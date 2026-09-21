package admin

import (
	"context"
	"crypto/subtle"
	"html/template"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"ryubot/internal/pasino"
)

type contextKey string

const adminKey contextKey = "admin"
const cookieName = "ryubot_admin"

type HTTP struct {
	store      *Store
	logger     *slog.Logger
	secure     bool
	template   *template.Template
	username   string
	password   string
	provider   *pasino.Client
	sessionsMu sync.Mutex
	sessions   map[string]adminSession
}

type adminSession struct {
	admin     Admin
	expiresAt time.Time
}

func NewHTTP(store *Store, provider *pasino.Client, logger *slog.Logger, secure bool, username, password string) *HTTP {
	return &HTTP{store: store, provider: provider, logger: logger, secure: secure, username: username, password: password, sessions: make(map[string]adminSession), template: template.Must(template.New("panel").Parse(simplePanelTemplate))}
}

func (h *HTTP) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /admin/login", h.loginPage)
	mux.HandleFunc("POST /admin/login", h.login)
	mux.Handle("GET /admin/", h.require(http.HandlerFunc(h.dashboard)))
	mux.Handle("GET /admin/cutoffs/estimate", h.require(http.HandlerFunc(h.cutoffEstimate)))
	mux.Handle("GET /admin/{page}", h.require(http.HandlerFunc(h.placeholderPage)))
	mux.Handle("POST /admin/users/{id}/action", h.require(http.HandlerFunc(h.userAction)))
	mux.Handle("POST /admin/rules/save", h.require(http.HandlerFunc(h.saveRules)))
	mux.Handle("GET /admin/settings/{category}", h.require(http.HandlerFunc(h.settingsPage)))
	mux.Handle("POST /admin/settings/{category}", h.require(http.HandlerFunc(h.saveSettings)))
	mux.Handle("POST /admin/logout", h.require(http.HandlerFunc(h.logout)))
}

func (h *HTTP) loginPage(w http.ResponseWriter, r *http.Request) { h.render(w, pageData{Login: true}) }
func (h *HTTP) login(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "request tidak valid", 400)
		return
	}
	username, password := r.FormValue("username"), r.FormValue("password")
	if subtle.ConstantTimeCompare([]byte(username), []byte(h.username)) != 1 || subtle.ConstantTimeCompare([]byte(password), []byte(h.password)) != 1 {
		h.render(w, pageData{Login: true, Error: "Username atau password salah"})
		return
	}
	token, err := randomToken(32)
	if err != nil {
		h.fail(w, err)
		return
	}
	csrf, err := randomToken(24)
	if err != nil {
		h.fail(w, err)
		return
	}
	h.sessionsMu.Lock()
	h.sessions[token] = adminSession{admin: Admin{Username: h.username, CSRF: csrf}, expiresAt: time.Now().Add(8 * time.Hour)}
	h.sessionsMu.Unlock()
	h.setCookie(w, token, 8*60*60)
	http.Redirect(w, r, "/admin/", http.StatusSeeOther)
}

func (h *HTTP) panel(w http.ResponseWriter, r *http.Request) {
	http.Redirect(w, r, "/admin/settings/trading", http.StatusSeeOther)
}
func (h *HTTP) saveRules(w http.ResponseWriter, r *http.Request) {
	admin := current(r)
	if !h.validCSRF(r, admin) {
		http.Error(w, "CSRF tidak valid", http.StatusForbidden)
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, "request tidak valid", 400)
		return
	}
	rules, err := rulesFromForm(r)
	if err != nil {
		h.render(w, pageData{Admin: admin, Rules: rules, Error: err.Error()})
		return
	}
	if err = h.store.SaveRules(r.Context(), admin.ID, rules); err != nil {
		h.render(w, pageData{Admin: admin, Rules: rules, Error: "Aturan ditolak: " + safeDBError(err)})
		return
	}
	http.Redirect(w, r, "/admin/?saved=1", http.StatusSeeOther)
}
func (h *HTTP) logout(w http.ResponseWriter, r *http.Request) {
	admin := current(r)
	if !h.validCSRF(r, admin) {
		http.Error(w, "CSRF tidak valid", 403)
		return
	}
	cookie, _ := r.Cookie(cookieName)
	if cookie != nil {
		h.sessionsMu.Lock()
		delete(h.sessions, cookie.Value)
		h.sessionsMu.Unlock()
	}
	h.setCookie(w, "", -1)
	http.Redirect(w, r, "/admin/login", 303)
}

func (h *HTTP) require(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie(cookieName)
		if err != nil {
			http.Redirect(w, r, "/admin/login", 303)
			return
		}
		h.sessionsMu.Lock()
		session, ok := h.sessions[cookie.Value]
		if ok && time.Now().After(session.expiresAt) {
			delete(h.sessions, cookie.Value)
			ok = false
		}
		h.sessionsMu.Unlock()
		if !ok {
			h.setCookie(w, "", -1)
			http.Redirect(w, r, "/admin/login", 303)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), adminKey, session.admin)))
	})
}
func current(r *http.Request) Admin { admin, _ := r.Context().Value(adminKey).(Admin); return admin }
func (h *HTTP) validCSRF(r *http.Request, a Admin) bool {
	return r.FormValue("csrf") == a.CSRF && a.CSRF != ""
}
func (h *HTTP) setCookie(w http.ResponseWriter, value string, maxAge int) {
	http.SetCookie(w, &http.Cookie{Name: cookieName, Value: value, Path: "/admin", HttpOnly: true, Secure: h.secure, SameSite: http.SameSiteStrictMode, MaxAge: maxAge})
}
func (h *HTTP) fail(w http.ResponseWriter, err error) {
	h.logger.Error("admin request failed", "error", err)
	http.Error(w, "Terjadi kesalahan internal", 500)
}
func (h *HTTP) render(w http.ResponseWriter, data pageData) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := h.template.Execute(w, data); err != nil {
		h.logger.Error("render admin", "error", err)
	}
}

type pageData struct {
	Login bool
	Admin Admin
	Rules Rules
	Error string
	Saved bool
}

func rulesFromForm(request *http.Request) (Rules, error) {
	trial, err := strconv.Atoi(request.FormValue("trial_days"))
	if err != nil || trial < 0 {
		return Rules{}, strconv.ErrSyntax
	}
	rules := Rules{Status: "ACTIVE", UserPercent: request.FormValue("user_percent"), HoldingPercent: request.FormValue("holding_percent"), KangdenPercent: request.FormValue("kangden_percent"), FeeExemptUsername: strings.TrimSpace(request.FormValue("fee_exempt_username")), Referral1: request.FormValue("referral_1"), Referral2: request.FormValue("referral_2"), Referral3: request.FormValue("referral_3"), SubscriptionPrice: request.FormValue("subscription_price"), UplineReward: request.FormValue("upline_reward"), ManagementAmount: request.FormValue("management_amount"), TrialDays: trial, OwnerNana: request.FormValue("owner_nana"), OwnerDeni: request.FormValue("owner_deni"), OwnerArya: request.FormValue("owner_arya"), Operational: request.FormValue("operational"), Timezone: strings.TrimSpace(request.FormValue("timezone")), Cutoff1: request.FormValue("cutoff_1"), Cutoff2: request.FormValue("cutoff_2")}
	if rules.FeeExemptUsername == "" || rules.Timezone == "" {
		return rules, &validationError{"Username bebas fee dan zona waktu wajib diisi"}
	}
	return rules, nil
}

type validationError struct{ message string }

func (e *validationError) Error() string { return e.message }
func safeDBError(error) string           { return "periksa total persentase dan seluruh nominal" }

