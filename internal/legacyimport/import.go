package legacyimport

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Summary struct { Users, Referrals, ProviderAccounts, TradingSettings, BonusRows int }

func Run(ctx context.Context, legacyURL, targetURL string) (Summary, error) {
	legacy, err := pgxpool.New(ctx, legacyURL); if err != nil { return Summary{}, err }; defer legacy.Close()
	target, err := pgxpool.New(ctx, targetURL); if err != nil { return Summary{}, err }; defer target.Close()
	tx, err := target.Begin(ctx); if err != nil { return Summary{}, err }; defer tx.Rollback(ctx)
	if err := ensureImportSchema(ctx, tx); err != nil { return Summary{}, err }
	users, err := importUsers(ctx, legacy, tx); if err != nil { return Summary{}, err }
	referrals, err := importReferrals(ctx, legacy, tx); if err != nil { return Summary{}, err }
	settings, err := importTradingSettings(ctx, legacy, tx); if err != nil { return Summary{}, err }
	accounts, err := importAccounts(ctx, legacy, tx); if err != nil { return Summary{}, err }
	bonuses, err := importBonuses(ctx, legacy, tx); if err != nil { return Summary{}, err }
	if err = tx.Commit(ctx); err != nil { return Summary{}, err }
	return Summary{Users:users, Referrals:referrals, ProviderAccounts:accounts, TradingSettings:settings, BonusRows:bonuses}, nil
}

func ensureImportSchema(ctx context.Context, tx pgx.Tx) error {
	var exists bool
	err := tx.QueryRow(ctx, `SELECT EXISTS(
		SELECT 1 FROM information_schema.columns
		WHERE table_schema='public' AND table_name='user_trading_settings' AND column_name='profit_session'
	)`).Scan(&exists)
	if err != nil { return err }
	if !exists { return fmt.Errorf("database schema belum memakai migration 007_import_legacy_trading_settings.sql; jalankan migrate sebelum import-legacy") }
	err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_referrals')`).Scan(&exists)
	if err != nil { return err }
	if !exists { return fmt.Errorf("database schema belum memakai migration 008_user_referrals_and_trial.sql; jalankan migrate sebelum import-legacy") }
	return nil
}

func importUsers(ctx context.Context, source *pgxpool.Pool, tx pgx.Tx) (int,error) {
	rows,err:=source.Query(ctx,`SELECT id,username,email,password_hash,is_active,subscription_expires_at,subscription_trial_ends_at FROM users WHERE role='user' ORDER BY id`);if err!=nil{return 0,fmt.Errorf("legacy users: %w",err)};defer rows.Close();count:=0
	for rows.Next(){var id int64;var username,email,hash string;var active bool;var subscriptionExpires,trialEnds *time.Time;if err=rows.Scan(&id,&username,&email,&hash,&active,&subscriptionExpires,&trialEnds);err!=nil{return count,err};status:="SUSPENDED";if active{status="ACTIVE"};_,err=tx.Exec(ctx,`INSERT INTO users(legacy_user_id,username,email,password_hash,status,subscription_expires_at,subscription_trial_ends_at) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(legacy_user_id) WHERE legacy_user_id IS NOT NULL DO UPDATE SET username=excluded.username,email=excluded.email,password_hash=excluded.password_hash,status=excluded.status,subscription_expires_at=excluded.subscription_expires_at,subscription_trial_ends_at=excluded.subscription_trial_ends_at,updated_at=now()`,id,username,email,hash,status,subscriptionExpires,trialEnds);if err!=nil{return count,err};count++};return count,rows.Err()
}

func importReferrals(ctx context.Context, source *pgxpool.Pool, tx pgx.Tx) (int,error) {
	rows, err := source.Query(ctx, `SELECT r.user_id,r.referrer_user_id,r.provider_referrer
		FROM user_referrals r JOIN users u ON u.id=r.user_id WHERE u.role='user' ORDER BY r.user_id`)
	if err != nil { return 0, fmt.Errorf("legacy referrals: %w", err) }
	defer rows.Close()
	count := 0
	for rows.Next() {
		var legacyUserID int64; var legacyReferrerID *int64; var providerReferrer string
		if err := rows.Scan(&legacyUserID,&legacyReferrerID,&providerReferrer); err != nil { return count,err }
		var userID int64
		if err := tx.QueryRow(ctx, `SELECT id FROM users WHERE legacy_user_id=$1`,legacyUserID).Scan(&userID);err!=nil{return count,err}
		var referrerID *int64
		if legacyReferrerID != nil {
			var found int64
			if err:=tx.QueryRow(ctx,`SELECT id FROM users WHERE legacy_user_id=$1`,*legacyReferrerID).Scan(&found);err==nil { referrerID=&found } else if !errors.Is(err,pgx.ErrNoRows) { return count,err }
		}
		_,err:=tx.Exec(ctx,`INSERT INTO user_referrals(user_id,referrer_user_id,provider_referrer) VALUES($1,$2,$3)
			ON CONFLICT(user_id) DO UPDATE SET referrer_user_id=excluded.referrer_user_id,provider_referrer=excluded.provider_referrer,updated_at=now()`,userID,referrerID,providerReferrer)
		if err!=nil{return count,err};count++
	}
	return count,rows.Err()
}

// importTradingSettings maps the actual legacy trading_settings contract into
// the new per-user settings table. Provider balance is intentionally absent:
// it is always obtained live from Pasino.
func importTradingSettings(ctx context.Context, source *pgxpool.Pool, tx pgx.Tx) (int,error) {
	rows, err := source.Query(ctx, `SELECT s.user_id,u.selected_coin,
		s.martingale_on_win,s.martingale_on_loss,s.reset_win_streak,s.reset_loss_streak,
		s.win_streak_roll,s.win_next_bet::text,s.loss_streak_roll,s.loss_next_bet::text,
		s.take_profit::text,s.stop_loss::text,s.profit_session::text,s.balance_below::text
		FROM trading_settings s JOIN users u ON u.id=s.user_id
		WHERE u.role='user' ORDER BY s.user_id`)
	if err != nil { return 0, fmt.Errorf("legacy trading settings: %w", err) }
	defer rows.Close()
	count := 0
	for rows.Next() {
		var legacyID int64
		var coin string
		var martingaleWin, martingaleLoss, resetWins, resetLosses, boomWins, boomLosses int
		var boomWinAmount, boomLossAmount, takeProfit, stopLoss, profitSession, balanceBelow string
		if err := rows.Scan(&legacyID, &coin, &martingaleWin, &martingaleLoss, &resetWins, &resetLosses,
			&boomWins, &boomWinAmount, &boomLosses, &boomLossAmount, &takeProfit, &stopLoss, &profitSession, &balanceBelow); err != nil {
			return count, err
		}
		var userID int64
		if err := tx.QueryRow(ctx, `SELECT id FROM users WHERE legacy_user_id=$1`, legacyID).Scan(&userID); err != nil { return count, err }
		_, err := tx.Exec(ctx, `INSERT INTO user_trading_settings(
			user_id,coin,martingale_on_win,martingale_on_loss,reset_after_wins,reset_after_losses,
			boom_after_wins,boom_win_amount,boom_after_losses,boom_loss_amount,
			take_profit,stop_loss,profit_session,balance_below,updated_at)
			VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,now())
			ON CONFLICT(user_id) DO UPDATE SET
			coin=excluded.coin,martingale_on_win=excluded.martingale_on_win,martingale_on_loss=excluded.martingale_on_loss,
			reset_after_wins=excluded.reset_after_wins,reset_after_losses=excluded.reset_after_losses,
			boom_after_wins=excluded.boom_after_wins,boom_win_amount=excluded.boom_win_amount,
			boom_after_losses=excluded.boom_after_losses,boom_loss_amount=excluded.boom_loss_amount,
			take_profit=excluded.take_profit,stop_loss=excluded.stop_loss,profit_session=excluded.profit_session,
			balance_below=excluded.balance_below,updated_at=now()`,
			userID, coin, martingaleWin, martingaleLoss, resetWins, resetLosses, boomWins, boomWinAmount,
			boomLosses, boomLossAmount, takeProfit, stopLoss, profitSession, balanceBelow)
		if err != nil { return count, err }
		count++
	}
	return count, rows.Err()
}

func importAccounts(ctx context.Context, source *pgxpool.Pool, tx pgx.Tx) (int,error) {
	columns, err := tableColumns(ctx, source, "pasino_accounts")
	if err != nil { return 0, err }
	username := requiredColumn(columns, "provider_username", "username")
	if username == "" { return 0, fmt.Errorf("legacy Pasino accounts has no provider username column; available: %s", strings.Join(columnNames(columns), ", ")) }
	query := fmt.Sprintf(`SELECT p.user_id,%s,%s,%s,%s,%s,%s,%s FROM pasino_accounts p JOIN users u ON u.id=p.user_id WHERE u.role='user'`,
		legacyColumnExpression(username, "text"),
		optionalColumnExpression(columns, "text", "provider_email", "email"),
		optionalColumnExpression(columns, "text", "pasino_password_ciphertext", "password_encrypted", "encrypted_password", "provider_password_encrypted"),
		optionalColumnExpression(columns, "text", "access_token_ciphertext", "access_token", "token"),
		optionalColumnExpression(columns, "timestamptz", "access_token_expires_at", "token_expires_at", "access_expires_at"),
		optionalColumnExpression(columns, "text", "socket_token"),
		optionalColumnExpression(columns, "timestamptz", "socket_token_expires_at", "socket_expires_at"),
	)
	rows,err:=source.Query(ctx,query);if err!=nil{return 0,fmt.Errorf("legacy Pasino accounts: %w",err)};defer rows.Close();count:=0
	for rows.Next(){var legacyID int64;var username string;var email,password,access,socket *string;var accessAt,socketAt *time.Time;if err=rows.Scan(&legacyID,&username,&email,&password,&access,&accessAt,&socket,&socketAt);err!=nil{return count,err};var userID int64;if err=tx.QueryRow(ctx,`SELECT id FROM users WHERE legacy_user_id=$1`,legacyID).Scan(&userID);err!=nil{return count,err};_,err=tx.Exec(ctx,`INSERT INTO user_pasino_accounts(user_id,provider_username,provider_email,password_ciphertext,access_token_ciphertext,access_token_expires_at,socket_token_ciphertext,socket_token_expires_at,encryption_version,imported_from_legacy,last_authenticated_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,0,true,now()) ON CONFLICT(user_id) DO UPDATE SET provider_username=excluded.provider_username,provider_email=excluded.provider_email,password_ciphertext=excluded.password_ciphertext,access_token_ciphertext=excluded.access_token_ciphertext,access_token_expires_at=excluded.access_token_expires_at,socket_token_ciphertext=excluded.socket_token_ciphertext,socket_token_expires_at=excluded.socket_token_expires_at,encryption_version=0,imported_from_legacy=true,updated_at=now()`,userID,username,email,password,access,accessAt,socket,socketAt);if err!=nil{return count,err};count++};return count,rows.Err()
}

func tableColumns(ctx context.Context, pool *pgxpool.Pool, table string) (map[string]bool, error) {
	rows, err := pool.Query(ctx, `SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1`, table)
	if err != nil { return nil, err }
	defer rows.Close()
	result := map[string]bool{}
	for rows.Next() { var name string; if err := rows.Scan(&name); err != nil { return nil, err }; result[name] = true }
	if err := rows.Err(); err != nil { return nil, err }
	if len(result) == 0 { return nil, fmt.Errorf("legacy table %q not found", table) }
	return result, nil
}

func requiredColumn(columns map[string]bool, candidates ...string) string {
	for _, name := range candidates { if columns[name] { return name } }
	return ""
}

func optionalColumnExpression(columns map[string]bool, cast string, candidates ...string) string {
	if column := requiredColumn(columns, candidates...); column != "" { return legacyColumnExpression(column, cast) }
	return "NULL::" + cast
}

func columnExpression(column, cast string) string { return `p."` + column + `"::` + cast }

func columnNames(columns map[string]bool) []string {
	result := make([]string, 0, len(columns))
	for name := range columns { result = append(result, name) }
	return result
}

func importBonuses(ctx context.Context, source *pgxpool.Pool, tx pgx.Tx) (int,error) {
	rows,err:=source.Query(ctx,`SELECT b.user_id,b.coin,b.unclaimed_amount::text FROM referral_bonus_balances b JOIN users u ON u.id=b.user_id WHERE u.role='user' AND b.unclaimed_amount>0`);if err!=nil{return 0,fmt.Errorf("legacy bonuses: %w",err)};defer rows.Close();count:=0
	for rows.Next(){var legacyID int64;var coin,amount string;if err=rows.Scan(&legacyID,&coin,&amount);err!=nil{return count,err};var userID int64;if err=tx.QueryRow(ctx,`SELECT id FROM users WHERE legacy_user_id=$1`,legacyID).Scan(&userID);err!=nil{return count,err};external:=fmt.Sprintf("legacy-bonus:%d:%s",legacyID,strings.ToUpper(coin));id,err:=uuid();if err!=nil{return count,err};tag,err:=tx.Exec(ctx,`INSERT INTO referral_bonus_events(id,user_id,coin,amount,event_type,source_external_id) VALUES($1,$2,$3,$4,'IMPORT_OPENING',$5) ON CONFLICT(event_type,source_external_id) DO NOTHING`,id,userID,strings.ToUpper(coin),amount,external);if err!=nil{return count,err};if tag.RowsAffected()==0{continue};_,err=tx.Exec(ctx,`INSERT INTO referral_bonus_balances(user_id,coin,available_amount) VALUES($1,$2,$3) ON CONFLICT(user_id,coin) DO UPDATE SET available_amount=referral_bonus_balances.available_amount+excluded.available_amount,updated_at=now()`,userID,strings.ToUpper(coin),amount);if err!=nil{return count,err};count++};return count,rows.Err()
}

func uuid()(string,error){b:=make([]byte,16);if _,err:=rand.Read(b);err!=nil{return "",err};b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",b[0:4],b[4:6],b[6:8],b[8:10],b[10:16]),nil}
