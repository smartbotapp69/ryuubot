package user

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	qrcode "github.com/skip2/go-qrcode"
	"log/slog"
	"math/big"
	"net/http"
	"nhooyr.io/websocket"
	"nhooyr.io/websocket/wsjson"
	"regexp"
	"ryubot/internal/pasino"
	"ryubot/internal/trading"
	"strconv"
	"strings"
	"sync"
	"time"
)

type contextKey string

const accountKey contextKey = "user-account"
const cookieName = "ryubot_user"

var decimalPattern = regexp.MustCompile(`^[0-9]+(?:\.[0-9]{1,8})?$`)
var emailPattern = regexp.MustCompile(`^[^\s@]+@[^\s@]+\.[^\s@]+$`)

type HTTP struct {
	store    *Store
	provider *pasino.Client
	logger   *slog.Logger
	secure   bool
	engine   *trading.Engine
}

func NewHTTP(store *Store, provider *pasino.Client, engine *trading.Engine, logger *slog.Logger, secure bool) *HTTP {
	return &HTTP{store: store, provider: provider, engine: engine, logger: logger, secure: secure}
}

func (h *HTTP) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /", h.userPage)
	mux.HandleFunc("POST /api/user/login", h.login)
	mux.HandleFunc("POST /api/user/register", h.register)
	mux.Handle("POST /api/user/logout", h.require(http.HandlerFunc(h.logout)))
	mux.HandleFunc("GET /api/user/session", h.optionalSession)
	mux.Handle("GET /api/user/trading/settings", h.require(http.HandlerFunc(h.getTradingSettings)))
	mux.Handle("PUT /api/user/trading/settings", h.require(http.HandlerFunc(h.saveTradingSettings)))
	mux.Handle("GET /api/user/trading/status", h.require(http.HandlerFunc(h.tradingStatus)))
	mux.Handle("POST /api/user/trading/stop", h.require(http.HandlerFunc(h.stopTrading)))
	mux.Handle("POST /api/user/trading/start", h.require(http.HandlerFunc(h.startTrading)))
	mux.Handle("POST /api/user/trading/command", h.require(http.HandlerFunc(h.tradingCommand)))
	mux.Handle("GET /api/user/trading/history", h.require(http.HandlerFunc(h.tradingHistory)))
	mux.Handle("GET /api/user/realtime", h.require(http.HandlerFunc(h.realtime)))
	mux.Handle("GET /api/user/wallet/balance", h.require(http.HandlerFunc(h.balance)))
	mux.Handle("GET /api/user/wallet/deposit-info", h.require(http.HandlerFunc(h.depositInfo)))
	mux.Handle("GET /api/user/wallet/market-price", h.require(http.HandlerFunc(h.marketPrice)))
	mux.Handle("GET /api/user/wallet/qr", h.require(http.HandlerFunc(h.walletQR)))
	mux.Handle("GET /api/user/referral", h.require(http.HandlerFunc(h.referral)))
	mux.Handle("GET /api/user/referral/bonus", h.require(http.HandlerFunc(h.referralBonus)))
	mux.Handle("POST /api/user/referral/bonus/claim", h.require(http.HandlerFunc(h.claimReferralBonus)))
	mux.Handle("PUT /api/user/profile/password", h.require(http.HandlerFunc(h.changePassword)))
	mux.Handle("POST /api/user/wallet/withdraw", h.require(http.HandlerFunc(h.withdraw)))
	mux.Handle("POST /api/user/wallet/transfer", h.require(http.HandlerFunc(h.transfer)))
	mux.Handle("GET /api/user/wallet/rules", h.require(http.HandlerFunc(h.walletRules)))
	mux.Handle("GET /api/user/wallet/history", h.require(http.HandlerFunc(h.walletHistory)))
}

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
				providerBalance, readErr := h.provider.Balance(ctx, account.ID, request.coin)
				if readErr != nil {
					_ = write(map[string]any{"type": "balance_retry", "coin": request.coin, "request_id": request.requestID})
					continue
				}
				available, reserved, readErr := h.availableWalletBalance(ctx, account.ID, request.coin, providerBalance)
				if readErr != nil {
					_ = write(map[string]any{"type": "error", "message": readErr.Error(), "request_id": request.requestID})
					continue
				}
				_ = write(map[string]any{"type": "balance", "coin": request.coin, "balance": available, "provider_balance": providerBalance, "reserved_fees": reserved, "request_id": request.requestID})
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

func (h *HTTP) walletHistory(w http.ResponseWriter, r *http.Request) {
	operation := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("type")))
	if operation != "WITHDRAW" && operation != "TRANSFER" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_history_type", "message": "Jenis history tidak valid"})
		return
	}
	items, err := h.store.WalletHistory(r.Context(), current(r).ID, operation, 100)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *HTTP) login(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	token, account, err := h.store.Login(r.Context(), strings.TrimSpace(body.Username), body.Password)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_credentials", "message": "Username atau password tidak valid"})
		return
	}
	if err = h.provider.RefreshFromLogin(r.Context(), account.ID, body.Password); err != nil {
		h.store.Logout(r.Context(), token)
		if errors.Is(err, pasino.ErrUnauthorized) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "pasino_login_failed", "message": "Sesi Pasino tidak dapat diverifikasi"})
			return
		}
		h.fail(w, err)
		return
	}
	if err = h.store.MarkLogin(r.Context(), account.ID); err != nil {
		h.store.Logout(r.Context(), token)
		h.fail(w, err)
		return
	}
	h.setCookie(w, token, int(sessionLifetime.Seconds()))
	writeJSON(w, http.StatusOK, map[string]any{"user": account, "csrf_token": account.CSRF})
}
func (h *HTTP) register(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Username string `json:"username"`
		Email    string `json:"email"`
		Password string `json:"password"`
		Referrer string `json:"referrer"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	body.Username = strings.TrimSpace(body.Username)
	body.Email = strings.ToLower(strings.TrimSpace(body.Email))
	body.Referrer = strings.TrimSpace(body.Referrer)
	if len(body.Username) < 3 || len(body.Username) > 50 || !emailPattern.MatchString(body.Email) || len(body.Password) < 6 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_registration", "message": "Username, email, atau password tidak valid"})
		return
	}
	available, err := h.store.RegistrationAvailable(r.Context(), body.Username, body.Email)
	if err != nil {
		h.fail(w, err)
		return
	}
	if !available {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "duplicate_account", "message": "Username atau email sudah digunakan"})
		return
	}
	access, err := h.provider.RegisterAndLogin(r.Context(), body.Username, body.Email, body.Password)
	if err != nil {
		if errors.Is(err, pasino.ErrUnauthorized) {
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "pasino_registration_failed"})
			return
		}
		h.fail(w, err)
		return
	}
	accessCipher, err := h.provider.EncryptCredential(access)
	if err != nil {
		h.fail(w, err)
		return
	}
	passwordCipher, err := h.provider.EncryptCredential(body.Password)
	if err != nil {
		h.fail(w, err)
		return
	}
	token, account, err := h.store.Register(r.Context(), Registration{Username: body.Username, Email: body.Email, Password: body.Password, Referrer: body.Referrer, AccessTokenCiphertext: accessCipher, PasswordCiphertext: passwordCipher})
	if err != nil {
		if strings.Contains(err.Error(), "digunakan") {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "duplicate_account"})
			return
		}
		h.fail(w, err)
		return
	}
	h.setCookie(w, token, int(sessionLifetime.Seconds()))
	writeJSON(w, http.StatusCreated, map[string]any{"user": account, "csrf_token": account.CSRF})
}
func (h *HTTP) logout(w http.ResponseWriter, r *http.Request) {
	account := current(r)
	if !h.validCSRF(r, account) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_csrf"})
		return
	}
	if cookie, err := r.Cookie(cookieName); err == nil {
		h.store.Logout(r.Context(), cookie.Value)
	}
	h.setCookie(w, "", -1)
	writeJSON(w, http.StatusOK, map[string]bool{"logged_out": true})
}
func (h *HTTP) session(w http.ResponseWriter, r *http.Request) {
	account := current(r)
	writeJSON(w, http.StatusOK, map[string]any{"user": account, "csrf_token": account.CSRF})
}
func (h *HTTP) optionalSession(w http.ResponseWriter, r *http.Request) {
	cookie, err := r.Cookie(cookieName)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"authenticated": false})
		return
	}
	account, err := h.store.Authenticate(r.Context(), cookie.Value)
	if err != nil {
		h.setCookie(w, "", -1)
		writeJSON(w, http.StatusOK, map[string]any{"authenticated": false})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"authenticated": true, "user": account, "csrf_token": account.CSRF})
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
func (h *HTTP) balance(w http.ResponseWriter, r *http.Request) {
	coin := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("coin")))
	if coin == "" {
		coin = "TRX"
	}
	if coin != "TRX" && coin != "DOGE" && coin != "FLOKI" && coin != "BTT" && coin != "BTC" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported_coin"})
		return
	}
	if balance, status, active, err := h.store.ActiveTradingBalance(r.Context(), current(r).ID, coin); err != nil {
		h.fail(w, err)
		return
	} else if active {
		writeJSON(w, http.StatusOK, map[string]any{"coin": coin, "balance": balance, "source": "settlement_ledger", "trading_status": status, "reconciliation_required": status == "RECONCILIATION_REQUIRED"})
		return
	}
	balance, err := h.provider.Balance(r.Context(), current(r).ID, coin)
	if err != nil {
		if errors.Is(err, pasino.ErrUnauthorized) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "pasino_reconnect_required", "message": "Sesi Pasino perlu dihubungkan kembali"})
			return
		}
		h.logger.Error("Pasino balance failed", "user_id", current(r).ID, "coin", coin, "error", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "pasino_balance_unavailable", "message": "Saldo Pasino belum tersedia, silakan coba kembali"})
		return
	}
	available, reserved, err := h.availableWalletBalance(r.Context(), current(r).ID, coin, balance)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"coin": coin, "balance": available, "provider_balance": balance, "reserved_fees": reserved, "source": "pasino_live_net"})
}

func (h *HTTP) availableWalletBalance(ctx context.Context, userID int64, coin, providerBalance string) (string, string, error) {
	reserved, err := h.store.OutstandingTradingFees(ctx, userID, coin)
	if err != nil {
		return "", "", err
	}
	provider, validProvider := new(big.Rat).SetString(providerBalance)
	fees, validFees := new(big.Rat).SetString(reserved)
	if !validProvider || !validFees {
		return "", "", errors.New("saldo wallet tidak valid")
	}
	available := new(big.Rat).Sub(provider, fees)
	if available.Sign() < 0 {
		available.SetInt64(0)
	}
	return available.FloatString(8), fees.FloatString(8), nil
}
func (h *HTTP) walletRules(w http.ResponseWriter, r *http.Request) {
	coin := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("coin")))
	if coin != "TRX" && coin != "DOGE" && coin != "FLOKI" && coin != "BTT" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported_coin", "message": "Coin tidak didukung"})
		return
	}
	minimum, err := h.store.MinimumWithdrawal(r.Context(), coin)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"coin": coin, "minimum_withdrawal": minimum})
}
func (h *HTTP) depositInfo(w http.ResponseWriter, r *http.Request) {
	coin := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("coin")))
	if coin == "" {
		coin = "TRX"
	}
	if coin != "TRX" && coin != "DOGE" && coin != "FLOKI" && coin != "BTT" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported_coin", "message": "Coin tidak didukung"})
		return
	}
	info, err := h.provider.DepositInfo(r.Context(), current(r).ID, coin)
	if err != nil {
		if errors.Is(err, pasino.ErrUnauthorized) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "pasino_reconnect_required", "message": "Sesi Pasino perlu dihubungkan kembali"})
			return
		}
		h.logger.Error("Pasino deposit info failed", "user_id", current(r).ID, "coin", coin, "error", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "pasino_deposit_unavailable", "message": "Alamat deposit belum tersedia"})
		return
	}
	minimum, err := h.store.MinimumWithdrawal(r.Context(), coin)
	if err != nil {
		h.fail(w, err)
		return
	}
	info["coin"] = coin
	info["minimum_withdrawal"] = minimum
	writeJSON(w, http.StatusOK, info)
}
func (h *HTTP) walletQR(w http.ResponseWriter, r *http.Request) {
	address := strings.TrimSpace(r.URL.Query().Get("address"))
	if address == "" || len(address) > 512 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_address"})
		return
	}
	png, err := qrcode.Encode(address, qrcode.Medium, 256)
	if err != nil {
		h.fail(w, err)
		return
	}
	w.Header().Set("Content-Type", "image/png")
	w.Header().Set("Content-Length", strconv.Itoa(len(png)))
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(png)
}
func (h *HTTP) marketPrice(w http.ResponseWriter, r *http.Request) {
	coin := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("coin")))
	pairs := map[string]string{"TRX": "trx_idr", "DOGE": "doge_idr", "FLOKI": "floki_idr", "BTT": "btt_usdt"}
	pair, ok := pairs[coin]
	if !ok {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported_coin"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://indodax.com/api/ticker_all", nil)
	if err != nil {
		h.fail(w, err)
		return
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "market_unavailable", "message": "Harga Indodax belum tersedia"})
		return
	}
	defer response.Body.Close()
	var payload struct {
		Tickers map[string]struct {
			Last string `json:"last"`
		} `json:"tickers"`
	}
	if response.StatusCode != http.StatusOK || json.NewDecoder(response.Body).Decode(&payload) != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "market_unavailable", "message": "Harga Indodax belum tersedia"})
		return
	}
	price, ok := new(big.Rat).SetString(payload.Tickers[pair].Last)
	if !ok || price.Sign() <= 0 {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "market_unavailable", "message": "Harga Indodax belum lengkap"})
		return
	}
	if coin == "BTT" {
		usdt, valid := new(big.Rat).SetString(payload.Tickers["usdt_idr"].Last)
		if !valid || usdt.Sign() <= 0 {
			writeJSON(w, http.StatusBadGateway, map[string]string{"error": "market_unavailable", "message": "Harga Indodax belum lengkap"})
			return
		}
		price.Mul(price, usdt)
	}
	writeJSON(w, http.StatusOK, map[string]string{"coin": coin, "price_idr": price.FloatString(8), "source": "Indodax"})
}
func (h *HTTP) referral(w http.ResponseWriter, r *http.Request) {
	items, err := h.store.ReferralNetwork(r.Context(), current(r).ID)
	if err != nil {
		h.fail(w, err)
		return
	}
	counts := []int{0, 0, 0}
	downlines := make([]map[string]any, 0, len(items))
	for _, item := range items {
		if item.Level >= 1 && item.Level <= 3 {
			counts[item.Level-1]++
		}
		downlines = append(downlines, map[string]any{"id": item.ID, "username": item.Username, "level": item.Level, "downline_count": item.DownlineCount, "created_at": item.CreatedAt})
	}
	writeJSON(w, http.StatusOK, map[string]any{"level1": counts[0], "level2": counts[1], "level3": counts[2], "total": len(items), "downlines": downlines})
}
func (h *HTTP) referralBonus(w http.ResponseWriter, r *http.Request) {
	coin := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("coin")))
	if coin != "TRX" && coin != "DOGE" && coin != "FLOKI" && coin != "BTT" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported_coin"})
		return
	}
	available, claimed, minimum, events, err := h.store.ReferralBonus(r.Context(), current(r).ID, coin)
	if err != nil {
		h.fail(w, err)
		return
	}
	history := make([]map[string]any, 0, len(events))
	levels := []string{"0", "0", "0"}
	for _, event := range events {
		history = append(history, map[string]any{"id": event.ID, "amount": event.Amount, "event_type": event.EventType, "level": event.Level, "occurred_at": event.OccurredAt})
		if event.EventType == "TRADING_ACCRUAL" && event.Level >= 1 && event.Level <= 3 {
			a, _ := new(big.Rat).SetString(levels[event.Level-1])
			b, _ := new(big.Rat).SetString(event.Amount)
			a.Add(a, b)
			levels[event.Level-1] = a.FloatString(8)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"coin": coin, "available": available, "claimed": claimed, "minimum_claim": minimum, "levels": levels, "history": history})
}
func (h *HTTP) claimReferralBonus(w http.ResponseWriter, r *http.Request) {
	account := current(r)
	if !h.validCSRF(r, account) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_csrf"})
		return
	}
	var body struct {
		Coin string `json:"coin"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	coin := strings.ToUpper(strings.TrimSpace(body.Coin))
	if coin != "TRX" && coin != "DOGE" && coin != "FLOKI" && coin != "BTT" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported_coin"})
		return
	}
	available, _, minimum, _, err := h.store.ReferralBonus(r.Context(), account.ID, coin)
	if err != nil {
		h.fail(w, err)
		return
	}
	avail, _ := trading.ParseMoney(available)
	minClaim, _ := trading.ParseMoney(minimum)
	if avail < minClaim {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "below_minimum_claim", "message": "Bonus belum mencapai minimum klaim"})
		return
	}
	claimedAmount, err := h.store.ClaimBonus(r.Context(), account.ID, coin)
	if err != nil {
		h.fail(w, err)
		return
	}
	collectorUsername, err := h.store.GetCollectorUsername(r.Context())
	if err != nil {
		h.logger.Error("get collector username failed", "error", err)
		writeJSON(w, http.StatusOK, map[string]any{"success": true, "claimed": claimedAmount})
		return
	}
	collectorID, err := h.store.GetUserID(r.Context(), collectorUsername)
	if err != nil {
		h.logger.Error("get collector user id failed", "error", err)
		writeJSON(w, http.StatusOK, map[string]any{"success": true, "claimed": claimedAmount})
		return
	}
	response, transferErr := h.provider.Transfer(r.Context(), collectorID, coin, account.Username, claimedAmount)
	if transferErr != nil {
		h.logger.Error("transfer bonus failed", "error", transferErr)
		writeJSON(w, http.StatusOK, map[string]any{"success": true, "claimed": claimedAmount, "warning": "transfer gagal, perlu verifikasi manual"})
		return
	}
	_ = response
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "claimed": claimedAmount})
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
func (h *HTTP) changePassword(w http.ResponseWriter, r *http.Request) {
	account := current(r)
	if !h.validCSRF(r, account) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_csrf"})
		return
	}
	var body struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	if len(body.NewPassword) < 8 || len(body.NewPassword) > 72 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_password", "message": "Password baru minimal 8 karakter"})
		return
	}
	if err := h.store.ChangePassword(r.Context(), account.ID, body.CurrentPassword, body.NewPassword); err != nil {
		if strings.Contains(err.Error(), "tidak valid") {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid_current_password", "message": "Password saat ini tidak valid"})
			return
		}
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "Password berhasil diperbarui"})
}

func (h *HTTP) require(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie(cookieName)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthenticated"})
			return
		}
		account, err := h.store.Authenticate(r.Context(), cookie.Value)
		if err != nil {
			h.setCookie(w, "", -1)
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthenticated"})
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), accountKey, account)))
	})
}
func current(r *http.Request) Account {
	account, _ := r.Context().Value(accountKey).(Account)
	return account
}
func (h *HTTP) validCSRF(r *http.Request, account Account) bool {
	return account.CSRF != "" && r.Header.Get("X-CSRF-Token") == account.CSRF
}
func (h *HTTP) setCookie(w http.ResponseWriter, value string, maxAge int) {
	http.SetCookie(w, &http.Cookie{Name: cookieName, Value: value, Path: "/", HttpOnly: true, Secure: h.secure, SameSite: http.SameSiteStrictMode, MaxAge: maxAge})
}
func (h *HTTP) fail(w http.ResponseWriter, err error) {
	h.logger.Error("user request failed", "error", err)
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal_error"})
}
func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func decodeJSON(w http.ResponseWriter, r *http.Request, target any) bool {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_json"})
		return false
	}
	return true
}

func (h *HTTP) withdraw(w http.ResponseWriter, r *http.Request) { h.walletOperation(w, r, "WITHDRAW") }
func (h *HTTP) transfer(w http.ResponseWriter, r *http.Request) { h.walletOperation(w, r, "TRANSFER") }
func (h *HTTP) walletOperation(w http.ResponseWriter, r *http.Request, operation string) {
	account := current(r)
	if !h.validCSRF(r, account) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "invalid_csrf"})
		return
	}
	var body struct {
		Coin      string `json:"coin"`
		Amount    string `json:"amount"`
		Address   string `json:"address"`
		To        string `json:"to"`
		RequestID string `json:"request_id"`
	}
	if !decodeJSON(w, r, &body) {
		return
	}
	coin := strings.ToUpper(strings.TrimSpace(body.Coin))
	amount := strings.TrimSpace(body.Amount)
	destination := strings.TrimSpace(body.To)
	if operation == "WITHDRAW" {
		destination = strings.TrimSpace(body.Address)
	}
	if coin != "TRX" && coin != "DOGE" && coin != "FLOKI" && coin != "BTT" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unsupported_coin", "message": "Coin tidak didukung"})
		return
	}
	if !decimalPattern.MatchString(amount) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_amount", "message": "Nominal tidak valid"})
		return
	}
	amountRat, ok := new(big.Rat).SetString(amount)
	if !ok || amountRat.Sign() <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_amount", "message": "Nominal harus lebih dari nol"})
		return
	}
	// Preserve the legacy Pasino contract: wallet amounts are always sent and
	// persisted as fixed 8-decimal strings.
	amount = amountRat.FloatString(8)
	amountRat, _ = new(big.Rat).SetString(amount)
	if !regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$`).MatchString(body.RequestID) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_request_id", "message": "Request ID tidak valid"})
		return
	}
	if destination == "" || len(destination) > 512 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_destination", "message": "Tujuan transaksi wajib diisi"})
		return
	}
	if operation == "TRANSFER" && !regexp.MustCompile(`^[A-Za-z0-9_.-]{1,50}$`).MatchString(destination) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_username", "message": "Format username tujuan tidak valid"})
		return
	}
	active, err := h.store.HasActiveTrading(r.Context(), account.ID)
	if err != nil {
		h.fail(w, err)
		return
	}
	if active {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "trading_active", "message": "Selesaikan sesi trading sebelum melakukan transaksi"})
		return
	}
	if operation == "WITHDRAW" {
		minimum, minimumErr := h.store.MinimumWithdrawal(r.Context(), coin)
		if minimumErr != nil {
			h.fail(w, minimumErr)
			return
		}
		minimumRat, _ := new(big.Rat).SetString(minimum)
		if amountRat.Cmp(minimumRat) < 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "below_minimum", "message": "Minimum withdraw " + minimum + " " + coin})
			return
		}
	}
	balance, balanceErr := h.provider.Balance(r.Context(), account.ID, coin)
	if balanceErr != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "balance_unavailable", "message": "Saldo belum dapat diverifikasi"})
		return
	}
	availableBalance, _, availableErr := h.availableWalletBalance(r.Context(), account.ID, coin, balance)
	if availableErr != nil {
		h.fail(w, availableErr)
		return
	}
	balanceRat, valid := new(big.Rat).SetString(availableBalance)
	if !valid || balanceRat.Cmp(amountRat) < 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "insufficient_balance", "message": "Saldo tidak mencukupi"})
		return
	}
	existing, reused, err := h.store.BeginWalletOperation(r.Context(), body.RequestID, account.ID, operation, coin, amount, destination)
	if err != nil {
		h.logger.Error("wallet ledger rejected operation", "user_id", account.ID, "operation", operation, "coin", coin, "error", err)
		writeJSON(w, http.StatusConflict, map[string]string{"error": "wallet_ledger_conflict", "message": "Transaksi sebelumnya belum dibersihkan. Jalankan migration terbaru."})
		return
	}
	if reused {
		if existing.Status == "COMPLETED" {
			var data any
			_ = json.Unmarshal(existing.ProviderResponse, &data)
			writeJSON(w, http.StatusOK, map[string]any{"success": true, "reused": true, "data": data})
			return
		}
		writeJSON(w, http.StatusConflict, map[string]string{"error": "duplicate_request", "message": "Transaksi ini sudah pernah diproses"})
		return
	}
	var result map[string]any
	if operation == "WITHDRAW" {
		result, err = h.provider.Withdraw(r.Context(), account.ID, coin, destination, amount)
	} else {
		result, err = h.provider.Transfer(r.Context(), account.ID, coin, destination, amount)
	}
	if err != nil {
		_ = h.store.FinishWalletOperation(r.Context(), body.RequestID, "FAILED", nil, err.Error())
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "provider_rejected", "message": err.Error()})
		return
	}
	raw, _ := json.Marshal(result)
	if err = h.store.FinishWalletOperation(r.Context(), body.RequestID, "COMPLETED", raw, ""); err != nil {
		// Pasino sudah menyatakan transaksi berhasil. Jangan mengubah hasilnya
		// menjadi HTTP 500 karena penyimpanan response mentah ke ledger gagal.
		// Coba selesaikan ledger tanpa response sebagai jalur pemulihan.
		h.logger.Error("wallet provider succeeded but response persistence failed", "request_id", body.RequestID, "user_id", account.ID, "operation", operation, "error", err)
		if retryErr := h.store.FinishWalletOperation(r.Context(), body.RequestID, "COMPLETED", nil, ""); retryErr != nil {
			h.logger.Error("wallet completion recovery failed", "request_id", body.RequestID, "user_id", account.ID, "operation", operation, "error", retryErr)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"success": true, "data": result})
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
	}{{"delay_ms", &base.DelayMS, 100, 3600000}, {"reset_after_wins", &base.ResetAfterWins, 0, 100000}, {"reset_after_losses", &base.ResetAfterLosses, 0, 100000}, {"boom_after_wins", &base.BoomAfterWins, 0, 100000}, {"boom_after_losses", &base.BoomAfterLosses, 0, 100000}} {
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
func valueString(value any) string {
	switch v := value.(type) {
	case string:
		return v
	case json.Number:
		return v.String()
	default:
		return ""
	}
}
