ALTER TABLE users
    ADD COLUMN IF NOT EXISTS subscription_trial_ends_at timestamptz;

CREATE TABLE IF NOT EXISTS user_referrals (
    user_id bigint PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    referrer_user_id bigint REFERENCES users(id) ON DELETE RESTRICT,
    provider_referrer varchar(30) NOT NULL DEFAULT '277064',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_referrals_not_self CHECK (referrer_user_id IS NULL OR user_id <> referrer_user_id)
);
CREATE INDEX IF NOT EXISTS user_referrals_referrer_idx ON user_referrals(referrer_user_id);
