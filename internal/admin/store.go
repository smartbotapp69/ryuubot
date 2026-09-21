package admin

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

type Store struct{ pool *pgxpool.Pool }
type Admin struct {
	ID             int64
	Username, CSRF string
}
type Rules struct {
	Version                                                        int
	Status                                                         string
	UserPercent, HoldingPercent, KangdenPercent, FeeExemptUsername string
	Referral1, Referral2, Referral3                                string
	SubscriptionPrice, UplineReward, ManagementAmount              string
	TrialDays                                                      int
	OwnerNana, OwnerDeni, OwnerArya, Operational                   string
	Timezone, Cutoff1, Cutoff2                                     string
}

func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }
func DefaultRules() Rules {
	return Rules{Status: "NEW", UserPercent: "86", HoldingPercent: "12", KangdenPercent: "2", FeeExemptUsername: "kangden69", Referral1: "1.5", Referral2: "0.9", Referral3: "0.6", SubscriptionPrice: "22", UplineReward: "3", ManagementAmount: "19", TrialDays: 2, OwnerNana: "30", OwnerDeni: "30", OwnerArya: "30", Operational: "10", Timezone: "Asia/Jakarta", Cutoff1: "13:00", Cutoff2: "18:00"}
}

func Open(ctx context.Context, url string) (*Store, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, err
	}
	ping, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err = pool.Ping(ping); err != nil {
		pool.Close()
		return nil, err
	}
	return NewStore(pool), nil
}
func (s *Store) Close() { s.pool.Close() }

func (s *Store) DashboardStats(ctx context.Context) (DashboardStats, error) {
	var result DashboardStats
	err := s.pool.QueryRow(ctx, `SELECT
		count(*),
		count(*) FILTER (WHERE (created_at AT TIME ZONE 'Asia/Jakarta')::date=(now() AT TIME ZONE 'Asia/Jakarta')::date),
		count(*) FILTER (WHERE (last_login_at AT TIME ZONE 'Asia/Jakarta')::date=(now() AT TIME ZONE 'Asia/Jakarta')::date),
		(SELECT count(DISTINCT user_id) FROM trading_sessions WHERE status IN ('RUNNING','STOP_REQUESTED'))
		FROM users`).Scan(&result.TotalMembers, &result.MembersToday, &result.LoginsToday, &result.TradingMembers)
	if err != nil {
		return result, err
	}
	rows, err := s.pool.Query(ctx, `WITH coins(coin) AS (VALUES ('TRX'),('DOGE'),('FLOKI'),('BTT'))
		SELECT c.coin,coalesce(sum(p.holding_amount),0)::text
		FROM coins c LEFT JOIN provider_bets p ON p.coin=c.coin AND p.status='COMPLETED'
		AND (p.completed_at AT TIME ZONE 'Asia/Jakarta')::date=(now() AT TIME ZONE 'Asia/Jakarta')::date
		GROUP BY c.coin ORDER BY CASE c.coin WHEN 'TRX' THEN 1 WHEN 'DOGE' THEN 2 WHEN 'FLOKI' THEN 3 ELSE 4 END`)
	if err != nil {
		return result, err
	}
	defer rows.Close()
	for rows.Next() {
		var item DashboardRevenue
		if err = rows.Scan(&item.Coin, &item.Amount); err != nil {
			return result, err
		}
		result.Revenue = append(result.Revenue, item)
	}
	return result, rows.Err()
}

func (s *Store) Login(ctx context.Context, username, password string) (string, Admin, error) {
	var a Admin
	var hash string
	err := s.pool.QueryRow(ctx, `SELECT id,username,password_hash FROM admin_users WHERE lower(username)=lower($1) AND is_active=true AND (locked_until IS NULL OR locked_until<now())`, username).Scan(&a.ID, &a.Username, &hash)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return "", Admin{}, errors.New("username atau password salah")
	}
	token, err := randomToken(32)
	if err != nil {
		return "", Admin{}, err
	}
	csrf, err := randomToken(24)
	if err != nil {
		return "", Admin{}, err
	}
	digest := sha256.Sum256([]byte(token))
	_, err = s.pool.Exec(ctx, `INSERT INTO admin_sessions(token_hash,admin_user_id,csrf_token,expires_at) VALUES($1,$2,$3,now()+interval '8 hours')`, digest[:], a.ID, csrf)
	if err != nil {
		return "", Admin{}, err
	}
	a.CSRF = csrf
	return token, a, nil
}
func (s *Store) Authenticate(ctx context.Context, token string) (Admin, error) {
	if token == "" {
		return Admin{}, errors.New("unauthenticated")
	}
	digest := sha256.Sum256([]byte(token))
	var a Admin
	err := s.pool.QueryRow(ctx, `SELECT u.id,u.username,s.csrf_token FROM admin_sessions s JOIN admin_users u ON u.id=s.admin_user_id WHERE s.token_hash=$1 AND s.expires_at>now() AND u.is_active=true`, digest[:]).Scan(&a.ID, &a.Username, &a.CSRF)
	return a, err
}
func (s *Store) Logout(ctx context.Context, token string) {
	digest := sha256.Sum256([]byte(token))
	_, _ = s.pool.Exec(ctx, `DELETE FROM admin_sessions WHERE token_hash=$1`, digest[:])
}

func (s *Store) Rules(ctx context.Context) (Rules, error) {
	var r Rules
	err := s.pool.QueryRow(ctx, `SELECT version,status,user_win_percent::text,holding_win_percent::text,kangden_win_percent::text,fee_exempt_username,referral_level_1_percent::text,referral_level_2_percent::text,referral_level_3_percent::text,subscription_price::text,subscription_upline_reward::text,subscription_management_amount::text,subscription_trial_days,owner_nana_percent::text,owner_deni_percent::text,owner_arya_percent::text,operational_percent::text,owner_cutoff_timezone,to_char(owner_cutoff_times[1],'HH24:MI'),to_char(owner_cutoff_times[2],'HH24:MI') FROM business_rule_versions ORDER BY version DESC LIMIT 1`).Scan(&r.Version, &r.Status, &r.UserPercent, &r.HoldingPercent, &r.KangdenPercent, &r.FeeExemptUsername, &r.Referral1, &r.Referral2, &r.Referral3, &r.SubscriptionPrice, &r.UplineReward, &r.ManagementAmount, &r.TrialDays, &r.OwnerNana, &r.OwnerDeni, &r.OwnerArya, &r.Operational, &r.Timezone, &r.Cutoff1, &r.Cutoff2)
	if errors.Is(err, pgx.ErrNoRows) {
		return DefaultRules(), nil
	}
	return r, err
}

func (s *Store) SaveRules(ctx context.Context, adminID int64, r Rules) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `UPDATE business_rule_versions SET status='ARCHIVED' WHERE status='ACTIVE'`); err != nil {
		return err
	}
	args := []any{r.UserPercent, r.HoldingPercent, r.KangdenPercent, r.FeeExemptUsername, r.Referral1, r.Referral2, r.Referral3, r.SubscriptionPrice, r.UplineReward, r.ManagementAmount, r.TrialDays, r.OwnerNana, r.OwnerDeni, r.OwnerArya, r.Operational, r.Timezone, r.Cutoff1, r.Cutoff2, adminID}
	var id int64
	err = tx.QueryRow(ctx, `INSERT INTO business_rule_versions(version,status,user_win_percent,holding_win_percent,kangden_win_percent,fee_exempt_username,referral_level_1_percent,referral_level_2_percent,referral_level_3_percent,subscription_coin,subscription_price,subscription_upline_reward,subscription_management_amount,subscription_trial_days,owner_nana_percent,owner_deni_percent,owner_arya_percent,operational_percent,owner_cutoff_timezone,owner_cutoff_times,created_by,activated_by,activated_at) VALUES((SELECT coalesce(max(version),0)+1 FROM business_rule_versions),'ACTIVE',$1,$2,$3,$4,$5,$6,$7,'TRX',$8,$9,$10,$11,$12,$13,$14,$15,$16,ARRAY[$17::time,$18::time],$19,$19,now()) RETURNING id`, args...).Scan(&id)
	if err != nil {
		return fmt.Errorf("save rules: %w", err)
	}
	if _, err = tx.Exec(ctx, `INSERT INTO admin_business_rule_audit(admin_user_id,business_rule_version_id,action) VALUES($1,$2,'SAVE')`, adminID, id); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func HashPassword(password string) (string, error) {
	if len(password) < 12 {
		return "", errors.New("password minimal 12 karakter")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(hash), err
}
func (s *Store) BootstrapAdmin(ctx context.Context, username, password string) error {
	hash, err := HashPassword(password)
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `INSERT INTO admin_users(username,password_hash) VALUES($1,$2) ON CONFLICT ((lower(username))) DO NOTHING`, username, hash)
	return err
}
func randomToken(size int) (string, error) {
	b := make([]byte, size)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
