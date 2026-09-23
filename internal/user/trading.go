package user

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"nhooyr.io/websocket"
	"nhooyr.io/websocket/wsjson"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

func (h *HTTP) realtime(w http.ResponseWriter, r *http.Request) {
	account := current(r)
	connection, err := websocket.Accept(w, r, &websocket.AcceptOptions{CompressionMode: websocket.CompressionContextTakeover})
	if err != nil {
		return
	}
	defer connection.Close(websocket.StatusNormalClosure, "closed")
	connection.SetReadLimit(4096)
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	var writeMu sync.Mutex
	write := func(value any) error {
		writeMu.Lock()
		defer writeMu.Unlock()
		return wsjson.Write(ctx, connection, value)
	}
	events, unsubscribe := h.engine.Subscribe(account.ID)
	defer unsubscribe()
	type balanceRequest struct{ coin, requestID string }
	// Browser requests are kept in order. The provider client serializes them
	// on the one Pasino socket and deduplicates equal user/coin reads.
	balanceRequests := make(chan balanceRequest, 8)
	go func() {
		for {
			select {
			case request := <-balanceRequests:
				if balance, status, active, readErr := h.store.ActiveTradingBalance(ctx, account.ID, request.coin); readErr == nil && active {
					_ = write(map[string]any{"type": "balance", "coin": request.coin, "balance": balance, "status": status, "request_id": request.requestID})
					continue
				}
				providerBalance, stale, readErr := h.provider.BalanceForDisplay(ctx, account.ID, request.coin)
				if readErr != nil {
					_ = write(map[string]any{"type": "balance_retry", "coin": request.coin, "request_id": request.requestID})
					continue
				}
				available, reserved, readErr := h.availableWalletBalance(ctx, account.ID, request.coin, providerBalance)
				if readErr != nil {
					_ = write(map[string]any{"type": "error", "message": readErr.Error(), "request_id": request.requestID})
					continue
				}
				_ = write(map[string]any{"type": "balance", "coin": request.coin, "balance": available, "provider_balance": providerBalance, "reserved_fees": reserved, "stale": stale, "request_id": request.requestID})
			case <-ctx.Done():
				return
			}
		}
	}()
	go func() {
		for event := range events {
			message := map[string]any{"type": "trading_event", "event": event}
			if event.Type == "COMMAND_RESULT" {
				var result map[string]any
				_ = json.Unmarshal(event.Payload, &result)
				message = result
				message["type"] = "command_result"
			} else if event.Type == "RUNNER_STATE" {
				var state map[string]any
				_ = json.Unmarshal(event.Payload, &state)
				message = state
				// START already has one durable COMMAND_RESULT. Do not make the UI
				// reload status/settings/history a second time for the same start.
				// Terminal states still trigger one refresh so controls return to START.
				if state["status"] == "RUNNING" {
					message["type"] = "runner_state"
				} else {
					message["type"] = "command_result"
				}
				message["command"] = "state"
				message["ok"] = true
			}
			if write(message) != nil {
				cancel()
				return
			}
		}
	}()
	for ctx.Err() == nil {
		var message struct {
			Type, Command, Coin, Amount, RequestID string
			Enabled                                bool
		}
		if err = wsjson.Read(ctx, connection, &message); err != nil {
			return
		}
		switch message.Type {
		case "get_balance":
			coin := strings.ToUpper(strings.TrimSpace(message.Coin))
			if coin != "TRX" && coin != "DOGE" && coin != "FLOKI" && coin != "BTT" {
				_ = write(map[string]any{"type": "error", "message": "Coin tidak didukung"})
				continue
			}
			request := balanceRequest{coin: coin, requestID: message.RequestID}
			select {
			case balanceRequests <- request:
			case <-ctx.Done():
				return
			}
		case "start_runner":
			requestID := validRequestID(message.RequestID)
			payload, _ := json.Marshal(map[string]any{"enabled": message.Enabled})
			_, _, enqueueErr := h.engine.Enqueue(ctx, requestID, account.ID, "START", payload)
			_ = write(map[string]any{"type": "command_queued", "command": "START", "request_id": requestID, "ok": enqueueErr == nil, "message": errorText(enqueueErr)})
		case "stop_runner":
			requestID := validRequestID(message.RequestID)
			_, _, enqueueErr := h.engine.Enqueue(ctx, requestID, account.ID, "STOP", nil)
			_ = write(map[string]any{"type": "command_queued", "command": "STOP", "request_id": requestID, "ok": enqueueErr == nil, "message": errorText(enqueueErr)})
		case "runner_command":
			requestID := validRequestID(message.RequestID)
			payload, _ := json.Marshal(map[string]any{"amount": message.Amount, "enabled": message.Enabled})
			_, _, enqueueErr := h.engine.Enqueue(ctx, requestID, account.ID, strings.ToUpper(message.Command), payload)
			_ = write(map[string]any{"type": "command_queued", "command": message.Command, "request_id": requestID, "ok": enqueueErr == nil, "message": errorText(enqueueErr)})
		case "ping":
			_ = write(map[string]string{"type": "pong"})
		}
	}
}

func validRequestID(value string) string {
	if matched, _ := regexp.MatchString(`^[0-9a-fA-F-]{36}$`, value); matched {
		return value
	}
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 15) | 64
	b[8] = (b[8] & 63) | 128
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func errorText(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func (h *HTTP) tradingEvents(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "stream_unsupported"})
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache, no-store")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")
	events, unsubscribe := h.engine.Subscribe(current(r).ID)
	defer unsubscribe()
	fmt.Fprint(w, ": connected\n\n")
	if lastID, parseErr := strconv.ParseInt(r.Header.Get("Last-Event-ID"), 10, 64); parseErr == nil && lastID > 0 {
		if missed, historyErr := h.engine.EventsAfter(r.Context(), current(r).ID, lastID); historyErr == nil {
			for _, event := range missed {
				encoded, _ := json.Marshal(event)
				fmt.Fprintf(w, "id: %d\nevent: trading\ndata: %s\n\n", event.ID, encoded)
			}
		}
	}
	flusher.Flush()
	keepAlive := time.NewTicker(20 * time.Second)
	defer keepAlive.Stop()
	for {
		select {
		case event := <-events:
			encoded, _ := json.Marshal(event)
			fmt.Fprintf(w, "id: %d\nevent: trading\ndata: %s\n\n", event.ID, encoded)
			flusher.Flush()
		case <-keepAlive.C:
			fmt.Fprint(w, ": keepalive\n\n")
			flusher.Flush()
		case <-r.Context().Done():
			return
		}
	}
}

func (h *HTTP) tradingCommand(w http.ResponseWriter, r *http.Request) {
	account := current(r)
	if !h.validCSRF(r, account) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_csrf"})
		return
	}
	var body struct {
		Command, Amount string
		Enabled         bool
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	if err := h.engine.Command(r.Context(), account.ID, body.Command, body.Amount, body.Enabled); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "trading_command_failed", "message": err.Error()})
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]bool{"success": true})
}

func (h *HTTP) startTrading(w http.ResponseWriter, r *http.Request) {
	account := current(r)
	if !h.validCSRF(r, account) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_csrf"})
		return
	}
	sessionID, err := h.engine.Start(r.Context(), account.ID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "trading_start_failed", "message": err.Error()})
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{"success": true, "session_id": sessionID})
}

func (h *HTTP) getTradingSettings(w http.ResponseWriter, r *http.Request) {
	settings, err := h.store.TradingSettings(r.Context(), current(r).ID)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"settings": settings})
}

func (h *HTTP) tradingStatus(w http.ResponseWriter, r *http.Request) {
	status, err := h.store.TradingStatus(r.Context(), current(r).ID)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"trading": status})
}

func (h *HTTP) stopTrading(w http.ResponseWriter, r *http.Request) {
	account := current(r)
	if !h.validCSRF(r, account) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_csrf"})
		return
	}
	requested, err := h.store.RequestTradingStop(r.Context(), account.ID)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"requested": requested, "status": map[bool]string{true: "STOP_REQUESTED", false: "IDLE"}[requested]})
}

func (h *HTTP) tradingHistory(w http.ResponseWriter, r *http.Request) {
	items, err := h.store.BetHistory(r.Context(), current(r).ID, 50)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"bets": items})
}

func (h *HTTP) saveTradingSettings(w http.ResponseWriter, r *http.Request) {
	account := current(r)
	if !h.validCSRF(r, account) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_csrf"})
		return
	}
	existing, err := h.store.TradingSettings(r.Context(), account.ID)
	if err != nil {
		h.fail(w, err)
		return
	}
	settings, err := decodeTradingSettings(w, r, existing)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_settings", "message": err.Error()})
		return
	}
	if err = h.store.SaveTradingSettings(r.Context(), account.ID, settings); err != nil {
		h.fail(w, err)
		return
	}
	if err = h.engine.SyncSettings(r.Context(), account.ID); err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"saved": true, "applies": "next_roll", "settings": settings})
}

func decodeTradingSettings(w http.ResponseWriter, r *http.Request, base TradingSettings) (TradingSettings, error) {
	decoder := json.NewDecoder(r.Body)
	decoder.UseNumber()
	var raw map[string]any
	if err := decoder.Decode(&raw); err != nil {
		return TradingSettings{}, errors.New("JSON tidak valid")
	}
	getText := func(key, current string) (string, error) {
		if raw[key] == nil {
			return current, nil
		}
		v := strings.TrimSpace(valueString(raw[key]))
		if !decimalPattern.MatchString(v) {
			return "", errors.New(key + " tidak valid")
		}
		q, ok := new(big.Rat).SetString(v)
		if !ok || q.Sign() < 0 {
			return "", errors.New(key + " tidak valid")
		}
		return v, nil
	}
	getInt := func(key string, current, min, max int) (int, error) {
		if raw[key] == nil {
			return current, nil
		}
		n, err := strconv.Atoi(valueString(raw[key]))
		if err != nil || n < min || n > max {
			return 0, errors.New(key + " tidak valid")
		}
		return n, nil
	}
	var err error
	if raw["coin"] != nil {
		base.Coin = strings.ToUpper(strings.TrimSpace(valueString(raw["coin"])))
		if base.Coin != "TRX" && base.Coin != "DOGE" && base.Coin != "FLOKI" && base.Coin != "BTT" && base.Coin != "BTC" {
			return base, errors.New("coin tidak didukung")
		}
	}
	for _, field := range []struct {
		key string
		dst *string
	}{{"base_bet", &base.BaseBet}, {"chance_min", &base.ChanceMin}, {"chance_max", &base.ChanceMax}, {"martingale_on_win", &base.MartingaleOnWin}, {"martingale_on_loss", &base.MartingaleOnLoss}, {"boom_win_amount", &base.BoomWinAmount}, {"boom_loss_amount", &base.BoomLossAmount}, {"take_profit", &base.TakeProfit}, {"stop_loss", &base.StopLoss}, {"profit_session", &base.ProfitSession}, {"balance_below", &base.BalanceBelow}, {"maximum_bet", &base.MaximumBet}} {
		if *field.dst, err = getText(field.key, *field.dst); err != nil {
			return base, err
		}
	}
	for _, field := range []*string{&base.MartingaleOnWin, &base.MartingaleOnLoss} {
		value, ok := new(big.Rat).SetString(*field)
		if !ok || !value.IsInt() || value.Sign() < 0 || value.Cmp(big.NewRat(100, 1)) > 0 {
			return base, errors.New("martingale harus bilangan bulat 0 sampai 100")
		}
		*field = value.Num().String()
	}
	for _, field := range []struct {
		key      string
		dst      *int
		min, max int
	}{{"delay_ms", &base.DelayMS, 100, 600000}, {"reset_after_wins", &base.ResetAfterWins, 0, 100000}, {"reset_after_losses", &base.ResetAfterLosses, 0, 100000}, {"boom_after_wins", &base.BoomAfterWins, 0, 100000}, {"boom_after_losses", &base.BoomAfterLosses, 0, 100000}} {
		if *field.dst, err = getInt(field.key, *field.dst, field.min, field.max); err != nil {
			return base, err
		}
	}
	if raw["stop_on_win"] != nil {
		value, ok := raw["stop_on_win"].(bool)
		if !ok {
			return base, errors.New("stop_on_win tidak valid")
		}
		base.StopOnWin = value
	}
	min, _ := new(big.Rat).SetString(base.ChanceMin)
	max, _ := new(big.Rat).SetString(base.ChanceMax)
	zero := new(big.Rat)
	hundred := big.NewRat(100, 1)
	if !min.IsInt() || !max.IsInt() || min.Cmp(zero) <= 0 || max.Cmp(min) < 0 || max.Cmp(big.NewRat(94, 1)) > 0 || max.Cmp(hundred) >= 0 {
		return base, errors.New("chance harus bilangan bulat 1 sampai 94")
	}
	base.ChanceMin, base.ChanceMax = min.Num().String(), max.Num().String()
	baseBet, _ := new(big.Rat).SetString(base.BaseBet)
	if baseBet.Cmp(zero) <= 0 {
		return base, errors.New("base_bet harus lebih dari nol")
	}
	return base, nil
}
