CREATE TABLE wallet_operations (
    request_id uuid PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    operation varchar(12) NOT NULL CHECK (operation IN ('WITHDRAW','TRANSFER')),
    coin varchar(12) NOT NULL,
    amount numeric(38,8) NOT NULL CHECK (amount > 0),
    destination text NOT NULL CHECK (length(destination) > 0),
    status varchar(24) NOT NULL CHECK (status IN ('PROCESSING','COMPLETED','FAILED')),
    provider_response jsonb,
    failure_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);
CREATE INDEX wallet_operations_user_created_idx ON wallet_operations(user_id,created_at DESC);
