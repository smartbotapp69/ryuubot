CREATE TABLE management_fee_payouts (
    id uuid PRIMARY KEY,
    source_user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    coin varchar(12) NOT NULL,
    allocation varchar(12) NOT NULL CHECK (allocation IN ('HOLDING','KANGDEN')),
    recipient_username varchar(50) NOT NULL,
    amount numeric(38,8) NOT NULL CHECK (amount > 0),
    status varchar(20) NOT NULL CHECK (status IN ('PREPARED','SENT','COMPLETED','FAILED','REVIEW_REQUIRED')),
    provider_response jsonb,
    failure_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    sent_at timestamptz,
    completed_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX management_fee_payouts_one_unresolved
ON management_fee_payouts(source_user_id,coin,allocation)
WHERE status IN ('PREPARED','SENT','REVIEW_REQUIRED');

CREATE TABLE owner_cutoff_batches (
    id uuid PRIMARY KEY,
    business_date date NOT NULL,
    cutoff_slot time NOT NULL,
    coin varchar(12) NOT NULL,
    collector_balance numeric(38,8) NOT NULL,
    reserved_liability numeric(38,8) NOT NULL,
    distributable_amount numeric(38,8) NOT NULL,
    status varchar(20) NOT NULL CHECK (status IN ('PROCESSING','COMPLETED','REVIEW_REQUIRED')),
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(business_date,cutoff_slot,coin)
);

CREATE TABLE owner_cutoff_payouts (
    id uuid PRIMARY KEY,
    batch_id uuid NOT NULL REFERENCES owner_cutoff_batches(id) ON DELETE RESTRICT,
    allocation varchar(16) NOT NULL CHECK (allocation IN ('NANA','DENI','ARYA','OPERATIONAL')),
    recipient_username varchar(50) NOT NULL,
    percentage numeric(7,4) NOT NULL,
    amount numeric(38,8) NOT NULL CHECK (amount >= 0),
    status varchar(20) NOT NULL CHECK (status IN ('PREPARED','SENT','COMPLETED','REVIEW_REQUIRED')),
    provider_response jsonb,
    failure_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    sent_at timestamptz,
    completed_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(batch_id,allocation)
);
