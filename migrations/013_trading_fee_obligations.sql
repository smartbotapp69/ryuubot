CREATE TABLE trading_fee_obligations (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    provider_bet_id uuid NOT NULL REFERENCES provider_bets(id) ON DELETE RESTRICT,
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    coin varchar(12) NOT NULL,
    obligation_type varchar(16) NOT NULL CHECK (obligation_type IN ('HOLDING','KANGDEN')),
    amount numeric(38,8) NOT NULL CHECK (amount > 0),
    status varchar(16) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PROCESSING','PAID','FAILED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    paid_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(provider_bet_id, obligation_type)
);

CREATE INDEX trading_fee_obligations_user_coin_pending
    ON trading_fee_obligations(user_id,coin)
    WHERE status IN ('PENDING','PROCESSING','FAILED');
