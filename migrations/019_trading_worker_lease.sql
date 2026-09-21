ALTER TABLE trading_sessions
    ADD COLUMN worker_id text,
    ADD COLUMN lease_expires_at timestamptz;

CREATE INDEX trading_sessions_recoverable_idx
    ON trading_sessions(lease_expires_at)
    WHERE status IN ('RUNNING','STOP_REQUESTED');

ALTER TABLE trading_commands
    ADD COLUMN worker_id text;

CREATE INDEX trading_commands_processing_idx
    ON trading_commands(updated_at)
    WHERE status='PROCESSING';
