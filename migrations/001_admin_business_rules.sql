CREATE TABLE admin_users (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username varchar(50) NOT NULL,
    password_hash text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    failed_login_count integer NOT NULL DEFAULT 0 CHECK (failed_login_count >= 0),
    locked_until timestamptz,
    last_login_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX admin_users_username_lower_unique ON admin_users (lower(username));

CREATE TABLE admin_sessions (
    token_hash bytea PRIMARY KEY,
    admin_user_id bigint NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
    csrf_token varchar(64) NOT NULL,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_sessions_expiry ON admin_sessions (expires_at);

CREATE TABLE business_rule_versions (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    version integer NOT NULL UNIQUE CHECK (version > 0),
    status varchar(12) NOT NULL CHECK (status IN ('DRAFT', 'ACTIVE', 'ARCHIVED')),

    user_win_percent numeric(7,4) NOT NULL CHECK (user_win_percent >= 0 AND user_win_percent <= 100),
    holding_win_percent numeric(7,4) NOT NULL CHECK (holding_win_percent >= 0 AND holding_win_percent <= 100),
    kangden_win_percent numeric(7,4) NOT NULL CHECK (kangden_win_percent >= 0 AND kangden_win_percent <= 100),
    fee_exempt_username varchar(50) NOT NULL,

    referral_level_1_percent numeric(7,4) NOT NULL CHECK (referral_level_1_percent >= 0),
    referral_level_2_percent numeric(7,4) NOT NULL CHECK (referral_level_2_percent >= 0),
    referral_level_3_percent numeric(7,4) NOT NULL CHECK (referral_level_3_percent >= 0),

    subscription_coin varchar(12) NOT NULL,
    subscription_price numeric(38,8) NOT NULL CHECK (subscription_price > 0),
    subscription_upline_reward numeric(38,8) NOT NULL CHECK (subscription_upline_reward >= 0),
    subscription_management_amount numeric(38,8) NOT NULL CHECK (subscription_management_amount >= 0),
    subscription_trial_days integer NOT NULL CHECK (subscription_trial_days >= 0),

    owner_nana_percent numeric(7,4) NOT NULL CHECK (owner_nana_percent >= 0),
    owner_deni_percent numeric(7,4) NOT NULL CHECK (owner_deni_percent >= 0),
    owner_arya_percent numeric(7,4) NOT NULL CHECK (owner_arya_percent >= 0),
    operational_percent numeric(7,4) NOT NULL CHECK (operational_percent >= 0),
    owner_cutoff_timezone varchar(64) NOT NULL,
    owner_cutoff_times time[] NOT NULL,

    created_by bigint NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
    activated_by bigint REFERENCES admin_users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    activated_at timestamptz,

    CONSTRAINT win_allocation_exactly_100 CHECK (
        user_win_percent + holding_win_percent + kangden_win_percent = 100
    ),
    CONSTRAINT referral_within_holding_allocation CHECK (
        referral_level_1_percent + referral_level_2_percent + referral_level_3_percent <= holding_win_percent
    ),
    CONSTRAINT subscription_allocation_matches_price CHECK (
        subscription_upline_reward + subscription_management_amount = subscription_price
    ),
    CONSTRAINT owner_allocation_exactly_100 CHECK (
        owner_nana_percent + owner_deni_percent + owner_arya_percent + operational_percent = 100
    ),
    CONSTRAINT active_version_has_activation CHECK (
        status <> 'ACTIVE' OR (activated_by IS NOT NULL AND activated_at IS NOT NULL)
    )
);
CREATE UNIQUE INDEX business_rule_versions_one_active
    ON business_rule_versions ((status)) WHERE status = 'ACTIVE';

CREATE TABLE coin_rule_versions (
    business_rule_version_id bigint NOT NULL REFERENCES business_rule_versions(id) ON DELETE CASCADE,
    coin varchar(12) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    decimals smallint NOT NULL CHECK (decimals BETWEEN 0 AND 18),
    minimum_bet numeric(38,18) NOT NULL CHECK (minimum_bet > 0),
    minimum_withdrawal numeric(38,18) NOT NULL CHECK (minimum_withdrawal > 0),
    minimum_bonus_claim numeric(38,18) NOT NULL CHECK (minimum_bonus_claim > 0),
    PRIMARY KEY (business_rule_version_id, coin)
);

CREATE TABLE admin_business_rule_audit (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    admin_user_id bigint NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
    business_rule_version_id bigint NOT NULL REFERENCES business_rule_versions(id) ON DELETE RESTRICT,
    action varchar(20) NOT NULL CHECK (action = 'SAVE'),
    before_data jsonb,
    after_data jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_business_rule_audit_version_time
    ON admin_business_rule_audit (business_rule_version_id, created_at DESC);
