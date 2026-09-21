ALTER TABLE trading_sessions
    ADD COLUMN IF NOT EXISTS next_override numeric(38,8) CHECK (next_override IS NULL OR next_override > 0),
    ADD COLUMN IF NOT EXISTS reset_after_pending boolean NOT NULL DEFAULT false;
