CREATE OR REPLACE FUNCTION notify_ryubot_trading_event() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_notify('ryubot_trading_events', NEW.id::text);
    RETURN NEW;
END;
$$;
