-- Allow automatic cleanup of provider_bets when trading_sessions are deleted.
-- Previously ON DELETE RESTRICT caused the cleanup function to fail when bets
-- didn't match the filter criteria. CASCADE ensures the transient history
-- cleanup always succeeds.
ALTER TABLE provider_bets
    DROP CONSTRAINT IF EXISTS provider_bets_session_id_fkey,
    ADD CONSTRAINT provider_bets_session_id_fkey
        FOREIGN KEY (session_id) REFERENCES trading_sessions(id)
        ON DELETE CASCADE;
