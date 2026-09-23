package management

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"ryubot/internal/pasino"
	"ryubot/internal/trading"
)

var coins = []string{"TRX", "DOGE", "FLOKI", "BTT"}

type Service struct {
	pool          *pgxpool.Pool
	provider      *pasino.Client
	logger        *slog.Logger
	lastCutoffCheck string
	lastCutoffError time.Time
}

func New(pool *pgxpool.Pool, provider *pasino.Client, logger *slog.Logger) *Service {
	return &Service{pool: pool, provider: provider, logger: logger}
}

func (s *Service) Run(ctx context.Context) {
	_, _ = s.pool.Exec(ctx, `UPDATE management_fee_payouts SET status='REVIEW_REQUIRED',failure_reason='Proses berhenti setelah transfer dikirim; verifikasi sebelum retry',updated_at=now() WHERE status='SENT'`)
	_, _ = s.pool.Exec(ctx, `UPDATE owner_cutoff_payouts SET status='REVIEW_REQUIRED',failure_reason='Proses berhenti setelah transfer dikirim; verifikasi sebelum retry',updated_at=now() WHERE status='SENT'`)
	s.run(ctx)
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			s.run(ctx)
		case <-ctx.Done():
			return
		}
	}
}

// stopExpiredSubscriptions halts running trading sessions for active users
// whose subscription has run out, so an expired account cannot keep rolling.
func (s *Service) stopExpiredSubscriptions(ctx context.Context) error {
	_, err := s.pool.Exec(ctx, `UPDATE trading_sessions SET status='STOP_REQUESTED',stop_reason='Langganan berakhir',updated_at=now()
		WHERE status='RUNNING' AND user_id IN (SELECT id FROM users WHERE status='ACTIVE' AND subscription_expires_at IS NOT NULL AND subscription_expires_at<=now())`)
	return err
}

func (s *Service) run(ctx context.Context) {
	if err := s.stopExpiredSubscriptions(ctx); err != nil {
		s.logger.Error("stop expired subscriptions failed", "error", err)
	}
	feeCtx, cancelFees := context.WithTimeout(ctx, 25*time.Second)
	if err := s.dispatchFees(feeCtx); err != nil && !errors.Is(err, context.Canceled) {
		s.logger.Error("management fee payout failed", "error", err)
	}
	cancelFees()
	location, err := time.LoadLocation("Asia/Jakarta")
	if err != nil {
		location = time.Local
	}
	now := time.Now().In(location)
	currentTime := now.Format("15:04")
	cfg, err := s.settings(ctx, "owner.cutoff_1", "owner.cutoff_2")
	if err != nil {
		return
	}
	for _, slot := range []string{cfg["owner.cutoff_1"], cfg["owner.cutoff_2"]} {
		if currentTime != slot {
			continue
		}
		daySlot := now.Format("2006-01-02") + " " + slot
		if daySlot == s.lastCutoffCheck {
			continue
		}
		s.lastCutoffCheck = daySlot
		if time.Since(s.lastCutoffError) < 5*time.Minute {
			continue
		}
		cutoffCtx, cancelCutoff := context.WithTimeout(ctx, 5*time.Minute)
		if err := s.runCutoffAt(cutoffCtx, slot); err != nil && !errors.Is(err, context.Canceled) {
			s.lastCutoffError = time.Now()
			s.logger.Error("owner cutoff failed", "error", err)
		}
		cancelCutoff()
	}
}

type feeJob struct {
	id                                            string
	userID                                        int64
	username, coin, allocation, recipient, amount string
}

func (s *Service) dispatchFees(ctx context.Context) error {
	settings, err := s.settings(ctx, "account.fee_collector_username", "account.kangden_username")
	if err != nil {
		return err
	}
	rows, err := s.pool.Query(ctx, `SELECT f.user_id,u.username,f.coin,f.holding_pending::text,f.kangden_pending::text
		FROM trading_fee_balances f JOIN users u ON u.id=f.user_id
		WHERE f.holding_pending>0 OR f.kangden_pending>0 ORDER BY f.updated_at LIMIT 50`)
	if err != nil {
		return err
	}
	defer rows.Close()
	var jobs []feeJob
	for rows.Next() {
		var userID int64
		var username, coin, holding, kangden string
		if err = rows.Scan(&userID, &username, &coin, &holding, &kangden); err != nil {
			return err
		}
		for _, line := range []struct{ allocation, recipient, amount string }{{"HOLDING", settings["account.fee_collector_username"], holding}, {"KANGDEN", settings["account.kangden_username"], kangden}} {
			amount, parseErr := trading.ParseMoney(line.amount)
			if parseErr != nil {
				return parseErr
			}
			if amount <= 0 {
				continue
			}
			id, idErr := newID()
			if idErr != nil {
				return idErr
			}
			tag, insertErr := s.pool.Exec(ctx, `INSERT INTO management_fee_payouts(id,source_user_id,coin,allocation,recipient_username,amount,status)
				VALUES($1,$2,$3,$4,$5,$6,'PREPARED') ON CONFLICT DO NOTHING`, id, userID, coin, line.allocation, line.recipient, amount.String())
			if insertErr != nil {
				return insertErr
			}
			if tag.RowsAffected() == 1 {
				jobs = append(jobs, feeJob{id, userID, username, coin, line.allocation, line.recipient, amount.String()})
			}
		}
	}
	if err = rows.Err(); err != nil {
		return err
	}
	pending, err := s.pool.Query(ctx, `SELECT p.id::text,p.source_user_id,u.username,p.coin,p.allocation,p.recipient_username,p.amount::text
		FROM management_fee_payouts p JOIN users u ON u.id=p.source_user_id
		WHERE p.status='PREPARED' ORDER BY p.created_at LIMIT 100`)
	if err != nil {
		return err
	}
	for pending.Next() {
		var job feeJob
		if err = pending.Scan(&job.id, &job.userID, &job.username, &job.coin, &job.allocation, &job.recipient, &job.amount); err != nil {
			pending.Close()
			return err
		}
		jobs = append(jobs, job)
	}
	err = pending.Err()
	pending.Close()
	if err != nil {
		return err
	}
	for _, job := range jobs {
		if err = s.sendFee(ctx, job); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) sendFee(ctx context.Context, job feeJob) error {
	tag, err := s.pool.Exec(ctx, `UPDATE management_fee_payouts SET status='SENT',sent_at=now(),updated_at=now() WHERE id=$1 AND status='PREPARED'`, job.id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return nil
	}
	response := map[string]any{"success": true, "settlement": "SELF_RECIPIENT_NO_TRANSFER"}
	if !strings.EqualFold(job.username, job.recipient) {
		response, err = s.provider.Transfer(ctx, job.userID, job.coin, job.recipient, job.amount)
		if err != nil {
			_, _ = s.pool.Exec(context.Background(), `UPDATE management_fee_payouts SET status='REVIEW_REQUIRED',failure_reason=$2,updated_at=now() WHERE id=$1 AND status='SENT'`, job.id, err.Error())
			return nil
		}
	}
	raw, _ := json.Marshal(response)
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var status string
	if err = tx.QueryRow(ctx, `SELECT status FROM management_fee_payouts WHERE id=$1 FOR UPDATE`, job.id).Scan(&status); err != nil {
		return err
	}
	if status != "SENT" {
		return nil
	}
	column := "holding_pending"
	if job.allocation == "KANGDEN" {
		column = "kangden_pending"
	}
	if _, err = tx.Exec(ctx, fmt.Sprintf(`UPDATE trading_fee_balances SET %s=greatest(%s-$3::numeric,0),updated_at=now() WHERE user_id=$1 AND coin=$2`, column, column), job.userID, job.coin, job.amount); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `UPDATE management_fee_payouts SET status='COMPLETED',provider_response=$2,completed_at=now(),updated_at=now() WHERE id=$1`, job.id, raw); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Service) runCutoffAt(ctx context.Context, slot string) error {
	keys := []string{"owner.cutoff_1", "owner.cutoff_2", "owner.nana_percent", "owner.deni_percent", "owner.arya_percent", "owner.operational_percent", "account.fee_collector_username", "account.owner_nana_username", "account.owner_deni_username", "account.owner_arya_username", "account.operational_username"}
	cfg, err := s.settings(ctx, keys...)
	if err != nil {
		return err
	}
	location, err := time.LoadLocation("Asia/Jakarta")
	if err != nil {
		location = time.Local
	}
	now := time.Now().In(location)
	var collectorID int64
	if err = s.pool.QueryRow(ctx, `SELECT id FROM users WHERE lower(username)=lower($1) AND status='ACTIVE'`, cfg["account.fee_collector_username"]).Scan(&collectorID); err != nil {
		return err
	}
	var failures []error
	for _, coin := range coins {
		coinCtx, cancel := context.WithTimeout(ctx, 90*time.Second)
		err = s.cutoffCoin(coinCtx, collectorID, now.Format("2006-01-02"), slot, coin, cfg)
		cancel()
		if err != nil {
			failures = append(failures, fmt.Errorf("%s %s: %w", slot, coin, err))
		}
	}
	return errors.Join(failures...)
}

func (s *Service) cutoffCoin(ctx context.Context, collectorID int64, date, slot, coin string, cfg map[string]string) error {
	slotTime, err := time.ParseInLocation("15:04", slot, time.Local)
	if err != nil {
		return fmt.Errorf("format slot tidak valid: %w", err)
	}
	// pgx maps time.Time with zero date to PostgreSQL time type.
	// We construct a time.Time with date=0 to force this mapping.
	slotAtTime := time.Date(0, time.January, 1, slotTime.Hour(), slotTime.Minute(), 0, 0, time.Local)
	var batchID, batchStatus string
	err = s.pool.QueryRow(ctx, `SELECT id::text,status FROM owner_cutoff_batches WHERE business_date=$1 AND cutoff_slot=$2 AND coin=$3`, date, slotAtTime, coin).Scan(&batchID, &batchStatus)
	if err == nil {
		if batchStatus == "COMPLETED" || batchStatus == "REVIEW_REQUIRED" {
			return nil
		}
		return s.processCutoffPayouts(ctx, batchID, collectorID, coin)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	balanceText, err := s.provider.Balance(ctx, collectorID, coin)
	if err != nil {
		return err
	}
	balance, err := trading.ParseMoney(balanceText)
	if err != nil {
		return err
	}
	var liabilityText string
	err = s.pool.QueryRow(ctx, `SELECT (coalesce((SELECT sum(available_amount) FROM referral_bonus_balances WHERE coin=$1),0)+coalesce((SELECT sum(p.amount) FROM owner_cutoff_payouts p JOIN owner_cutoff_batches b ON b.id=p.batch_id WHERE b.coin=$1 AND p.status IN ('PREPARED','SENT','REVIEW_REQUIRED')),0))::text`, coin).Scan(&liabilityText)
	if err != nil {
		return err
	}
	liability, err := trading.ParseMoney(liabilityText)
	if err != nil {
		return err
	}
	available := balance - liability
	if available < 0 {
		available = 0
	}
	batchID, err = newID()
	if err != nil {
		return err
	}
	labels := []string{"NANA", "DENI", "ARYA", "OPERATIONAL"}
	users := []string{cfg["account.owner_nana_username"], cfg["account.owner_deni_username"], cfg["account.owner_arya_username"], cfg["account.operational_username"]}
	percents := []string{cfg["owner.nana_percent"], cfg["owner.deni_percent"], cfg["owner.arya_percent"], cfg["owner.operational_percent"]}
	amounts := make([]trading.Money, 4)
	allocated := trading.Money(0)
	for i := 0; i < 3; i++ {
		bps, e := trading.ParseBPS(percents[i])
		if e != nil {
			return e
		}
		amounts[i] = trading.Money(int64(available) * bps / 10000)
		allocated += amounts[i]
	}
	amounts[3] = available - allocated
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, `INSERT INTO owner_cutoff_batches(id,business_date,cutoff_slot,coin,collector_balance,reserved_liability,distributable_amount,status) VALUES($1,$2,$3,$4,$5,$6,$7,'PROCESSING') ON CONFLICT DO NOTHING`, batchID, date, slot, coin, balance.String(), liability.String(), available.String())
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return nil
	}
	for i := range labels {
		id, e := newID()
		if e != nil {
			return e
		}
		if _, err = tx.Exec(ctx, `INSERT INTO owner_cutoff_payouts(id,batch_id,allocation,recipient_username,percentage,amount,status) VALUES($1,$2,$3,$4,$5,$6,'PREPARED')`, id, batchID, labels[i], users[i], percents[i], amounts[i].String()); err != nil {
			return err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return err
	}
	return s.processCutoffPayouts(ctx, batchID, collectorID, coin)
}

func (s *Service) processCutoffPayouts(ctx context.Context, batchID string, collectorID int64, coin string) error {
	rows, err := s.pool.Query(ctx, `SELECT id::text,allocation,recipient_username,amount::text FROM owner_cutoff_payouts WHERE batch_id=$1 AND status='PREPARED' ORDER BY CASE allocation WHEN 'NANA' THEN 1 WHEN 'DENI' THEN 2 WHEN 'ARYA' THEN 3 ELSE 4 END`, batchID)
	if err != nil {
		return err
	}
	type payout struct{ id, allocation, username, amount string }
	var jobs []payout
	for rows.Next() {
		var job payout
		if err = rows.Scan(&job.id, &job.allocation, &job.username, &job.amount); err != nil { rows.Close(); return err }
		jobs = append(jobs, job)
	}
	err = rows.Err(); rows.Close(); if err != nil { return err }
	var failures []error
	for _, job := range jobs {
		amount, parseErr := trading.ParseMoney(job.amount)
		if parseErr != nil { failures = append(failures, parseErr); continue }
		if amount <= 0 {
			_, _ = s.pool.Exec(ctx, `UPDATE owner_cutoff_payouts SET status='COMPLETED',completed_at=now(),updated_at=now() WHERE id=$1 AND status='PREPARED'`, job.id)
			continue
		}
		tag, updateErr := s.pool.Exec(ctx, `UPDATE owner_cutoff_payouts SET status='SENT',sent_at=now(),updated_at=now() WHERE id=$1 AND status='PREPARED'`, job.id)
		if updateErr != nil { failures = append(failures, updateErr); continue }
		if tag.RowsAffected() != 1 { continue }
		response, sendErr := s.provider.Transfer(ctx, collectorID, coin, job.username, job.amount)
		if sendErr != nil {
			_, _ = s.pool.Exec(context.Background(), `UPDATE owner_cutoff_payouts SET status='REVIEW_REQUIRED',failure_reason=$2,updated_at=now() WHERE id=$1`, job.id, sendErr.Error())
			failures = append(failures, fmt.Errorf("%s: %w", job.allocation, sendErr))
			continue
		}
		raw, _ := json.Marshal(response)
		if _, err = s.pool.Exec(ctx, `UPDATE owner_cutoff_payouts SET status='COMPLETED',provider_response=$2,completed_at=now(),updated_at=now() WHERE id=$1 AND status='SENT'`, job.id, raw); err != nil {
			failures = append(failures, err)
		}
	}
	var unresolved int
	if err = s.pool.QueryRow(ctx, `SELECT count(*) FROM owner_cutoff_payouts WHERE batch_id=$1 AND status<>'COMPLETED'`, batchID).Scan(&unresolved); err != nil { return err }
	status := "COMPLETED"; if unresolved > 0 { status = "REVIEW_REQUIRED" }
	_, err = s.pool.Exec(ctx, `UPDATE owner_cutoff_batches SET status=$2,completed_at=CASE WHEN $2='COMPLETED' THEN now() ELSE completed_at END,updated_at=now() WHERE id=$1`, batchID, status)
	if err != nil { failures = append(failures, err) }
	return errors.Join(failures...)
}

func (s *Service) settings(ctx context.Context, keys ...string) (map[string]string, error) {
	rows, err := s.pool.Query(ctx, `SELECT key,value FROM app_settings WHERE key=ANY($1)`, keys)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := map[string]string{}
	for rows.Next() {
		var k, v string
		if err = rows.Scan(&k, &v); err != nil {
			return nil, err
		}
		result[k] = strings.TrimSpace(v)
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	for _, k := range keys {
		if result[k] == "" {
			return nil, fmt.Errorf("pengaturan %s belum tersedia", k)
		}
	}
	return result, nil
}

func newID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	b[6] = (b[6] & 15) | 64
	b[8] = (b[8] & 63) | 128
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}
