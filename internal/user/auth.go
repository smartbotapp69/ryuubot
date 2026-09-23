package user

import (
	"errors"
	"net/http"
	"strings"

	"ryubot/internal/pasino"
)

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
	if !decodeJSON(w, r, &body) { return }
	body.Username = strings.TrimSpace(body.Username)
	body.Email = strings.ToLower(strings.TrimSpace(body.Email))
	body.Referrer = strings.TrimSpace(body.Referrer)
	if len(body.Username) < 3 || len(body.Username) > 50 || !emailPattern.MatchString(body.Email) || len(body.Password) < 6 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_registration"})
		return
	}
	available, err := h.store.RegistrationAvailable(r.Context(), body.Username, body.Email)
	if err != nil { h.fail(w, err); return }
	if !available {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "duplicate_account"})
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
	if err != nil { h.fail(w, err); return }
	passwordCipher, err := h.provider.EncryptCredential(body.Password)
	if err != nil { h.fail(w, err); return }
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
		if errors.Is(err, ErrUnauthenticated) {
			h.setCookie(w, "", -1)
			writeJSON(w, http.StatusOK, map[string]any{"authenticated": false})
			return
		}
		// Infrastructure failure: never delete the cookie — answer 500 so the
		// frontend retries instead of treating it as a logout.
		h.logger.Error("session check failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"authenticated": false, "error": "session_check_failed"})
		return
	}
	// Slide the browser cookie forward; a running bot tab must not lose it by time.
	h.setCookie(w, cookie.Value, int(sessionLifetime.Seconds()))
	writeJSON(w, http.StatusOK, map[string]any{"authenticated": true, "user": account, "csrf_token": account.CSRF})
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
