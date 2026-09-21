package trading

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Command struct {
	ID, RequestID, Command string
	UserID                 int64
	SessionID              *string
	Payload                json.RawMessage
	CreatedAt              time.Time
}

type CommandQueue struct{ pool *pgxpool.Pool }

func NewCommandQueue(pool *pgxpool.Pool) *CommandQueue { return &CommandQueue{pool: pool} }

// Enqueue commits the durable command before PostgreSQL emits NOTIFY. A lost
// notification therefore only delays execution; it never loses the command.
func (q *CommandQueue) Enqueue(ctx context.Context, requestID string, userID int64, sessionID *string, command string, payload json.RawMessage) (string, bool, error) {
	if userID <= 0 || requestID == "" || command == "" {
		return "", false, errors.New("perintah trading tidak valid")
	}
	if len(payload) == 0 {
		payload = json.RawMessage(`{}`)
	}
	id, err := newID()
	if err != nil {
		return "", false, err
	}
	var storedID string
	err = q.pool.QueryRow(ctx, `INSERT INTO trading_commands(id,request_id,user_id,session_id,command,payload)
		VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(request_id) DO UPDATE SET request_id=excluded.request_id
		RETURNING id::text`, id, requestID, userID, sessionID, command, payload).Scan(&storedID)
	return storedID, storedID != id, err
}

// Claim uses SKIP LOCKED so multiple workers may run without processing the
// same command. The command row is the durable arbitration point.
func (q *CommandQueue) Claim(ctx context.Context, workerID string) (Command, bool, error) {
	tx, err := q.pool.Begin(ctx)
	if err != nil {
		return Command{}, false, err
	}
	defer tx.Rollback(ctx)
	var command Command
	err = tx.QueryRow(ctx, `SELECT id::text,request_id::text,user_id,session_id::text,command,payload,created_at
		FROM trading_commands WHERE status='PENDING' ORDER BY created_at
		FOR UPDATE SKIP LOCKED LIMIT 1`).Scan(&command.ID, &command.RequestID, &command.UserID, &command.SessionID, &command.Command, &command.Payload, &command.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Command{}, false, nil
	}
	if err != nil {
		return Command{}, false, err
	}
	if _, err = tx.Exec(ctx, `UPDATE trading_commands SET status='PROCESSING',worker_id=$2,updated_at=now() WHERE id=$1`, command.ID, workerID); err != nil {
		return Command{}, false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return Command{}, false, err
	}
	return command, true, nil
}

func (q *CommandQueue) RequeueStale(ctx context.Context) error {
	_, err := q.pool.Exec(ctx, `UPDATE trading_commands SET status='PENDING',worker_id=NULL,updated_at=now()
		WHERE status='PROCESSING' AND updated_at < now()-interval '2 minutes'`)
	return err
}

func (q *CommandQueue) Finish(ctx context.Context, id string, processErr error) error {
	status, reason := "COMPLETED", ""
	if processErr != nil {
		status, reason = "FAILED", processErr.Error()
	}
	tag, err := q.pool.Exec(ctx, `UPDATE trading_commands SET status=$2,failure_reason=nullif($3,''),processed_at=now(),updated_at=now()
		WHERE id=$1 AND status='PROCESSING'`, id, status, reason)
	if err != nil {
		return err
	}
	if tag.RowsAffected() != 1 {
		return errors.New("status perintah trading sudah berubah")
	}
	return nil
}

func (q *CommandQueue) PublishEvent(ctx context.Context, userID int64, sessionID *string, eventType string, payload json.RawMessage) error {
	_, err := q.pool.Exec(ctx, `INSERT INTO trading_events(user_id,session_id,event_type,payload) VALUES($1,$2,$3,$4)`, userID, sessionID, eventType, payload)
	return err
}
