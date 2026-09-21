ALTER TABLE trading_sessions
    ADD COLUMN IF NOT EXISTS streak integer NOT NULL DEFAULT 0 CHECK (streak >= 0),
    ADD COLUMN IF NOT EXISTS profit_cycle numeric(38,8) NOT NULL DEFAULT 0;
