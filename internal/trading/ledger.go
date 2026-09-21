package trading

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrReconciliationRequired = errors.New("trading session requires reconciliation")

type Ledger struct{ pool *pgxpool.Pool }

func NewLedger(pool *pgxpool.Pool) *Ledger { return &Ledger{pool: pool} }

type SessionStart struct {
	UserID           int64
	Coin             string
	SettingsSnapshot json.RawMessage
	RuleSnapshot     json.RawMessage
	OpeningBalance   Money
	BaseBet          Money
}
type PreparedBet struct {
	ID, SessionID string
	UserID        int64
	Coin          string
	Amount        Money
	Chance        string
}
type Settlement struct {
	ProviderReference     string
	ProviderBalanceBefore Money
	ProviderBalanceAfter  Money
	GrossProfit           Money
	Result                Result
	LastResult            Result
	Allocation            Allocation
	NextBet               Money
	Wins                  int
	Losses                int
	Streak                int
	ProfitCycle           Money
	Response              json.RawMessage
	ReferralBPS           []int64
	FeeExempt             bool
}

func (l *Ledger) Start(ctx context.Context, input SessionStart) (string, error) {
	if input.UserID <= 0 || input.Coin == "" || input.OpeningBalance < 0 || input.BaseBet <= 0 {
		return "", errors.New("session input invalid")
	}
	id, err := newID()
	if err != nil {
		return "", err
	}
	_, err = l.pool.Exec(ctx, `INSERT INTO trading_sessions(id,user_id,coin,status,settings_snapshot,rule_snapshot,opening_provider_balance,visible_user_balance,current_bet)
		VALUES($1,$2,$3,'RUNNING',$4,$5,$6,$6,$7)`, id, input.UserID, input.Coin, input.SettingsSnapshot, input.RuleSnapshot, input.OpeningBalance.String(), input.BaseBet.String())
	if err != nil {
		return "", fmt.Errorf("start trading session: %w", err)
	}
	return id, nil
}

// PrepareBet commits intent before the provider sees a request. A unique
// pending index prevents concurrent bets for the same session.
func (l *Ledger) PrepareBet(ctx context.Context, sessionID string, amount Money, chance string, payload json.RawMessage) (PreparedBet, error) {
	if amount <= 0 {
		return PreparedBet{}, errors.New("bet amount invalid")
	}
	tx, err := l.pool.Begin(ctx)
	if err != nil {
		return PreparedBet{}, err
	}
	defer tx.Rollback(ctx)
	var bet PreparedBet
	var status string
	if err = tx.QueryRow(ctx, `SELECT user_id,coin,status FROM trading_sessions WHERE id=$1 FOR UPDATE`, sessionID).Scan(&bet.UserID, &bet.Coin, &status); err != nil {
		return PreparedBet{}, err
	}
	if status == "RECONCILIATION_REQUIRED" {
		return PreparedBet{}, ErrReconciliationRequired
	}
	if status != "RUNNING" {
		return PreparedBet{}, errors.New("trading session is not running")
	}
	var pending bool
	if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM provider_bets WHERE session_id=$1 AND status IN ('PREPARED','SENT','RECONCILIATION_REQUIRED'))`, sessionID).Scan(&pending); err != nil {
		return PreparedBet{}, err
	}
	if pending {
		return PreparedBet{}, errors.New("a provider bet is already pending")
	}
	bet.ID, err = newID()
	if err != nil {
		return PreparedBet{}, err
	}
	bet.SessionID = sessionID
	bet.Amount = amount
	bet.Chance = chance
	_, err = tx.Exec(ctx, `INSERT INTO provider_bets(id,session_id,user_id,coin,amount,chance,status,request_payload) VALUES($1,$2,$3,$4,$5,$6,'PREPARED',$7)`, bet.ID, bet.SessionID, bet.UserID, bet.Coin, amount.String(), chance, payload)
	if err != nil {
		return PreparedBet{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return PreparedBet{}, err
	}
	return bet, nil
}

func (l *Ledger) MarkSent(ctx context.Context, betID string) error {
	tag, err := l.pool.Exec(ctx, `UPDATE provider_bets SET status='SENT',sent_at=now(),updated_at=now() WHERE id=$1 AND status='PREPARED'`, betID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return errors.New("bet cannot be marked sent")
	}
	return nil
}

// Settle is idempotent by state: only a SENT bet can alter ledger balances.
func (l *Ledger) Settle(ctx context.Context, bet PreparedBet, input Settlement) error {
	if input.Result != Win && input.Result != Loss {
		return errors.New("invalid result")
	}
	if input.Allocation.UserProfit+input.Allocation.HoldingAmount+input.Allocation.KangdenAmount != input.GrossProfit {
		return errors.New("settlement allocation does not balance")
	}
	if input.NextBet <= 0 {
		return errors.New("next bet invalid")
	}
	tx, err := l.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var betStatus string
	if err = tx.QueryRow(ctx, `SELECT status FROM provider_bets WHERE id=$1 FOR UPDATE`, bet.ID).Scan(&betStatus); err != nil {
		return err
	}
	if betStatus != "SENT" && betStatus != "RECONCILIATION_REQUIRED" {
		return errors.New("bet is not awaiting settlement")
	}
	if input.Wins < 0 || input.Losses < 0 || input.Streak < 0 {
		return errors.New("invalid settlement state")
	}
	if err = tx.QueryRow(ctx, `SELECT id FROM trading_sessions WHERE id=$1 FOR UPDATE`, bet.SessionID).Scan(new(string)); err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `UPDATE provider_bets SET status='COMPLETED',provider_reference=nullif($2,''),provider_balance_before=$3,provider_balance_after=$4,gross_profit=$5,user_profit=$6,holding_amount=$7,kangden_amount=$8,result=$9,response_payload=$10,completed_at=now(),updated_at=now() WHERE id=$1`, bet.ID, input.ProviderReference, input.ProviderBalanceBefore.String(), input.ProviderBalanceAfter.String(), input.GrossProfit.String(), input.Allocation.UserProfit.String(), input.Allocation.HoldingAmount.String(), input.Allocation.KangdenAmount.String(), string(input.Result), input.Response)
	if err != nil {
		return err
	}
	if input.Allocation.HoldingAmount > 0 || input.Allocation.KangdenAmount > 0 {
		if _, err = tx.Exec(ctx, `INSERT INTO trading_fee_balances(user_id,coin,holding_pending,kangden_pending)
			VALUES($1,$2,$3,$4) ON CONFLICT(user_id,coin) DO UPDATE SET
			holding_pending=trading_fee_balances.holding_pending+excluded.holding_pending,
			kangden_pending=trading_fee_balances.kangden_pending+excluded.kangden_pending,updated_at=now()`,
			bet.UserID, bet.Coin, input.Allocation.HoldingAmount.String(), input.Allocation.KangdenAmount.String()); err != nil {
			return err
		}
	}
	var visibleBalance string
	var sessionProfit string
	var maxWinStreak, maxLossStreak, activeStreak int
	err = tx.QueryRow(ctx, `UPDATE trading_sessions SET visible_user_balance=greatest(visible_user_balance+$2::numeric,0),profit=profit+$2::numeric,profit_cycle=$3,current_bet=$4,wins=$5,losses=$6,streak=$7,last_result=nullif($8,''),max_win_streak=CASE WHEN $8='WIN' THEN greatest(max_win_streak,$7) ELSE max_win_streak END,max_loss_streak=CASE WHEN $8='LOSS' THEN greatest(max_loss_streak,$7) ELSE max_loss_streak END,reset_after_pending=false,updated_at=now() WHERE id=$1 RETURNING visible_user_balance::text,profit::text,max_win_streak,max_loss_streak,streak`, bet.SessionID, input.Allocation.UserProfit.String(), input.ProfitCycle.String(), input.NextBet.String(), input.Wins, input.Losses, input.Streak, string(input.LastResult)).Scan(&visibleBalance, &sessionProfit, &maxWinStreak, &maxLossStreak, &activeStreak)
	if err != nil {
		return err
	}
	// Hasil roll, saldo bersih, dan ledger fee berada dalam transaksi yang
	// sama. UI tidak mungkin menerima roll tanpa saldo tersimpan atau saldo
	// berubah tanpa baris roll yang dapat dimuat ulang setelah reconnect.
	_, err = tx.Exec(ctx, `INSERT INTO trading_events(user_id,session_id,event_type,payload)
		VALUES($1,$2,'ROLL_SETTLED',jsonb_build_object(
			'bet_id',$3::text,'coin',$4::text,'amount',$5::text,'result',$6::text,
			'user_profit',$7::text,'gross_profit',$8::text,'balance_after',$9::text,
			'wins',$10::int,'losses',$11::int,'streak',$12::int,'session_profit',$13::text,'last_result',$6::text))`,
		bet.UserID, bet.SessionID, bet.ID, bet.Coin, bet.Amount.String(), string(input.Result),
		input.Allocation.UserProfit.String(), input.GrossProfit.String(), visibleBalance,
		maxWinStreak, maxLossStreak, activeStreak, sessionProfit)
	if err != nil {
		return err
	}
	if input.Result == Win && input.GrossProfit > 0 && !input.FeeExempt {
		if err = l.accrueReferral(ctx, tx, bet, input); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func (l *Ledger) accrueReferral(ctx context.Context, tx pgx.Tx, bet PreparedBet, input Settlement) error {
	current := bet.UserID
	for level, bps := range input.ReferralBPS {
		if level >= 3 || bps <= 0 {
			continue
		}
		var next *int64
		if err := tx.QueryRow(ctx, `SELECT referrer_user_id FROM user_referrals WHERE user_id=$1`, current).Scan(&next); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				break
			}
			return err
		}
		if next == nil {
			break
		}
		amount, err := percentageOf(input.GrossProfit, bps)
		if err != nil {
			return err
		}
		if amount > 0 {
			eventID, err := newID()
			if err != nil {
				return err
			}
			source := fmt.Sprintf("provider-bet:%s:referral:%d", bet.ID, level+1)
			tag, err := tx.Exec(ctx, `INSERT INTO referral_bonus_events(id,user_id,coin,amount,event_type,source_external_id) VALUES($1,$2,$3,$4,'TRADING_ACCRUAL',$5) ON CONFLICT(event_type,source_external_id) DO NOTHING`, eventID, *next, bet.Coin, amount.String(), source)
			if err != nil {
				return err
			}
			if tag.RowsAffected() == 1 {
				if _, err = tx.Exec(ctx, `INSERT INTO referral_bonus_balances(user_id,coin,available_amount) VALUES($1,$2,$3) ON CONFLICT(user_id,coin) DO UPDATE SET available_amount=referral_bonus_balances.available_amount+excluded.available_amount,updated_at=now()`, *next, bet.Coin, amount.String()); err != nil {
					return err
				}
			}
		}
		current = *next
	}
	return nil
}

// Reconciliation is terminal for automatic execution. An administrator must
// inspect the provider outcome before this session can be resolved.
func (l *Ledger) RequireReconciliation(ctx context.Context, bet PreparedBet, reason string) error {
	tx, err := l.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, `UPDATE provider_bets SET status='RECONCILIATION_REQUIRED',response_payload=jsonb_build_object('reason',$2),updated_at=now() WHERE id=$1 AND status IN ('PREPARED','SENT')`, bet.ID, reason)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `UPDATE trading_sessions SET status='RECONCILIATION_REQUIRED',stop_reason=$2,updated_at=now() WHERE id=$1`, bet.SessionID, reason)
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// FailConfirmed is used only when Pasino returns an explicit rejection before
// any outcome exists. It must never be used for a timeout/disconnect.
func (l *Ledger) FailConfirmed(ctx context.Context, bet PreparedBet, reason string) error {
	tx, err := l.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, `UPDATE provider_bets SET status='FAILED_CONFIRMED',response_payload=jsonb_build_object('reason',$2),completed_at=now(),updated_at=now() WHERE id=$1 AND status='SENT'`, bet.ID, reason)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return errors.New("bet cannot be failed")
	}
	_, err = tx.Exec(ctx, `UPDATE trading_sessions SET status='COMPLETED',stop_reason=$2,completed_at=now(),updated_at=now() WHERE id=$1`, bet.SessionID, reason)
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (l *Ledger) Complete(ctx context.Context, sessionID, reason string) error {
	tag, err := l.pool.Exec(ctx, `UPDATE trading_sessions SET status='COMPLETED',stop_reason=$2,completed_at=now(),updated_at=now() WHERE id=$1 AND status IN ('RUNNING','STOP_REQUESTED','RECONCILIATION_REQUIRED')`, sessionID, reason)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return errors.New("session cannot be completed")
	}
	return nil
}

func (l *Ledger) RequestStop(ctx context.Context, sessionID string) error {
	tag, err := l.pool.Exec(ctx, `UPDATE trading_sessions SET status='STOP_REQUESTED',updated_at=now() WHERE id=$1 AND status='RUNNING'`, sessionID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return errors.New("session cannot be stopped")
	}
	return nil
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
