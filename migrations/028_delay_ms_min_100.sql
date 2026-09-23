-- Allow trading delays as low as 100ms. The previous minimum of 250ms
-- (defined in 004_user_bot_foundation.sql) prevented the UI's 100ms+ delays.
-- The API validation and engine floor were updated to match.
ALTER TABLE user_trading_settings
    DROP CONSTRAINT IF EXISTS user_trading_settings_delay_ms_check,
    ADD CONSTRAINT user_trading_settings_delay_ms_check
        CHECK (delay_ms BETWEEN 100 AND 600000);