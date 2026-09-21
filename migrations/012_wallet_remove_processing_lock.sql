UPDATE wallet_operations
SET status='FAILED',
    failure_reason='Proses aplikasi terputus sebelum respons selesai',
    updated_at=now()
WHERE status='PROCESSING';

DROP INDEX IF EXISTS wallet_operations_one_processing_per_user;
