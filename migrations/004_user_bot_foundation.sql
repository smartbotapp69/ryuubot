CREATE TABLE users (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username varchar(50) NOT NULL,
    email varchar(254) NOT NULL,
    password_hash text NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE','SUSPENDED','DELETED')),
    subscription_expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_username_lower_unique ON users (lower(username));
CREATE UNIQUE INDEX users_email_lower_unique ON users (lower(email));

CREATE TABLE user_sessions (
    token_hash bytea PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    csrf_token varchar(64) NOT NULL,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX user_sessions_user_expiry ON user_sessions(user_id,expires_at);

CREATE TABLE user_trading_settings (
    user_id bigint PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    coin varchar(12) NOT NULL DEFAULT 'TRX',
    base_bet numeric(38,8) NOT NULL DEFAULT 0.00000100 CHECK (base_bet > 0),
    chance_min numeric(8,4) NOT NULL DEFAULT 49 CHECK (chance_min > 0 AND chance_min < 100),
    chance_max numeric(8,4) NOT NULL DEFAULT 49 CHECK (chance_max > 0 AND chance_max < 100),
    delay_ms integer NOT NULL DEFAULT 1000 CHECK (delay_ms BETWEEN 250 AND 600000),
    martingale_on_win numeric(8,4) NOT NULL DEFAULT 0 CHECK (martingale_on_win >= 0),
    martingale_on_loss numeric(8,4) NOT NULL DEFAULT 0 CHECK (martingale_on_loss >= 0),
    reset_after_wins integer NOT NULL DEFAULT 0 CHECK (reset_after_wins >= 0),
    reset_after_losses integer NOT NULL DEFAULT 0 CHECK (reset_after_losses >= 0),
    boom_after_wins integer NOT NULL DEFAULT 0 CHECK (boom_after_wins >= 0),
    boom_win_amount numeric(38,8) NOT NULL DEFAULT 0 CHECK (boom_win_amount >= 0),
    boom_after_losses integer NOT NULL DEFAULT 0 CHECK (boom_after_losses >= 0),
    boom_loss_amount numeric(38,8) NOT NULL DEFAULT 0 CHECK (boom_loss_amount >= 0),
    take_profit numeric(38,8) NOT NULL DEFAULT 0 CHECK (take_profit >= 0),
    stop_loss numeric(38,8) NOT NULL DEFAULT 0 CHECK (stop_loss >= 0),
    balance_below numeric(38,8) NOT NULL DEFAULT 0 CHECK (balance_below >= 0),
    stop_on_win boolean NOT NULL DEFAULT false,
    maximum_bet numeric(38,8) NOT NULL DEFAULT 0 CHECK (maximum_bet >= 0),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE trading_sessions (
    id uuid PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    coin varchar(12) NOT NULL,
    status varchar(30) NOT NULL CHECK (status IN ('RUNNING','STOP_REQUESTED','RECONCILIATION_REQUIRED','COMPLETED')),
    settings_snapshot jsonb NOT NULL,
    rule_snapshot jsonb NOT NULL,
    opening_provider_balance numeric(38,8) NOT NULL CHECK (opening_provider_balance >= 0),
    visible_user_balance numeric(38,8) NOT NULL CHECK (visible_user_balance >= 0),
    current_bet numeric(38,8) NOT NULL CHECK (current_bet > 0),
    profit numeric(38,8) NOT NULL DEFAULT 0,
    wins integer NOT NULL DEFAULT 0 CHECK (wins >= 0),
    losses integer NOT NULL DEFAULT 0 CHECK (losses >= 0),
    last_result varchar(8) CHECK (last_result IN ('WIN','LOSS')),
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX trading_sessions_one_unresolved_user
    ON trading_sessions(user_id) WHERE status IN ('RUNNING','STOP_REQUESTED','RECONCILIATION_REQUIRED');

CREATE TABLE provider_bets (
    id uuid PRIMARY KEY,
    session_id uuid NOT NULL REFERENCES trading_sessions(id) ON DELETE RESTRICT,
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    coin varchar(12) NOT NULL,
    amount numeric(38,8) NOT NULL CHECK (amount > 0),
    chance numeric(8,4) NOT NULL CHECK (chance > 0 AND chance < 100),
    status varchar(30) NOT NULL CHECK (status IN ('PREPARED','SENT','COMPLETED','FAILED_CONFIRMED','RECONCILIATION_REQUIRED')),
    provider_reference text,
    provider_balance_before numeric(38,8),
    provider_balance_after numeric(38,8),
    gross_profit numeric(38,8),
    user_profit numeric(38,8),
    result varchar(8) CHECK (result IN ('WIN','LOSS')),
    prepared_at timestamptz NOT NULL DEFAULT now(),
    sent_at timestamptz,
    completed_at timestamptz,
    UNIQUE(provider_reference)
);
CREATE UNIQUE INDEX provider_bets_one_pending_session
    ON provider_bets(session_id) WHERE status IN ('PREPARED','SENT','RECONCILIATION_REQUIRED');
CREATE INDEX provider_bets_user_time ON provider_bets(user_id,prepared_at DESC);
