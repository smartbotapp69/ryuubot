package user

import (
	"math/big"
	"net/http"
	"strings"

	"ryubot/internal/trading"
)

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
