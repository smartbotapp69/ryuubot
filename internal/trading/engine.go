package trading

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math/rand"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"ryubot/internal/pasino"
)

type Engine struct {
	pool     *pgxpool.Pool
	provider *pasino.Client
	ledger   *Ledger
	logger   *slog.Logger
	mu       sync.Mutex
	running  map[int64]context.CancelFunc
	events   *eventSubscribers
	workerID string
	commands *CommandQueue
}

func NewEngine(pool *pgxpool.Pool, provider *pasino.Client, logger *slog.Logger, workerID string) *Engine {
	return &Engine{pool: pool, provider: provider, ledger: NewLedger(pool), logger: logger, running: make(map[int64]context.CancelFunc), events: newEventSubscribers(), workerID: workerID, commands: NewCommandQueue(pool)}
}

func (e *Engine) Recover(ctx context.Context) error {
	rows, err := e.pool.Query(ctx, `UPDATE trading_sessions SET worker_id=$1,lease_expires_at=now()+interval '30 seconds',updated_at=now()
		WHERE id IN (SELECT id FROM trading_sessions WHERE status IN ('RUNNING','STOP_REQUESTED')
		AND (lease_expires_at IS NULL OR lease_expires_at<now()) FOR UPDATE SKIP LOCKED LIMIT 100)
		RETURNING id::text,user_id`, e.workerID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var userID int64
		if err = rows.Scan(&id, &userID); err != nil {
			return err
		}
		var sentPending bool
		if _, err = e.pool.Exec(ctx, `UPDATE provider_bets SET status='FAILED_CONFIRMED',response_payload='{"reason":"server restarted before send"}'::jsonb,completed_at=now(),updated_at=now() WHERE session_id=$1 AND status='PREPARED'`, id); err != nil {
			return err
		}
		if err = e.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM provider_bets WHERE session_id=$1 AND status IN ('SENT','RECONCILIATION_REQUIRED'))`, id).Scan(&sentPending); err != nil {
			return err
		}
		if sentPending {
			_, err = e.pool.Exec(ctx, `UPDATE trading_sessions SET status='RECONCILIATION_REQUIRED',stop_reason='Server restart ketika roll belum terselesaikan',updated_at=now() WHERE id=$1`, id)
			if err != nil {
				return err
			}
			continue
		}
		go e.run(userID, id)
	}
	return rows.Err()
}

func (e *Engine) Start(ctx context.Context, userID int64, stopOnWin ...bool) (string, error) {
	var existingID, existingStatus string
	existingErr := e.pool.QueryRow(ctx, `SELECT id::text,status FROM trading_sessions
		WHERE user_id=$1 AND status IN ('RUNNING','STOP_REQUESTED','RECONCILIATION_REQUIRED')
		ORDER BY started_at DESC LIMIT 1`, userID).Scan(&existingID, &existingStatus)
	if existingErr == nil {
		switch existingStatus {
		case "RUNNING":
			e.mu.Lock()
			_, localRunning := e.running[userID]
			e.mu.Unlock()
			if !localRunning {
				tag, claimErr := e.pool.Exec(ctx, `UPDATE trading_sessions SET worker_id=$2,lease_expires_at=now()+interval '30 seconds',updated_at=now()
				WHERE id=$1 AND (worker_id=$2 OR lease_expires_at IS NULL OR lease_expires_at<now())`, existingID, e.workerID)
				if claimErr != nil {
					return "", claimErr
				}
				if tag.RowsAffected() == 1 {
					go e.run(userID, existingID)
				}
			}
			return existingID, nil
		case "STOP_REQUESTED":
			return "", errors.New("sesi trading sebelumnya sedang dihentikan")
		default:
			resolved, reconcileErr := e.reconcileExact(ctx, userID, existingID)
			if reconcileErr != nil {
				return "", reconcileErr
			}
			if !resolved {
				return "", errors.New("hasil roll sebelumnya belum dapat dibuktikan dari saldo Pasino")
			}
		}
	}
	if !errors.Is(existingErr, pgx.ErrNoRows) {
		return "", existingErr
	}
	var username, coin string
	var expires *time.Time
	err := e.pool.QueryRow(ctx, `SELECT u.username,u.subscription_expires_at,s.coin FROM users u JOIN user_trading_settings s ON s.user_id=u.id WHERE u.id=$1 AND u.status='ACTIVE'`, userID).Scan(&username, &expires, &coin)
	if err != nil {
		return "", err
	}
	if expires == nil || expires.Before(time.Now()) {
		return "", errors.New("masa aktif akun telah berakhir")
	}
	settings, raw, err := e.settings(ctx, userID)
	if err != nil {
		return "", err
	}
	// Sama dengan base: sesi baru selalu mulai dengan Stop Win OFF. Tombol
	// Stop Win hanya mengubah sesi yang sedang berjalan.
	settings.StopOnWin = len(stopOnWin) > 0 && stopOnWin[0]
	raw, _ = json.Marshal(settings)
	rules, ruleRaw, err := LoadBusinessRules(ctx, e.pool, coin)
	if err != nil {
		return "", err
	}
	if settings.BaseBet < rules.MinimumBet {
		return "", fmt.Errorf("minimum base trade %s %s", rules.MinimumBet.String(), coin)
	}
	providerBalance, err := e.provider.Balance(ctx, userID, coin)
	if err != nil {
		return "", err
	}
	opening, err := ParseMoney(providerBalance)
	if err != nil {
		return "", err
	}
	var reservedText string
	if err = e.pool.QueryRow(ctx, `SELECT coalesce((SELECT holding_pending+kangden_pending FROM trading_fee_balances WHERE user_id=$1 AND coin=$2),0)::text`, userID, coin).Scan(&reservedText); err != nil {
		return "", err
	}
	reserved, err := ParseMoney(reservedText)
	if err != nil {
		return "", err
	}
	opening -= reserved
	if opening < settings.BaseBet {
		return "", errors.New("saldo tersedia tidak mencukupi")
	}
	_ = username
	id, err := e.ledger.Start(ctx, SessionStart{UserID: userID, Coin: coin, SettingsSnapshot: raw, RuleSnapshot: ruleRaw, OpeningBalance: opening, BaseBet: settings.BaseBet})
	if err != nil {
		// Dua START dapat tiba hampir bersamaan. Constraint database tetap
		// menjadi pengaman terakhir, tetapi pengguna tidak boleh melihat error SQL.
		if lookupErr := e.pool.QueryRow(ctx, `SELECT id::text,status FROM trading_sessions
			WHERE user_id=$1 AND status IN ('RUNNING','STOP_REQUESTED','RECONCILIATION_REQUIRED')
			ORDER BY started_at DESC LIMIT 1`, userID).Scan(&existingID, &existingStatus); lookupErr == nil {
			if existingStatus == "RUNNING" {
				return existingID, nil
			}
			if existingStatus == "STOP_REQUESTED" {
				return "", errors.New("sesi trading sebelumnya sedang dihentikan")
			}
			return "", errors.New("sesi trading sebelumnya perlu rekonsiliasi")
		}
		return "", errors.New("sesi trading tidak dapat dimulai")
	}
	if _, err = e.pool.Exec(ctx, `UPDATE trading_sessions SET worker_id=$2,lease_expires_at=now()+interval '30 seconds' WHERE id=$1`, id, e.workerID); err != nil {
		return "", err
	}
	e.publishState(ctx, userID, id, "RUNNING", "Trading dimulai")
	go e.run(userID, id)
	return id, nil
}

func (e *Engine) reconcileExact(ctx context.Context, userID int64, sessionID string) (bool, error) {
	var bet PreparedBet
	var amountText, payloadText, coin, visibleText, cycleText, last string
	var wins, losses, streak int
	var ruleRaw []byte
	err := e.pool.QueryRow(ctx, `SELECT b.id::text,b.amount::text,b.request_payload::text,s.coin,s.visible_user_balance::text,
		s.profit_cycle::text,s.wins,s.losses,s.streak,coalesce(s.last_result,''),s.rule_snapshot
		FROM provider_bets b JOIN trading_sessions s ON s.id=b.session_id
		WHERE s.id=$1 AND s.user_id=$2 AND s.status='RECONCILIATION_REQUIRED'
		AND b.status IN ('SENT','RECONCILIATION_REQUIRED') ORDER BY b.prepared_at DESC LIMIT 1`, sessionID, userID).
		Scan(&bet.ID, &amountText, &payloadText, &coin, &visibleText, &cycleText, &wins, &losses, &streak, &last, &ruleRaw)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	bet.SessionID, bet.UserID, bet.Coin = sessionID, userID, coin
	if bet.Amount, err = ParseMoney(amountText); err != nil {
		return false, err
	}
	var payload struct {
		Profit        string `json:"profit"`
		WinningChance string `json:"winning_chance"`
	}
	if err = json.Unmarshal([]byte(payloadText), &payload); err != nil {
		return false, err
	}
	bet.Chance = payload.WinningChance
	winGross, err := ParseMoney(payload.Profit)
	if err != nil {
		return false, err
	}
	visible, _ := ParseMoney(visibleText)
	var reservedText string
	if err = e.pool.QueryRow(ctx, `SELECT coalesce((SELECT holding_pending+kangden_pending FROM trading_fee_balances WHERE user_id=$1 AND coin=$2),0)::text`, userID, coin).Scan(&reservedText); err != nil {
		return false, err
	}
	reserved, _ := ParseMoney(reservedText)
	before := visible + reserved
	liveText, err := e.provider.Balance(ctx, userID, coin)
	if err != nil {
		return false, err
	}
	live, err := ParseMoney(liveText)
	if err != nil {
		return false, err
	}
	outcome, gross := Result(""), Money(0)
	if live == before+winGross {
		outcome, gross = Win, winGross
	} else if live == before-bet.Amount {
		outcome, gross = Loss, -bet.Amount
	} else {
		return false, nil
	}
	var rules BusinessRules
	if err = json.Unmarshal(ruleRaw, &rules); err != nil {
		return false, err
	}
	var username string
	if err = e.pool.QueryRow(ctx, `SELECT username FROM users WHERE id=$1`, userID).Scan(&username); err != nil {
		return false, err
	}
	exempt := strings.EqualFold(username, rules.FeeExemptUsername)
	allocation, err := AllocateProfit(gross, AllocationRule{HoldingBPS: rules.HoldingBPS, KangdenBPS: rules.KangdenBPS, FeeExemptUsername: rules.FeeExemptUsername}, exempt)
	if err != nil {
		return false, err
	}
	settings, _, err := e.settings(ctx, userID)
	if err != nil {
		return false, err
	}
	cycle, _ := ParseSignedMoney(cycleText)
	next, err := Advance(settings.Runtime, RuntimeState{CurrentBet: bet.Amount, ProfitCycle: cycle, Wins: wins, Losses: losses, Streak: streak, LastResult: Result(last)}, outcome, allocation.UserProfit)
	if err != nil {
		return false, err
	}
	response, _ := json.Marshal(map[string]any{"action": "bet_update_reconciled", "coin": coin, "profit": gross.String(), "balance": live.String(), "reconciliation": "EXACT_PROVIDER_BALANCE_MATCH"})
	if err = e.ledger.Settle(ctx, bet, Settlement{ProviderBalanceBefore: before, ProviderBalanceAfter: live, GrossProfit: gross, Result: outcome, LastResult: next.LastResult, Allocation: allocation, NextBet: next.CurrentBet, Wins: next.Wins, Losses: next.Losses, Streak: next.Streak, ProfitCycle: next.ProfitCycle, Response: response, ReferralBPS: rules.ReferralBPS, FeeExempt: exempt}); err != nil {
		return false, err
	}
	if err = e.ledger.Complete(ctx, sessionID, "Direkonsiliasi dari saldo Pasino"); err != nil {
		return false, err
	}
	e.publishState(ctx, userID, sessionID, "COMPLETED", "Rekonsiliasi selesai")
	return true, nil
}

func (e *Engine) Command(ctx context.Context, userID int64, command, amountText string, enabled bool) error {
	command = strings.ToUpper(strings.TrimSpace(command))
	switch command {
	case "OVERRIDE":
		amount, err := ParseMoney(amountText)
		if err != nil || amount <= 0 {
			return errors.New("nominal override tidak valid")
		}
		tag, err := e.pool.Exec(ctx, `UPDATE trading_sessions SET next_override=$2,updated_at=now() WHERE user_id=$1 AND status='RUNNING'`, userID, amount.String())
		if err != nil {
			return err
		}
		if tag.RowsAffected() != 1 {
			return errors.New("trading tidak aktif")
		}
		return nil
	case "RESET":
		var pending bool
		err := e.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM provider_bets b JOIN trading_sessions s ON s.id=b.session_id WHERE s.user_id=$1 AND s.status='RUNNING' AND b.status IN ('PREPARED','SENT'))`, userID).Scan(&pending)
		if err != nil {
			return err
		}
		var affected int64
		if pending {
			tag, updateErr := e.pool.Exec(ctx, `UPDATE trading_sessions SET reset_after_pending=true,next_override=NULL,updated_at=now() WHERE user_id=$1 AND status='RUNNING'`, userID)
			if updateErr != nil {
				return updateErr
			}
			affected = tag.RowsAffected()
		} else {
			tag, updateErr := e.pool.Exec(ctx, `UPDATE trading_sessions SET current_bet=(SELECT base_bet FROM user_trading_settings WHERE user_id=$1),next_override=NULL,profit_cycle=0,streak=0,last_result=NULL,max_win_streak=0,max_loss_streak=0,reset_after_pending=false,updated_at=now() WHERE user_id=$1 AND status='RUNNING'`, userID)
			if updateErr != nil {
				return updateErr
			}
			affected = tag.RowsAffected()
		}
		if affected != 1 {
			return errors.New("trading tidak aktif")
		}
		return nil
	case "STOP_ON_WIN":
		tag, err := e.pool.Exec(ctx, `UPDATE trading_sessions
			SET settings_snapshot=jsonb_set(settings_snapshot,'{StopOnWin}',to_jsonb($2::boolean)),updated_at=now()
			WHERE user_id=$1 AND status='RUNNING'`, userID, enabled)
		if err != nil {
			return err
		}
		if tag.RowsAffected() != 1 {
			return errors.New("trading tidak aktif")
		}
		return nil
	default:
		return errors.New("command trading tidak dikenal")
	}
}

func (e *Engine) run(userID int64, sessionID string) {
	ctx, cancel := context.WithCancel(context.Background())
	e.mu.Lock()
	if old := e.running[userID]; old != nil {
		old()
	}
	e.running[userID] = cancel
	e.mu.Unlock()
	defer func() { cancel(); e.mu.Lock(); delete(e.running, userID); e.mu.Unlock() }()
	time.Sleep(time.Duration(rand.Intn(500)) * time.Millisecond)
	for {
		stop, delay, err := e.roll(ctx, userID, sessionID)
		if err != nil {
			e.logger.Error("trading roll stopped", "user_id", userID, "session_id", sessionID, "error", err)
			var status string
			if queryErr := e.pool.QueryRow(context.Background(), `SELECT status FROM trading_sessions WHERE id=$1`, sessionID).Scan(&status); queryErr == nil && (status == "RUNNING" || status == "STOP_REQUESTED") {
				if completeErr := e.ledger.Complete(context.Background(), sessionID, err.Error()); completeErr != nil {
					e.logger.Error("complete failed trading session", "user_id", userID, "session_id", sessionID, "error", completeErr)
				}
			}
			e.publishState(context.Background(), userID, sessionID, "COMPLETED", err.Error())
			return
		}
		if stop {
			var status, reason string
			if queryErr := e.pool.QueryRow(context.Background(), `SELECT status,coalesce(stop_reason,'') FROM trading_sessions WHERE id=$1`, sessionID).Scan(&status, &reason); queryErr == nil {
				e.publishState(context.Background(), userID, sessionID, status, reason)
			}
			return
		}
		select {
		case <-time.After(delay):
		case <-ctx.Done():
			return
		}
	}
}

func (e *Engine) publishState(ctx context.Context, userID int64, sessionID, status, message string) {
	payload, _ := json.Marshal(map[string]any{"status": status, "message": message})
	if err := e.commands.PublishEvent(ctx, userID, &sessionID, "RUNNER_STATE", payload); err != nil {
		e.logger.Error("publish runner state failed", "user_id", userID, "session_id", sessionID, "error", err)
	}
}

func (e *Engine) roll(ctx context.Context, userID int64, sessionID string) (bool, time.Duration, error) {
	rollStartedAt := time.Now()
	tag, err := e.pool.Exec(ctx, `UPDATE trading_sessions SET lease_expires_at=now()+interval '30 seconds',updated_at=now()
		WHERE id=$1 AND worker_id=$2 AND status IN ('RUNNING','STOP_REQUESTED')`, sessionID, e.workerID)
	if err != nil || tag.RowsAffected() != 1 {
		if err != nil {
			return true, 0, err
		}
		return true, 0, errors.New("kepemilikan sesi trading berpindah")
	}
	var status, coin, currentText, profitText, cycleText, last string
	var overrideText *string
	var resetPending bool
	var wins, losses, streak int
	var ruleRaw, settingsRaw []byte
	err = e.pool.QueryRow(ctx, `SELECT status,coin,current_bet::text,profit::text,profit_cycle::text,wins,losses,streak,coalesce(last_result,''),rule_snapshot,settings_snapshot,next_override::text,reset_after_pending FROM trading_sessions WHERE id=$1`, sessionID).Scan(&status, &coin, &currentText, &profitText, &cycleText, &wins, &losses, &streak, &last, &ruleRaw, &settingsRaw, &overrideText, &resetPending)
	if err != nil {
		return true, 0, err
	}
	if status == "STOP_REQUESTED" {
		return true, 0, e.ledger.Complete(ctx, sessionID, "Dihentikan pengguna")
	}
	if status != "RUNNING" {
		return true, 0, nil
	}
	var settings engineSettings
	if err = json.Unmarshal(settingsRaw, &settings); err != nil {
		return true, 0, fmt.Errorf("snapshot pengaturan sesi tidak valid: %w", err)
	}
	current, err := ParseMoney(currentText)
	if err != nil {
		return true, 0, err
	}
	if resetPending {
		current = settings.BaseBet
		streak = 0
		last = ""
		_, err = e.pool.Exec(ctx, `UPDATE trading_sessions SET reset_after_pending=false,current_bet=$2,streak=0,last_result=NULL,updated_at=now() WHERE id=$1`, sessionID, current.String())
		if err != nil {
			return true, 0, err
		}
	}
	if overrideText != nil {
		current, err = ParseMoney(*overrideText)
		if err != nil {
			return true, 0, err
		}
		_, err = e.pool.Exec(ctx, `UPDATE trading_sessions SET next_override=NULL,current_bet=$2,updated_at=now() WHERE id=$1`, sessionID, current.String())
		if err != nil {
			return true, 0, err
		}
	}
	profit, _ := ParseSignedMoney(profitText)
	cycle, _ := ParseSignedMoney(cycleText)
	var rules BusinessRules
	if err = json.Unmarshal(ruleRaw, &rules); err != nil {
		return true, 0, err
	}
	var visible string
	if err = e.pool.QueryRow(ctx, `SELECT visible_user_balance::text FROM trading_sessions WHERE id=$1`, sessionID).Scan(&visible); err != nil {
		return true, 0, err
	}
	available, _ := ParseMoney(visible)
	var reservedText string
	if err = e.pool.QueryRow(ctx, `SELECT coalesce((SELECT holding_pending+kangden_pending FROM trading_fee_balances WHERE user_id=$1 AND coin=$2),0)::text`, userID, coin).Scan(&reservedText); err != nil {
		return true, 0, err
	}
	reserved, _ := ParseMoney(reservedText)
	providerBefore := available + reserved
	if current > available {
		return true, 0, e.ledger.Complete(ctx, sessionID, "Saldo tidak mencukupi")
	}
	if settings.MaximumBet > 0 && current > settings.MaximumBet {
		return true, 0, e.ledger.Complete(ctx, sessionID, "Melebihi maximum bet")
	}
	payload, _, err := BuildBetPayload(current, BetConfig{Coin: coin, ChanceMin: settings.ChanceMin, ChanceMax: settings.ChanceMax})
	if err != nil {
		return true, 0, err
	}
	rawPayload, _ := json.Marshal(payload)
	bet, err := e.ledger.PrepareBet(ctx, sessionID, current, payload.WinningChance, rawPayload)
	if err != nil {
		return true, 0, err
	}
	if err = e.ledger.MarkSent(ctx, bet.ID); err != nil {
		return true, 0, err
	}
	response, err := e.provider.PlaceBet(ctx, userID, map[string]any{"method": payload.Method, "bet_amt": payload.BetAmount, "coin": payload.Coin, "client_seed": payload.ClientSeed, "type": payload.Type, "payout": payload.Payout, "winning_chance": payload.WinningChance, "profit": payload.Profit})
	if err != nil {
		var unknown *pasino.OutcomeUnknownError
		if errors.As(err, &unknown) {
			_ = e.ledger.RequireReconciliation(context.Background(), bet, err.Error())
			return true, 0, err
		}
		_ = e.ledger.FailConfirmed(context.Background(), bet, err.Error())
		return true, 0, err
	}
	var result map[string]any
	decoder := json.NewDecoder(strings.NewReader(string(response)))
	decoder.UseNumber()
	if err = decoder.Decode(&result); err != nil {
		_ = e.ledger.RequireReconciliation(context.Background(), bet, "Respons Pasino tidak valid")
		return true, 0, err
	}
	if success, exists := result["success"].(bool); exists && !success {
		reason := strings.TrimSpace(fmt.Sprint(result["message"]))
		if reason == "" || reason == "<nil>" {
			reason = "Taruhan ditolak Pasino"
		}
		if err = e.ledger.FailConfirmed(context.Background(), bet, reason); err != nil {
			return true, 0, err
		}
		return true, 0, errors.New(reason)
	}
	win := boolValue(result["win"])
	gross, err := ParseProviderSignedMoney(fmt.Sprint(result["profit"]))
	if err != nil {
		_ = e.ledger.RequireReconciliation(context.Background(), bet, "Profit Pasino tidak valid")
		return true, 0, err
	}
	outcome := Loss
	if win {
		outcome = Win
	}
	var username string
	if err = e.pool.QueryRow(ctx, `SELECT username FROM users WHERE id=$1`, userID).Scan(&username); err != nil {
		return true, 0, err
	}
	exempt := strings.EqualFold(username, rules.FeeExemptUsername)
	allocation, err := AllocateProfit(gross, AllocationRule{HoldingBPS: rules.HoldingBPS, KangdenBPS: rules.KangdenBPS, FeeExemptUsername: rules.FeeExemptUsername}, exempt)
	if err != nil {
		return true, 0, err
	}
	if err = e.pool.QueryRow(ctx, `SELECT reset_after_pending FROM trading_sessions WHERE id=$1`, sessionID).Scan(&resetPending); err != nil {
		return true, 0, err
	}
	next, err := Advance(settings.Runtime, RuntimeState{CurrentBet: current, ProfitCycle: cycle, Wins: wins, Losses: losses, Streak: streak, LastResult: Result(last), ManualReset: resetPending}, outcome, allocation.UserProfit)
	if err != nil {
		return true, 0, err
	}
	providerRef := strings.TrimSpace(fmt.Sprint(result["bet_id"]))
	if providerRef == "<nil>" {
		providerRef = ""
	}
	responseRaw, _ := json.Marshal(result)
	if err = e.ledger.Settle(ctx, bet, Settlement{ProviderReference: providerRef, ProviderBalanceBefore: providerBefore, ProviderBalanceAfter: providerBefore + gross, GrossProfit: gross, Result: outcome, LastResult: next.LastResult, Allocation: allocation, NextBet: next.CurrentBet, Wins: next.Wins, Losses: next.Losses, Streak: next.Streak, ProfitCycle: next.ProfitCycle, Response: responseRaw, ReferralBPS: rules.ReferralBPS, FeeExempt: exempt}); err != nil {
		return true, 0, err
	}
	profit += allocation.UserProfit
	newBalance := available + allocation.UserProfit
	if err = e.pool.QueryRow(ctx, `SELECT status,coalesce((settings_snapshot->>'StopOnWin')::boolean,false)
		FROM trading_sessions WHERE id=$1`, sessionID).Scan(&status, &settings.StopOnWin); err != nil {
		return true, 0, err
	}
	if status == "STOP_REQUESTED" {
		return true, 0, e.ledger.Complete(ctx, sessionID, "Dihentikan pengguna")
	}
	stopReason := ""
	if settings.StopOnWin && win {
		stopReason = "Stop Win tercapai"
	} else if settings.TakeProfit > 0 && profit >= settings.TakeProfit {
		stopReason = "Take Profit tercapai"
	} else if settings.StopLoss > 0 && profit <= -settings.StopLoss {
		stopReason = "Stop Loss tercapai"
	} else if settings.BalanceBelow > 0 && newBalance <= settings.BalanceBelow {
		stopReason = "Balance Below tercapai"
	}
	if stopReason != "" {
		return true, 0, e.ledger.Complete(ctx, sessionID, stopReason)
	}
	delay := time.Duration(settings.DelayMS)*time.Millisecond - time.Since(rollStartedAt)
	if delay < 0 {
		delay = 0
	}
	if delay < 1*time.Second {
		delay = 1 * time.Second
	}
	return false, delay, nil
}

type engineSettings struct {
	Runtime                                                 RuntimeConfig
	BaseBet, MaximumBet, TakeProfit, StopLoss, BalanceBelow Money
	ChanceMin, ChanceMax                                    string
	DelayMS                                                 int
	StopOnWin                                               bool
}

func (e *Engine) settings(ctx context.Context, userID int64) (engineSettings, json.RawMessage, error) {
	var s engineSettings
	var mw, ml, bw, bl, tp, sl, ps, bb, max, below string
	var rw, rl, baw, bal int
	err := e.pool.QueryRow(ctx, `SELECT base_bet::text,chance_min::integer::text,chance_max::integer::text,delay_ms,martingale_on_win::integer::text,martingale_on_loss::integer::text,reset_after_wins,reset_after_losses,boom_after_wins,boom_win_amount::text,boom_after_losses,boom_loss_amount::text,take_profit::text,stop_loss::text,profit_session::text,balance_below::text,stop_on_win,maximum_bet::text FROM user_trading_settings WHERE user_id=$1`, userID).Scan(&bb, &s.ChanceMin, &s.ChanceMax, &s.DelayMS, &mw, &ml, &rw, &rl, &baw, &bw, &bal, &bl, &tp, &sl, &ps, &below, &s.StopOnWin, &max)
	if err != nil {
		return s, nil, err
	}
	parse := func(v string) (Money, error) { return ParseMoney(v) }
	if s.BaseBet, err = parse(bb); err != nil {
		return s, nil, err
	}
	s.MaximumBet, _ = parse(max)
	s.TakeProfit, _ = parse(tp)
	s.StopLoss, _ = parse(sl)
	s.BalanceBelow, _ = parse(below)
	boomW, _ := parse(bw)
	boomL, _ := parse(bl)
	profitSession, _ := parse(ps)
	s.Runtime = RuntimeConfig{BaseBet: s.BaseBet, MartingaleOnWin: mw, MartingaleOnLoss: ml, ResetAfterWins: rw, ResetAfterLosses: rl, BoomAfterWins: baw, BoomWinAmount: boomW, BoomAfterLosses: bal, BoomLossAmount: boomL, ProfitSession: profitSession}
	raw, _ := json.Marshal(s)
	return s, raw, nil
}

// SyncSettings applies saved user settings to the active session beginning on
// the next roll, while preserving the session-only Stop Win switch.
func (e *Engine) SyncSettings(ctx context.Context, userID int64) error {
	settings, _, err := e.settings(ctx, userID)
	if err != nil {
		return err
	}
	var stopOnWin bool
	err = e.pool.QueryRow(ctx, `SELECT coalesce((settings_snapshot->>'StopOnWin')::boolean,false)
		FROM trading_sessions WHERE user_id=$1 AND status='RUNNING' ORDER BY started_at DESC LIMIT 1`, userID).Scan(&stopOnWin)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	settings.StopOnWin = stopOnWin
	raw, err := json.Marshal(settings)
	if err != nil {
		return err
	}
	_, err = e.pool.Exec(ctx, `UPDATE trading_sessions SET
		current_bet=CASE WHEN settings_snapshot->>'BaseBet'<>($2::jsonb->>'BaseBet') THEN ($2::jsonb->>'BaseBet')::numeric ELSE current_bet END,
		next_override=CASE WHEN settings_snapshot->>'BaseBet'<>($2::jsonb->>'BaseBet') THEN NULL ELSE next_override END,
		settings_snapshot=$2,updated_at=now()
		WHERE user_id=$1 AND status='RUNNING'`, userID, raw)
	return err
}
func boolValue(v any) bool {
	switch x := v.(type) {
	case bool:
		return x
	case float64:
		return x == 1
	case json.Number:
		return x.String() == "1"
	case string:
		b, _ := strconv.ParseBool(x)
		if b {
			return true
		}
		return x == "1"
	}
	return false
}
