CREATE TABLE trading_commands (
    id uuid PRIMARY KEY,
    request_id uuid NOT NULL UNIQUE,
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    session_id uuid REFERENCES trading_sessions(id) ON DELETE RESTRICT,
    command varchar(24) NOT NULL CHECK (command IN ('START','STOP','UPDATE_CONFIG','OVERRIDE','RESET','STOP_ON_WIN')),
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(16) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PROCESSING','COMPLETED','FAILED')),
    failure_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX trading_commands_pending_idx
    ON trading_commands(created_at)
    WHERE status='PENDING';

CREATE TABLE trading_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    session_id uuid REFERENCES trading_sessions(id) ON DELETE RESTRICT,
    event_type varchar(32) NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX trading_events_user_id_idx ON trading_events(user_id,id DESC);

CREATE OR REPLACE FUNCTION notify_ryubot_trading_command() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_notify('ryubot_trading_commands', NEW.id::text);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trading_commands_notify
AFTER INSERT ON trading_commands
FOR EACH ROW EXECUTE FUNCTION notify_ryubot_trading_command();

CREATE OR REPLACE FUNCTION notify_ryubot_trading_event() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_notify('ryubot_trading_events', NEW.user_id::text);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trading_events_notify
AFTER INSERT ON trading_events
FOR EACH ROW EXECUTE FUNCTION notify_ryubot_trading_event();
