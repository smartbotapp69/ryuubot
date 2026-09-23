package user

import (
	"context"
	"encoding/json"
	"errors"
	qrcode "github.com/skip2/go-qrcode"
	"math/big"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"ryubot/internal/pasino"
)

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
	// BalanceForDisplay falls back to the last known provider balance while
	// the Pasino socket is being re-established, so switching coins in the UI
	// keeps rendering a number instead of an intermittent error.
	balance, stale, err := h.provider.BalanceForDisplay(r.Context(), current(r).ID, coin)
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
	source := "pasino_live_net"
	if stale {
		source = "pasino_last_known"
	}
	writeJSON(w, http.StatusOK, map[string]any{"coin": coin, "balance": available, "provider_balance": balance, "reserved_fees": reserved, "source": source, "stale": stale})
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
	// Wallet mutations verify the live provider balance: the last-known
	// fallback used for display must never authorize moving money.
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
