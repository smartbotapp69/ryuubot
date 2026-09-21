package trading

import (
	"context"
	"encoding/json"
	"strconv"
	"sync"
	"time"
)

type LiveEvent struct {
	ID        int64           `json:"id"`
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload"`
	CreatedAt time.Time       `json:"created_at"`
}

type eventSubscribers struct {
	mu     sync.RWMutex
	byUser map[int64]map[chan LiveEvent]struct{}
}

func newEventSubscribers() *eventSubscribers {
	return &eventSubscribers{byUser: make(map[int64]map[chan LiveEvent]struct{})}
}

func (s *eventSubscribers) subscribe(userID int64) (<-chan LiveEvent, func()) {
	channel := make(chan LiveEvent, 32)
	s.mu.Lock()
	if s.byUser[userID] == nil {
		s.byUser[userID] = make(map[chan LiveEvent]struct{})
	}
	s.byUser[userID][channel] = struct{}{}
	s.mu.Unlock()
	return channel, func() {
		s.mu.Lock()
		if listeners := s.byUser[userID]; listeners != nil {
			delete(listeners, channel)
			if len(listeners) == 0 {
				delete(s.byUser, userID)
			}
		}
		s.mu.Unlock()
	}
}

func (s *eventSubscribers) publish(userID int64, event LiveEvent) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for channel := range s.byUser[userID] {
		select {
		case channel <- event:
		default:
		}
	}
}

func (e *Engine) Subscribe(userID int64) (<-chan LiveEvent, func()) {
	return e.events.subscribe(userID)
}

func (e *Engine) EventsAfter(ctx context.Context, userID, afterID int64) ([]LiveEvent, error) {
	rows, err := e.pool.Query(ctx, `SELECT id,event_type,payload,created_at FROM trading_events WHERE user_id=$1 AND id>$2 ORDER BY id LIMIT 200`, userID, afterID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]LiveEvent, 0)
	for rows.Next() {
		var item LiveEvent
		if err = rows.Scan(&item.ID, &item.Type, &item.Payload, &item.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (e *Engine) ListenEvents(ctx context.Context) {
	for ctx.Err() == nil {
		connection, err := e.pool.Acquire(ctx)
		if err != nil {
			e.logger.Error("acquire trading event listener failed", "error", err)
			waitContext(ctx, time.Second)
			continue
		}
		_, err = connection.Exec(ctx, `LISTEN ryubot_trading_events`)
		if err != nil {
			connection.Release()
			e.logger.Error("listen trading events failed", "error", err)
			waitContext(ctx, time.Second)
			continue
		}
		for ctx.Err() == nil {
			notification, waitErr := connection.Conn().WaitForNotification(ctx)
			if waitErr != nil {
				break
			}
			id, parseErr := strconv.ParseInt(notification.Payload, 10, 64)
			if parseErr != nil {
				continue
			}
			var userID int64
			var event LiveEvent
			queryErr := e.pool.QueryRow(ctx, `SELECT id,user_id,event_type,payload,created_at FROM trading_events WHERE id=$1`, id).Scan(&event.ID, &userID, &event.Type, &event.Payload, &event.CreatedAt)
			if queryErr == nil {
				e.events.publish(userID, event)
			}
		}
		connection.Release()
		if ctx.Err() == nil {
			waitContext(ctx, time.Second)
		}
	}
}

func waitContext(ctx context.Context, duration time.Duration) {
	select {
	case <-time.After(duration):
	case <-ctx.Done():
	}
}
