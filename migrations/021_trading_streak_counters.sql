ALTER TABLE trading_sessions
    ADD COLUMN max_win_streak integer NOT NULL DEFAULT 0 CHECK (max_win_streak >= 0),
    ADD COLUMN max_loss_streak integer NOT NULL DEFAULT 0 CHECK (max_loss_streak >= 0);

UPDATE trading_sessions
SET max_win_streak = CASE WHEN last_result='WIN' THEN streak ELSE 0 END,
    max_loss_streak = CASE WHEN last_result='LOSS' THEN streak ELSE 0 END;
