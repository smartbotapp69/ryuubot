CREATE TABLE trading_fee_balances (
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    coin varchar(12) NOT NULL,
    holding_pending numeric(38,8) NOT NULL DEFAULT 0 CHECK (holding_pending >= 0),
    kangden_pending numeric(38,8) NOT NULL DEFAULT 0 CHECK (kangden_pending >= 0),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(user_id,coin)
);

INSERT INTO trading_fee_balances(user_id,coin,holding_pending,kangden_pending)
SELECT user_id,coin,
       coalesce(sum(amount) FILTER (WHERE obligation_type='HOLDING'),0),
       coalesce(sum(amount) FILTER (WHERE obligation_type='KANGDEN'),0)
FROM trading_fee_obligations
WHERE status IN ('PENDING','PROCESSING','FAILED')
GROUP BY user_id,coin
ON CONFLICT(user_id,coin) DO UPDATE SET
    holding_pending=excluded.holding_pending,
    kangden_pending=excluded.kangden_pending,
    updated_at=now();

DROP TABLE trading_fee_obligations;

CREATE OR REPLACE FUNCTION cleanup_ryubot_transient_history() RETURNS TABLE(
    trading_events_deleted bigint,
    provider_bets_deleted bigint,
    trading_commands_deleted bigint,
    trading_sessions_deleted bigint,
    bonus_events_deleted bigint
)
LANGUAGE plpgsql AS $$
DECLARE
    cutoff timestamptz := now() - interval '1 day';
BEGIN
    DELETE FROM trading_events WHERE created_at < cutoff;
    GET DIAGNOSTICS trading_events_deleted = ROW_COUNT;

    DELETE FROM provider_bets
    WHERE prepared_at < cutoff
      AND status IN ('COMPLETED','FAILED_CONFIRMED');
    GET DIAGNOSTICS provider_bets_deleted = ROW_COUNT;

    DELETE FROM trading_commands
    WHERE created_at < cutoff AND status IN ('COMPLETED','FAILED');
    GET DIAGNOSTICS trading_commands_deleted = ROW_COUNT;

    DELETE FROM trading_sessions
    WHERE completed_at < cutoff AND status='COMPLETED';
    GET DIAGNOSTICS trading_sessions_deleted = ROW_COUNT;

    DELETE FROM referral_bonus_events WHERE occurred_at < cutoff;
    GET DIAGNOSTICS bonus_events_deleted = ROW_COUNT;

    RETURN NEXT;
END;
$$;
