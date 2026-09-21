ALTER TABLE user_trading_settings
    ALTER COLUMN chance_min TYPE integer USING chance_min::integer,
    ALTER COLUMN chance_max TYPE integer USING chance_max::integer,
    ALTER COLUMN martingale_on_win TYPE integer USING martingale_on_win::integer,
    ALTER COLUMN martingale_on_loss TYPE integer USING martingale_on_loss::integer;

-- Stop Win is a temporary command for one active session, not a persistent
-- user strategy setting. Clear values written by the previous implementation.
UPDATE user_trading_settings SET stop_on_win = false WHERE stop_on_win = true;
