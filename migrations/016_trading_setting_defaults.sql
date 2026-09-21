ALTER TABLE user_trading_settings
    ALTER COLUMN chance_min SET DEFAULT 45,
    ALTER COLUMN chance_max SET DEFAULT 45,
    ALTER COLUMN delay_ms SET DEFAULT 500,
    ALTER COLUMN martingale_on_win SET DEFAULT 0,
    ALTER COLUMN martingale_on_loss SET DEFAULT 100,
    ALTER COLUMN reset_after_wins SET DEFAULT 1,
    ALTER COLUMN reset_after_losses SET DEFAULT 0;
