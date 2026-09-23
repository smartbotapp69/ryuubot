-- Cleanup ryubot_go 2026-09-23: sisakan 6 akun (749,751,767,781,863,1051) + pengaturan sistem.
-- Semua dalam satu transaksi: jika ada error, rollback total.
BEGIN;

-- Anak user yang dibuang (RESTRICT & CASCADE, dieksplisitkan agar urutan aman)
DELETE FROM user_referrals
WHERE user_id NOT IN (749,751,767,781,863,1051)
   OR referrer_user_id NOT IN (749,751,767,781,863,1051);

DELETE FROM management_fee_payouts WHERE source_user_id NOT IN (749,751,767,781,863,1051);
DELETE FROM admin_user_actions     WHERE user_id             NOT IN (749,751,767,781,863,1051);
DELETE FROM referral_bonus_events  WHERE user_id             NOT IN (749,751,767,781,863,1051);
DELETE FROM referral_bonus_balances WHERE user_id            NOT IN (749,751,767,781,863,1051);
DELETE FROM wallet_operations      WHERE user_id             NOT IN (749,751,767,781,863,1051);
DELETE FROM trading_fee_balances   WHERE user_id             NOT IN (749,751,767,781,863,1051);
DELETE FROM trading_events         WHERE user_id             NOT IN (749,751,767,781,863,1051);
DELETE FROM trading_commands       WHERE user_id             NOT IN (749,751,767,781,863,1051);
DELETE FROM provider_bets          WHERE user_id             NOT IN (749,751,767,781,863,1051);
DELETE FROM trading_sessions       WHERE user_id             NOT IN (749,751,767,781,863,1051);
DELETE FROM user_sessions          WHERE user_id             NOT IN (749,751,767,781,863,1051);
DELETE FROM user_trading_settings  WHERE user_id             NOT IN (749,751,767,781,863,1051);
DELETE FROM user_pasino_accounts   WHERE user_id             NOT IN (749,751,767,781,863,1051);

-- User itu sendiri
DELETE FROM users WHERE id NOT IN (749,751,767,781,863,1051);

COMMIT;