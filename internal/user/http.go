package user

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"time"
	"ryubot/internal/pasino"
	"ryubot/internal/trading"
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
	mux.HandleFunc("GET /login", h.userPage)
	mux.HandleFunc("GET /register", h.userPage)
	mux.HandleFunc("GET /suspended", h.userPage)
	mux.HandleFunc("GET /subscribe", h.userPage)
	mux.HandleFunc("POST /api/user/login", h.login)
	mux.HandleFunc("POST /api/user/register", h.register)
	mux.Handle("POST /api/user/logout", h.require(http.HandlerFunc(h.logout)))
	mux.HandleFunc("GET /api/user/session", h.optionalSession)
	mux.Handle("GET /api/user/trading/settings", h.requireActive(http.HandlerFunc(h.getTradingSettings)))
	mux.Handle("PUT /api/user/trading/settings", h.requireActive(http.HandlerFunc(h.saveTradingSettings)))
	mux.Handle("GET /api/user/trading/status", h.requireActive(http.HandlerFunc(h.tradingStatus)))
	mux.Handle("POST /api/user/trading/stop", h.requireActive(http.HandlerFunc(h.stopTrading)))
	mux.Handle("POST /api/user/trading/start", h.requireActive(http.HandlerFunc(h.startTrading)))
	mux.Handle("POST /api/user/trading/command", h.requireActive(http.HandlerFunc(h.tradingCommand)))
	mux.Handle("GET /api/user/trading/history", h.requireActive(http.HandlerFunc(h.tradingHistory)))
	mux.Handle("GET /api/user/realtime", h.requireActive(http.HandlerFunc(h.realtime)))
	mux.Handle("GET /api/user/wallet/balance", h.requireActive(http.HandlerFunc(h.balance)))
	mux.Handle("GET /api/user/wallet/deposit-info", h.requireActive(http.HandlerFunc(h.depositInfo)))
	mux.Handle("GET /api/user/wallet/market-price", h.requireActive(http.HandlerFunc(h.marketPrice)))
	mux.Handle("GET /api/user/wallet/qr", h.requireActive(http.HandlerFunc(h.walletQR)))
	mux.Handle("GET /api/user/wallet/rules", h.requireActive(http.HandlerFunc(h.walletRules)))
	mux.Handle("GET /api/user/wallet/history", h.requireActive(http.HandlerFunc(h.walletHistory)))
	mux.Handle("POST /api/user/wallet/withdraw", h.requireActive(http.HandlerFunc(h.withdraw)))
	mux.Handle("POST /api/user/wallet/transfer", h.requireActive(http.HandlerFunc(h.transfer)))
	mux.Handle("POST /api/user/referral/bonus/claim", h.requireActive(http.HandlerFunc(h.claimReferralBonus)))
	mux.Handle("GET /api/user/referral", h.requireActive(http.HandlerFunc(h.referral)))
	mux.Handle("GET /api/user/referral/bonus", h.requireActive(http.HandlerFunc(h.referralBonus)))
	mux.Handle("PUT /api/user/profile/password", h.requireActive(http.HandlerFunc(h.changePassword)))
}

func (h *HTTP) require(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie(cookieName)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
		account, err := h.store.Authenticate(r.Context(), cookie.Value)
		if err != nil {
			if errors.Is(err, ErrUnauthenticated) {
				h.setCookie(w, "", -1)
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
				return
			}
			// Database/network failure: keep the cookie so a blip never logs the
			// user out. The frontend retries on the 500.
			h.logger.Error("session check failed", "error", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "session_check_failed"})
			return
		}
		// Re-issue the cookie on every authenticated response so the browser's
		// Max-Age never runs out while the app is in use (running bot tab).
		h.setCookie(w, cookie.Value, int(sessionLifetime.Seconds()))
		ctx := context.WithValue(r.Context(), accountKey, account)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func current(r *http.Request) Account {
	return r.Context().Value(accountKey).(Account)
}

// requireActive wraps require and blocks accounts that are suspended or whose
// subscription has expired, while logout and session stay reachable so the
// frontend can render the correct gate screen (suspended / subscribe).
func (h *HTTP) requireActive(next http.Handler) http.Handler {
	return h.require(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		account := current(r)
		if account.Status == "SUSPENDED" {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "suspended", "message": "Akun Anda ditangguhkan. Hubungi tim support."})
			return
		}
		if account.SubscriptionExpiresAt == nil || !account.SubscriptionExpiresAt.After(time.Now()) {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "subscription_expired", "message": "Masa aktif akun Anda berakhir. Silakan perpanjang langganan."})
			return
		}
		next.ServeHTTP(w, r)
	}))
}

func (h *HTTP) validCSRF(r *http.Request, account Account) bool {
	return account.CSRF != "" && r.Header.Get("X-CSRF-Token") == account.CSRF
}

func (h *HTTP) setCookie(w http.ResponseWriter, value string, maxAge int) {
	http.SetCookie(w, &http.Cookie{Name: cookieName, Value: value, Path: "/", HttpOnly: true, Secure: h.secure, SameSite: http.SameSiteStrictMode, MaxAge: maxAge})
}

func (h *HTTP) fail(w http.ResponseWriter, err error) {
	h.logger.Error("user request failed", "error", err)
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
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
