package trading

import (
	"context"
	"encoding/json"
	"errors"
	"time"
)

type commandPayload struct {
	Amount  string `json:"amount"`
	Enabled bool   `json:"enabled"`
}

// RunWorker consumes durable commands. Polling is deliberate: PostgreSQL
// NOTIFY is only an accelerator, while the table remains the source of truth.
func (e *Engine) RunWorker(ctx context.Context) error {
	if err := e.commands.RequeueStale(ctx); err != nil {
		return err
	}
	if err := e.Recover(ctx); err != nil {
		return err
	}
	ticker := time.NewTicker(200 * time.Millisecond)
	recoverTicker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	defer recoverTicker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-recoverTicker.C:
			if err := e.commands.RequeueStale(ctx); err != nil {
				e.logger.Error("requeue stale trading command failed", "error", err)
			}
			if err := e.Recover(ctx); err != nil {
				e.logger.Error("recover trading sessions failed", "error", err)
			}
		case <-ticker.C:
			for i := 0; i < 50; i++ {
				command, ok, err := e.commands.Claim(ctx, e.workerID)
				if err != nil {
					e.logger.Error("claim trading command failed", "error", err)
					break
				}
				if !ok {
					break
				}
				processErr := e.processCommand(ctx, command)
				if finishErr := e.commands.Finish(ctx, command.ID, processErr); finishErr != nil {
					e.logger.Error("finish trading command failed", "error", finishErr)
				}
				payload, _ := json.Marshal(map[string]any{"request_id": command.RequestID, "command": command.Command, "ok": processErr == nil, "message": errorString(processErr)})
				_ = e.commands.PublishEvent(ctx, command.UserID, command.SessionID, "COMMAND_RESULT", payload)
			}
		}
	}
}

func (e *Engine) processCommand(ctx context.Context, command Command) error {
	var payload commandPayload
	if err := json.Unmarshal(command.Payload, &payload); err != nil {
		return err
	}
	switch command.Command {
	case "START":
		_, err := e.Start(ctx, command.UserID, payload.Enabled)
		return err
	case "STOP":
		tag, err := e.pool.Exec(ctx, `UPDATE trading_sessions SET status='STOP_REQUESTED',updated_at=now() WHERE user_id=$1 AND status='RUNNING'`, command.UserID)
		if err == nil && tag.RowsAffected() == 0 {
			return errors.New("trading tidak aktif")
		}
		if err == nil {
			status, message := "STOP_REQUESTED", "Trading sedang dihentikan"
			var pending bool
			if queryErr := e.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM provider_bets b JOIN trading_sessions s ON s.id=b.session_id
				WHERE s.user_id=$1 AND s.status='STOP_REQUESTED' AND b.status IN ('PREPARED','SENT','RECONCILIATION_REQUIRED'))`, command.UserID).Scan(&pending); queryErr != nil {
				return queryErr
			}
			if !pending {
				if _, completeErr := e.pool.Exec(ctx, `UPDATE trading_sessions SET status='COMPLETED',stop_reason='Dihentikan pengguna',completed_at=now(),updated_at=now()
					WHERE user_id=$1 AND status='STOP_REQUESTED'`, command.UserID); completeErr != nil {
					return completeErr
				}
				status, message = "COMPLETED", "Dihentikan pengguna"
			}
			payload, _ := json.Marshal(map[string]any{"status": status, "message": message})
			_ = e.commands.PublishEvent(ctx, command.UserID, command.SessionID, "RUNNER_STATE", payload)
		}
		return err
	default:
		return e.Command(ctx, command.UserID, command.Command, payload.Amount, payload.Enabled)
	}
}

func errorString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func (e *Engine) Enqueue(ctx context.Context, requestID string, userID int64, command string, payload json.RawMessage) (string, bool, error) {
	return e.commands.Enqueue(ctx, requestID, userID, nil, command, payload)
}
