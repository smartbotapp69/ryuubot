ALTER TABLE user_trading_settings
    ADD COLUMN IF NOT EXISTS profit_session numeric(38,8) NOT NULL DEFAULT 0
        CHECK (profit_session >= 0);
