package user

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

const sessionLifetime = 30 * 24 * time.Hour

type Store struct{ pool *pgxpool.Pool }

type Account struct {
	ID                    int64      `json:"id"`
	Username              string     `json:"username"`
	Email                 string     `json:"email"`
	CSRF                  string     `json:"csrf_token,omitempty"`
	SubscriptionExpiresAt *time.Time `json:"subscription_expires_at,omitempty"`
}
type Registration struct{ Username, Email, Password, Referrer, AccessTokenCiphertext, PasswordCiphertext string }

type TradingSettings struct {
	Coin             string `json:"coin"`
	BaseBet          string `json:"base_bet"`
	ChanceMin        string `json:"chance_min"`
	ChanceMax        string `json:"chance_max"`
	DelayMS          int    `json:"delay_ms"`
	MartingaleOnWin  string `json:"martingale_on_win"`
	MartingaleOnLoss string `json:"martingale_on_loss"`
	ResetAfterWins   int    `json:"reset_after_wins"`
	ResetAfterLosses int    `json:"reset_after_losses"`
	BoomAfterWins    int    `json:"boom_after_wins"`
	BoomWinAmount    string `json:"boom_win_amount"`
	BoomAfterLosses  int    `json:"boom_after_losses"`
	BoomLossAmount   string `json:"boom_loss_amount"`
	TakeProfit       string `json:"take_profit"`
	StopLoss         string `json:"stop_loss"`
	ProfitSession    string `json:"profit_session"`
	BalanceBelow     string `json:"balance_below"`
	StopOnWin        bool   `json:"stop_on_win"`
	MaximumBet       string `json:"maximum_bet"`
}
type TradingStatus struct {
	Status         string `json:"status"`
	SessionID      string `json:"session_id,omitempty"`
	Coin           string `json:"coin,omitempty"`
	CurrentBet     string `json:"current_bet,omitempty"`
	Profit         string `json:"profit,omitempty"`
	VisibleBalance string `json:"visible_balance,omitempty"`
	StopReason     string `json:"stop_reason,omitempty"`
	Wins           int    `json:"wins"`
	Losses         int    `json:"losses"`
	Rolls          int    `json:"rolls"`
	TotalWins      int    `json:"total_wins"`
	TotalLosses    int    `json:"total_losses"`
	LastResult     string `json:"last_result,omitempty"`
}
type BetHistoryItem struct {
	ID         string    `json:"id"`
	Coin       string    `json:"coin"`
	Amount     string    `json:"amount"`
	UserProfit string    `json:"user_profit"`
	Result     string    `json:"result"`
	Status     string    `json:"status"`
	PreparedAt time.Time `json:"prepared_at"`
}
type ReferralUser struct {
	ID, Username         string
	Level, DownlineCount int
	CreatedAt            time.Time
}
type BonusEvent struct {
	ID, Amount, EventType string
	Level                 int
	OccurredAt            time.Time
}
type WalletOperation struct {
	Status           string
	ProviderResponse []byte
}
type WalletHistoryItem struct {
	RequestID   string     `json:"request_id"`
	Operation   string     `json:"operation"`
	Coin        string     `json:"coin"`
	Amount      string     `json:"amount"`
	Destination string     `json:"destination"`
	Status      string     `json:"status"`
	Reason      string     `json:"reason,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`
}

func DefaultTradingSettings() TradingSettings {
	return TradingSettings{Coin: "TRX", BaseBet: "0.00000100", ChanceMin: "45", ChanceMax: "45", DelayMS: 500,
		MartingaleOnWin: "0", MartingaleOnLoss: "100", ResetAfterWins: 1, BoomWinAmount: "0", BoomLossAmount: "0",
		TakeProfit: "0", StopLoss: "0", ProfitSession: "0", BalanceBelow: "0", MaximumBet: "0"}
}

func Open(ctx context.Context, url string) (*Store, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, err
	}
	check, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err = pool.Ping(check); err != nil {
		pool.Close()
		return nil, err
	}
	return &Store{pool: pool}, nil
}
func (s *Store) Close() { s.pool.Close() }

func (s *Store) CleanupTransientHistory(ctx context.Context) error {
	var events, bets, commands, sessions, bonus int64
	return s.pool.QueryRow(ctx, `SELECT * FROM cleanup_ryubot_transient_history()`).Scan(&events, &bets, &commands, &sessions, &bonus)
}

func (s *Store) Login(ctx context.Context, username, password string) (string, Account, error) {
	var account Account
	var hash string
	err := s.pool.QueryRow(ctx, `SELECT id,username,email,password_hash,subscription_expires_at FROM users
		WHERE lower(username)=lower($1) AND status='ACTIVE' LIMIT 1`, username).Scan(&account.ID, &account.Username, &account.Email, &hash, &account.SubscriptionExpiresAt)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return "", Account{}, errors.New("username atau password tidak valid")
	}
	token, err := newToken(32)
	if err != nil {
		return "", Account{}, err
	}
	csrf, err := newToken(24)
	if err != nil {
		return "", Account{}, err
	}
	digest := sha256.Sum256([]byte(token))
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", Account{}, err
	}
	defer tx.Rollback(ctx)
	// The Node application permits only one active user session. Keep that rule
	// while avoiding a separate active_session column.
	if _, err = tx.Exec(ctx, `DELETE FROM user_sessions WHERE user_id=$1`, account.ID); err != nil {
		return "", Account{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO user_sessions(token_hash,user_id,csrf_token,expires_at) VALUES($1,$2,$3,now()+interval '30 days')`, digest[:], account.ID, csrf); err != nil {
		return "", Account{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return "", Account{}, err
	}
	account.CSRF = csrf
	return token, account, nil
}

func (s *Store) MarkLogin(ctx context.Context, userID int64) error {
	_, err := s.pool.Exec(ctx, `UPDATE users SET last_login_at=now(),last_active_at=now(),updated_at=now() WHERE id=$1`, userID)
	return err
}

func (s *Store) RegistrationAvailable(ctx context.Context, username, email string) (bool, error) {
	var exists bool
	err := s.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE lower(username)=lower($1) OR lower(email)=lower($2))`, username, email).Scan(&exists)
	return !exists, err
}

// Register persists the local half of the already-verified Pasino
// registration. Both the local referral and default trial follow Node's
// existing behaviour; only the configurable trial length comes from admin
// settings instead of a compiled constant.
func (s *Store) Register(ctx context.Context, input Registration) (string, Account, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		return "", Account{}, err
	}
	token, err := newToken(32)
	if err != nil {
		return "", Account{}, err
	}
	csrf, err := newToken(24)
	if err != nil {
		return "", Account{}, err
	}
	digest := sha256.Sum256([]byte(token))
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", Account{}, err
	}
	defer tx.Rollback(ctx)
	var duplicate bool
	if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE lower(username)=lower($1) OR lower(email)=lower($2))`, input.Username, input.Email).Scan(&duplicate); err != nil {
		return "", Account{}, err
	}
	if duplicate {
		return "", Account{}, errors.New("username atau email sudah digunakan")
	}
	referrerName := input.Referrer
	if referrerName == "" {
		referrerName = "kangden69"
	}
	var referrerID int64
	err = tx.QueryRow(ctx, `SELECT id FROM users WHERE lower(username)=lower($1) AND status='ACTIVE' LIMIT 1`, referrerName).Scan(&referrerID)
	if errors.Is(err, pgx.ErrNoRows) && !strings.EqualFold(referrerName, "kangden69") {
		err = tx.QueryRow(ctx, `SELECT id FROM users WHERE lower(username)=lower('kangden69') AND status='ACTIVE' LIMIT 1`).Scan(&referrerID)
	}
	if err != nil {
		return "", Account{}, errors.New("upline default belum tersedia")
	}
	var trialDays int
	if err = tx.QueryRow(ctx, `SELECT value::integer FROM app_settings WHERE key='subscription.trial_days'`).Scan(&trialDays); err != nil {
		return "", Account{}, err
	}
	var account Account
	err = tx.QueryRow(ctx, `INSERT INTO users(username,email,password_hash,status,subscription_expires_at,subscription_trial_ends_at)
		VALUES($1,$2,$3,'ACTIVE',now()+($4::int*interval '1 day'),now()+($4::int*interval '1 day')) RETURNING id,username,email,subscription_expires_at`, input.Username, strings.ToLower(input.Email), string(hash), trialDays).Scan(&account.ID, &account.Username, &account.Email, &account.SubscriptionExpiresAt)
	if err != nil {
		return "", Account{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO user_referrals(user_id,referrer_user_id,provider_referrer) VALUES($1,$2,'277064')`, account.ID, referrerID); err != nil {
		return "", Account{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO user_trading_settings(user_id) VALUES($1)`, account.ID); err != nil {
		return "", Account{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO user_pasino_accounts(user_id,provider_username,provider_email,password_ciphertext,access_token_ciphertext,encryption_version,last_authenticated_at) VALUES($1,$2,$3,$4,$5,1,now())`, account.ID, account.Username, account.Email, input.PasswordCiphertext, input.AccessTokenCiphertext); err != nil {
		return "", Account{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO user_sessions(token_hash,user_id,csrf_token,expires_at) VALUES($1,$2,$3,now()+interval '30 days')`, digest[:], account.ID, csrf); err != nil {
		return "", Account{}, err
	}
	if _, err = tx.Exec(ctx, `UPDATE users SET last_login_at=now(),last_active_at=now(),updated_at=now() WHERE id=$1`, account.ID); err != nil {
		return "", Account{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return "", Account{}, err
	}
	account.CSRF = csrf
	return token, account, nil
}

func (s *Store) Authenticate(ctx context.Context, token string) (Account, error) {
	if token == "" {
		return Account{}, errors.New("unauthenticated")
	}
	digest := sha256.Sum256([]byte(token))
	var account Account
	err := s.pool.QueryRow(ctx, `SELECT u.id,u.username,u.email,s.csrf_token,u.subscription_expires_at FROM user_sessions s
		JOIN users u ON u.id=s.user_id
		WHERE s.token_hash=$1 AND s.expires_at>now() AND u.status='ACTIVE'`, digest[:]).Scan(&account.ID, &account.Username, &account.Email, &account.CSRF, &account.SubscriptionExpiresAt)
	if err == nil {
		// A five-minute write throttle records real application use without
		// turning every authenticated API call into a database write.
		_, _ = s.pool.Exec(ctx, `UPDATE users SET last_active_at=now() WHERE id=$1 AND (last_active_at IS NULL OR last_active_at < now()-interval '5 minutes')`, account.ID)
	}
	return account, err
}

func (s *Store) Logout(ctx context.Context, token string) {
	if token == "" {
		return
	}
	digest := sha256.Sum256([]byte(token))
	_, _ = s.pool.Exec(ctx, `DELETE FROM user_sessions WHERE token_hash=$1`, digest[:])
}
func (s *Store) ChangePassword(ctx context.Context, userID int64, currentPassword, newPassword string) error {
	var hash string
	if err := s.pool.QueryRow(ctx, `SELECT password_hash FROM users WHERE id=$1 AND status='ACTIVE'`, userID).Scan(&hash); err != nil {
		return err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(currentPassword)) != nil {
		return errors.New("password saat ini tidak valid")
	}
	replacement, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `UPDATE users SET password_hash=$2,updated_at=now() WHERE id=$1`, userID, string(replacement))
	return err
}

func (s *Store) MinimumWithdrawal(ctx context.Context, coin string) (string, error) {
	var value string
	err := s.pool.QueryRow(ctx, `SELECT value FROM app_settings WHERE key=$1`, `coin.`+strings.ToUpper(coin)+`.minimum_withdrawal`).Scan(&value)
	return value, err
}
func (s *Store) ReferralNetwork(ctx context.Context, userID int64) ([]ReferralUser, error) {
	rows, err := s.pool.Query(ctx, `WITH RECURSIVE network AS (SELECT u.id,u.username,u.created_at,1 level FROM user_referrals r JOIN users u ON u.id=r.user_id WHERE r.referrer_user_id=$1 UNION ALL SELECT u.id,u.username,u.created_at,n.level+1 FROM network n JOIN user_referrals r ON r.referrer_user_id=n.id JOIN users u ON u.id=r.user_id WHERE n.level<3) SELECT id::text,username,level,created_at,(SELECT count(*)::int FROM user_referrals c WHERE c.referrer_user_id=network.id) FROM network ORDER BY level,created_at`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []ReferralUser{}
	for rows.Next() {
		var item ReferralUser
		if err = rows.Scan(&item.ID, &item.Username, &item.Level, &item.CreatedAt, &item.DownlineCount); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}
func (s *Store) ReferralBonus(ctx context.Context, userID int64, coin string) (available, claimed, minimum string, events []BonusEvent, err error) {
	err = s.pool.QueryRow(ctx, `SELECT coalesce(available_amount,0)::text,coalesce(claimed_amount,0)::text FROM referral_bonus_balances WHERE user_id=$1 AND coin=$2`, userID, coin).Scan(&available, &claimed)
	if errors.Is(err, pgx.ErrNoRows) {
		available, claimed, err = "0.00000000", "0.00000000", nil
	}
	if err != nil {
		return
	}
	err = s.pool.QueryRow(ctx, `SELECT value FROM app_settings WHERE key=$1`, `coin.`+coin+`.minimum_claim`).Scan(&minimum)
	if err != nil {
		return
	}
	rows, rowErr := s.pool.Query(ctx, `SELECT id::text,amount::text,event_type,CASE WHEN source_external_id~'referral:[123]$' THEN right(source_external_id,1)::int ELSE 0 END,occurred_at FROM referral_bonus_events WHERE user_id=$1 AND coin=$2 ORDER BY occurred_at DESC LIMIT 100`, userID, coin)
	if rowErr != nil {
		err = rowErr
		return
	}
	defer rows.Close()
	events = []BonusEvent{}
	for rows.Next() {
		var item BonusEvent
		if scanErr := rows.Scan(&item.ID, &item.Amount, &item.EventType, &item.Level, &item.OccurredAt); scanErr != nil {
			err = scanErr
			return
		}
		events = append(events, item)
	}
	err = rows.Err()
	return
}

func (s *Store) ClaimBonus(ctx context.Context, userID int64, coin string) (claimed string, err error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)
	var available, currentClaimed string
	err = tx.QueryRow(ctx, `SELECT coalesce(available_amount,0)::text,coalesce(claimed_amount,0)::text FROM referral_bonus_balances WHERE user_id=$1 AND coin=$2 FOR UPDATE`, userID, coin).Scan(&available, &currentClaimed)
	if err != nil {
		return "", err
	}
	if available == "0" || available == "0.00000000" {
		return currentClaimed, nil
	}
	_, err = tx.Exec(ctx, `UPDATE referral_bonus_balances SET claimed_amount=coalesce(claimed_amount,0)::numeric+$1::numeric,available_amount=0 WHERE user_id=$2 AND coin=$3`, available, userID, coin)
	if err != nil {
		return "", err
	}
	_, err = tx.Exec(ctx, `INSERT INTO referral_bonus_events(user_id,amount,event_type,coin,source_external_id,occurred_at) VALUES($1,$2,'CLAIM_COMPLETED',$3,'wallet:claim',now())`, userID, available, coin)
	if err != nil {
		return "", err
	}
	err = tx.Commit(ctx)
	if err != nil {
		return "", err
	}
	return available, nil
}

func (s *Store) GetCollectorUsername(ctx context.Context) (string, error) {
	var username string
	err := s.pool.QueryRow(ctx, `SELECT value FROM app_settings WHERE key='account.fee_collector_username'`).Scan(&username)
	return username, err
}

func (s *Store) GetUserID(ctx context.Context, username string) (int64, error) {
	var id int64
	err := s.pool.QueryRow(ctx, `SELECT id FROM users WHERE lower(username)=lower($1) AND status='ACTIVE'`, username).Scan(&id)
	return id, err
}

func (s *Store) TradingSettings(ctx context.Context, userID int64) (TradingSettings, error) {
	settings := DefaultTradingSettings()
	err := s.pool.QueryRow(ctx, `SELECT coin,base_bet::text,chance_min::integer::text,chance_max::integer::text,delay_ms,
		martingale_on_win::integer::text,martingale_on_loss::integer::text,reset_after_wins,reset_after_losses,
		boom_after_wins,boom_win_amount::text,boom_after_losses,boom_loss_amount::text,
		take_profit::text,stop_loss::text,profit_session::text,balance_below::text,stop_on_win,maximum_bet::text
		FROM user_trading_settings WHERE user_id=$1`, userID).Scan(&settings.Coin, &settings.BaseBet, &settings.ChanceMin, &settings.ChanceMax, &settings.DelayMS,
		&settings.MartingaleOnWin, &settings.MartingaleOnLoss, &settings.ResetAfterWins, &settings.ResetAfterLosses,
		&settings.BoomAfterWins, &settings.BoomWinAmount, &settings.BoomAfterLosses, &settings.BoomLossAmount,
		&settings.TakeProfit, &settings.StopLoss, &settings.ProfitSession, &settings.BalanceBelow, &settings.StopOnWin, &settings.MaximumBet)
	if errors.Is(err, pgx.ErrNoRows) {
		return settings, nil
	}
	if err == nil {
		// Stop Win belongs to the active session, exactly as in the base app.
		// The persistent setting remains false so a new session starts OFF.
		settings.StopOnWin = false
		_ = s.pool.QueryRow(ctx, `SELECT coalesce((settings_snapshot->>'StopOnWin')::boolean,false)
			FROM trading_sessions WHERE user_id=$1 AND status IN ('RUNNING','STOP_REQUESTED')
			ORDER BY started_at DESC LIMIT 1`, userID).Scan(&settings.StopOnWin)
	}
	return settings, err
}

func (s *Store) SaveTradingSettings(ctx context.Context, userID int64, v TradingSettings) error {
	_, err := s.pool.Exec(ctx, `INSERT INTO user_trading_settings(
		user_id,coin,base_bet,chance_min,chance_max,delay_ms,martingale_on_win,martingale_on_loss,
		reset_after_wins,reset_after_losses,boom_after_wins,boom_win_amount,boom_after_losses,boom_loss_amount,
		take_profit,stop_loss,profit_session,balance_below,stop_on_win,maximum_bet,updated_at)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,now())
		ON CONFLICT(user_id) DO UPDATE SET
		coin=excluded.coin,base_bet=excluded.base_bet,chance_min=excluded.chance_min,chance_max=excluded.chance_max,delay_ms=excluded.delay_ms,
		martingale_on_win=excluded.martingale_on_win,martingale_on_loss=excluded.martingale_on_loss,
		reset_after_wins=excluded.reset_after_wins,reset_after_losses=excluded.reset_after_losses,
		boom_after_wins=excluded.boom_after_wins,boom_win_amount=excluded.boom_win_amount,
		boom_after_losses=excluded.boom_after_losses,boom_loss_amount=excluded.boom_loss_amount,
		take_profit=excluded.take_profit,stop_loss=excluded.stop_loss,profit_session=excluded.profit_session,
		balance_below=excluded.balance_below,stop_on_win=excluded.stop_on_win,maximum_bet=excluded.maximum_bet,updated_at=now()`,
		userID, v.Coin, v.BaseBet, v.ChanceMin, v.ChanceMax, v.DelayMS, v.MartingaleOnWin, v.MartingaleOnLoss,
		v.ResetAfterWins, v.ResetAfterLosses, v.BoomAfterWins, v.BoomWinAmount, v.BoomAfterLosses, v.BoomLossAmount,
		v.TakeProfit, v.StopLoss, v.ProfitSession, v.BalanceBelow, v.StopOnWin, v.MaximumBet)
	return err
}

// ActiveTradingBalance is the user-facing balance ledger during an unresolved
// trading session. It is net of fees once settlement has been committed.
func (s *Store) ActiveTradingBalance(ctx context.Context, userID int64, coin string) (string, string, bool, error) {
	var balance, status string
	err := s.pool.QueryRow(ctx, `SELECT visible_user_balance::text,status FROM trading_sessions
		WHERE user_id=$1 AND coin=$2 AND status IN ('RUNNING','STOP_REQUESTED','RECONCILIATION_REQUIRED')
		ORDER BY started_at DESC LIMIT 1`, userID, coin).Scan(&balance, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", false, nil
	}
	return balance, status, err == nil, err
}

func (s *Store) OutstandingTradingFees(ctx context.Context, userID int64, coin string) (string, error) {
	var amount string
	err := s.pool.QueryRow(ctx, `SELECT coalesce((SELECT holding_pending+kangden_pending FROM trading_fee_balances WHERE user_id=$1 AND coin=$2),0)::text`, userID, coin).Scan(&amount)
	return amount, err
}

func (s *Store) TradingStatus(ctx context.Context, userID int64) (TradingStatus, error) {
	var status TradingStatus
	err := s.pool.QueryRow(ctx, `SELECT id::text,status,coin,current_bet::text,profit::text,visible_user_balance::text,coalesce(stop_reason,''),max_win_streak,max_loss_streak,streak,wins,losses,coalesce(last_result,'')
		FROM trading_sessions WHERE user_id=$1 AND status IN ('RUNNING','STOP_REQUESTED','RECONCILIATION_REQUIRED')
		ORDER BY started_at DESC LIMIT 1`, userID).Scan(&status.SessionID, &status.Status, &status.Coin, &status.CurrentBet, &status.Profit, &status.VisibleBalance, &status.StopReason, &status.Wins, &status.Losses, &status.Rolls, &status.TotalWins, &status.TotalLosses, &status.LastResult)
	if errors.Is(err, pgx.ErrNoRows) {
		err = s.pool.QueryRow(ctx, `SELECT id::text,'STOPPED',coin,current_bet::text,profit::text,visible_user_balance::text,coalesce(stop_reason,''),max_win_streak,max_loss_streak,streak,wins,losses,coalesce(last_result,'')
			FROM trading_sessions WHERE user_id=$1 AND status='COMPLETED'
			ORDER BY completed_at DESC NULLS LAST,started_at DESC LIMIT 1`, userID).Scan(&status.SessionID, &status.Status, &status.Coin, &status.CurrentBet, &status.Profit, &status.VisibleBalance, &status.StopReason, &status.Wins, &status.Losses, &status.Rolls, &status.TotalWins, &status.TotalLosses, &status.LastResult)
		if errors.Is(err, pgx.ErrNoRows) {
			return TradingStatus{Status: "STOPPED", Profit: "0.00000000"}, nil
		}
	}
	return status, err
}

func (s *Store) RequestTradingStop(ctx context.Context, userID int64) (bool, error) {
	tag, err := s.pool.Exec(ctx, `UPDATE trading_sessions SET status='STOP_REQUESTED',updated_at=now()
		WHERE user_id=$1 AND status='RUNNING'`, userID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

func (s *Store) BetHistory(ctx context.Context, userID int64, limit int) ([]BetHistoryItem, error) {
	rows, err := s.pool.Query(ctx, `SELECT b.id::text,b.coin,b.amount::text,coalesce(b.user_profit,0)::text,coalesce(b.result,''),b.status,b.prepared_at
		FROM provider_bets b WHERE b.session_id=(SELECT id FROM trading_sessions WHERE user_id=$1
		ORDER BY started_at DESC LIMIT 1)
		AND b.status='COMPLETED' ORDER BY b.prepared_at DESC LIMIT $2`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []BetHistoryItem{}
	for rows.Next() {
		var item BetHistoryItem
		if err = rows.Scan(&item.ID, &item.Coin, &item.Amount, &item.UserProfit, &item.Result, &item.Status, &item.PreparedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) HasActiveTrading(ctx context.Context, userID int64) (bool, error) {
	var active bool
	err := s.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM trading_sessions WHERE user_id=$1 AND status IN ('RUNNING','STOP_REQUESTED','RECONCILIATION_REQUIRED'))`, userID).Scan(&active)
	return active, err
}

func (s *Store) WalletHistory(ctx context.Context, userID int64, operation string, limit int) ([]WalletHistoryItem, error) {
	rows, err := s.pool.Query(ctx, `SELECT request_id::text,operation,coin,amount::text,destination,status,coalesce(failure_reason,''),created_at,completed_at
		FROM wallet_operations WHERE user_id=$1 AND operation=$2 ORDER BY created_at DESC LIMIT $3`, userID, operation, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]WalletHistoryItem, 0)
	for rows.Next() {
		var item WalletHistoryItem
		if err = rows.Scan(&item.RequestID, &item.Operation, &item.Coin, &item.Amount, &item.Destination, &item.Status, &item.Reason, &item.CreatedAt, &item.CompletedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}
func (s *Store) BeginWalletOperation(ctx context.Context, requestID string, userID int64, operation, coin, amount, destination string) (WalletOperation, bool, error) {
	var existing WalletOperation
	var owner int64
	var response string
	err := s.pool.QueryRow(ctx, `SELECT user_id,status,coalesce(provider_response,'{}'::jsonb)::text FROM wallet_operations WHERE request_id=$1`, requestID).Scan(&owner, &existing.Status, &response)
	if err == nil {
		if owner != userID {
			return WalletOperation{}, false, errors.New("request_id sudah digunakan")
		}
		existing.ProviderResponse = []byte(response)
		return existing, true, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return WalletOperation{}, false, err
	}
	_, err = s.pool.Exec(ctx, `INSERT INTO wallet_operations(request_id,user_id,operation,coin,amount,destination,status) VALUES($1,$2,$3,$4,$5,$6,'PROCESSING')`, requestID, userID, operation, coin, amount, destination)
	if err != nil {
		return WalletOperation{}, false, fmt.Errorf("mencatat transaksi wallet: %w", err)
	}
	return WalletOperation{Status: "PROCESSING"}, false, nil
}
func (s *Store) FinishWalletOperation(ctx context.Context, requestID, status string, response []byte, reason string) error {
	var responseJSON any
	if len(response) > 0 {
		responseJSON = string(response)
	}
	tag, err := s.pool.Exec(ctx, `UPDATE wallet_operations SET status=$2::varchar(24),provider_response=coalesce($3::jsonb,provider_response),failure_reason=nullif($4::text,''),completed_at=CASE WHEN $2::varchar(24)='COMPLETED' THEN now() ELSE completed_at END,updated_at=now() WHERE request_id=$1::uuid AND status='PROCESSING'`, requestID, status, responseJSON, reason)
	if err != nil {
		return fmt.Errorf("menyelesaikan transaksi wallet: %w", err)
	}
	if tag.RowsAffected() != 1 {
		return errors.New("transaksi wallet tidak lagi berstatus PROCESSING")
	}
	return nil
}

func newToken(size int) (string, error) {
	b := make([]byte, size)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
