package admin

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"golang.org/x/crypto/bcrypt"
)

func (h *HTTP) userAction(w http.ResponseWriter, r *http.Request) {
	admin := current(r)
	if err := r.ParseForm(); err != nil || !h.validCSRF(r, admin) {
		http.Error(w, "Request tidak valid", http.StatusBadRequest)
		return
	}
	userID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || userID <= 0 {
		http.Error(w, "User tidak valid", http.StatusBadRequest)
		return
	}
	action := strings.ToUpper(strings.TrimSpace(r.FormValue("action")))
	detail := map[string]any{}
	tx, err := h.store.pool.Begin(r.Context())
	if err != nil {
		h.fail(w, err)
		return
	}
	defer tx.Rollback(r.Context())
	switch action {
	case "EXTEND_SUBSCRIPTION":
		months, e := strconv.Atoi(r.FormValue("months"))
		if e != nil || months < 1 || months > 120 {
			err = errors.New("jumlah bulan tidak valid")
			break
		}
		detail["months"] = months
		_, err = tx.Exec(r.Context(), `UPDATE users SET subscription_expires_at=greatest(coalesce(subscription_expires_at,now()),now())+($2::int*interval '1 month'),status='ACTIVE',updated_at=now() WHERE id=$1`, userID, months)
	case "RESET_PASSWORD":
		password := r.FormValue("password")
		if len(password) < 6 {
			err = errors.New("password minimal 6 karakter")
			break
		}
		var hash []byte
		hash, err = bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
		if err == nil {
			_, err = tx.Exec(r.Context(), `UPDATE users SET password_hash=$2,updated_at=now() WHERE id=$1`, userID, string(hash))
			detail["sessions_revoked"] = true
			if err == nil {
				_, err = tx.Exec(r.Context(), `DELETE FROM user_sessions WHERE user_id=$1`, userID)
			}
		}
	case "SUSPEND":
		_, err = tx.Exec(r.Context(), `UPDATE users SET status='SUSPENDED',updated_at=now() WHERE id=$1`, userID)
		if err == nil {
			_, err = tx.Exec(r.Context(), `DELETE FROM user_sessions WHERE user_id=$1`, userID)
		}
		if err == nil {
			_, err = tx.Exec(r.Context(), `UPDATE trading_sessions SET status='STOP_REQUESTED',stop_reason='Akun disuspend admin',updated_at=now() WHERE user_id=$1 AND status='RUNNING'`, userID)
		}
	case "ACTIVATE":
		_, err = tx.Exec(r.Context(), `UPDATE users SET status='ACTIVE',updated_at=now() WHERE id=$1`, userID)
	default:
		err = errors.New("aksi tidak dikenal")
	}
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	raw, _ := json.Marshal(detail)
	if _, err = tx.Exec(r.Context(), `INSERT INTO admin_user_actions(admin_username,user_id,action,detail) VALUES($1,$2,$3,$4)`, admin.Username, userID, action, raw); err != nil {
		h.fail(w, err)
		return
	}
	if err = tx.Commit(r.Context()); err != nil {
		h.fail(w, err)
		return
	}
	returnTo := "/admin/users"
	if r.FormValue("return_to") == "subscriptions" {
		returnTo = "/admin/subscriptions"
	}
	http.Redirect(w, r, returnTo+"?saved=1", http.StatusSeeOther)
}
