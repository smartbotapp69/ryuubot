ALTER TABLE trading_sessions
    ADD COLUMN IF NOT EXISTS stop_reason text;

ALTER TABLE provider_bets
    ADD COLUMN IF NOT EXISTS request_payload jsonb,
    ADD COLUMN IF NOT EXISTS response_payload jsonb,
    ADD COLUMN IF NOT EXISTS holding_amount numeric(38,8),
    ADD COLUMN IF NOT EXISTS kangden_amount numeric(38,8),
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
