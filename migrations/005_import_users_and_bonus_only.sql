-- Migration policy: only user identity/password hash and referral bonus are
-- imported from the Node system. Provider wallet balances are never imported.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS legacy_user_id bigint;
CREATE UNIQUE INDEX IF NOT EXISTS users_legacy_user_id_unique
    ON users(legacy_user_id) WHERE legacy_user_id IS NOT NULL;

CREATE TABLE referral_bonus_balances (
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    coin varchar(12) NOT NULL,
    available_amount numeric(38,8) NOT NULL DEFAULT 0 CHECK (available_amount >= 0),
    claimed_amount numeric(38,8) NOT NULL DEFAULT 0 CHECK (claimed_amount >= 0),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(user_id,coin)
);

CREATE TABLE referral_bonus_events (
    id uuid PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    coin varchar(12) NOT NULL,
    amount numeric(38,8) NOT NULL CHECK (amount <> 0),
    event_type varchar(30) NOT NULL CHECK (event_type IN ('IMPORT_OPENING','TRADING_ACCRUAL','CLAIM_COMPLETED','CLAIM_REVERSAL')),
    source_external_id text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(event_type,source_external_id)
);
CREATE INDEX referral_bonus_events_user_time
    ON referral_bonus_events(user_id,occurred_at DESC);

CREATE TABLE import_runs (
    id uuid PRIMARY KEY,
    source_name varchar(50) NOT NULL,
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    status varchar(20) NOT NULL CHECK (status IN ('RUNNING','COMPLETED','FAILED')),
    users_imported integer NOT NULL DEFAULT 0,
    bonus_rows_imported integer NOT NULL DEFAULT 0,
    error_message text
);
