-- Sesi ambigu yang sudah ada sebelum mekanisme trading final berasal dari
-- pengujian lokal. Tutup satu kali agar data trial tidak mengunci pengguna.
-- Rekonsiliasi yang terbentuk setelah migrasi ini tetap dilindungi normal.
UPDATE provider_bets b
SET status = 'FAILED_CONFIRMED',
    response_payload = coalesce(b.response_payload, '{}'::jsonb) ||
        '{"reason":"PRE_PRODUCTION_TRIAL_DISCARDED"}'::jsonb,
    completed_at = coalesce(b.completed_at, now()),
    updated_at = now()
FROM trading_sessions s
WHERE b.session_id = s.id
  AND s.status = 'RECONCILIATION_REQUIRED'
  AND b.status IN ('PREPARED','SENT','RECONCILIATION_REQUIRED');

UPDATE trading_sessions
SET status = 'COMPLETED',
    stop_reason = 'Data trial sebelum produksi ditutup',
    completed_at = coalesce(completed_at, now()),
    worker_id = NULL,
    lease_expires_at = NULL,
    updated_at = now()
WHERE status = 'RECONCILIATION_REQUIRED';
