#!/usr/bin/env bash
#
# trace-user.sh — lacak pergerakan saldo & bonus seorang user di DB ryubot_go.
#
# Menjawab pertanyaan seperti: "smartrich88 bilang saldo BTT-nya 1jt, kemana?"
# Jalankan di server yang punya database ryubot_go + psql (mis. VPS).
#
# Pemakaian:
#   bash trace-user.sh smartrich88
#   DATABASE_URL=postgresql://user:pass@127.0.0.1:5432/ryubot_go bash trace-user.sh smartrich88
#
# Catatan penting soal sumber jejak:
#   - Tabel referral_bonus_* = akun BONUS referral. CLAIM_REVERSAL = bonus yang
#     dipindah ke kangden69 oleh subcommand bonus-move (terekam, jumlah pasti).
#   - Konsolidasi WALLET ke kangden69 (subcommand wallet-move) TIDAK menulis ke
#     DB — jejaknya hanya ada di Pasino. Untuk itu lihat bagian "saldo live".
#
set -euo pipefail

TARGET="${1:-smartrich88}"
DB_URL="${DATABASE_URL:-}"
if [ -z "$DB_URL" ] && [ -f .env ]; then
  DB_URL="$(awk -F= '/^RYUBOT_DATABASE_URL=/{print $2}' .env | tr -d '\r"\047')"
fi
if [ -z "$DB_URL" ]; then
  echo "DATABASE_URL tidak ditemukan — set env DATABASE_URL atau sediakan .env." >&2
  exit 1
fi

q() { psql "$DB_URL" -X -A -F "|" -P pager=off -v ON_ERROR_STOP=1 -c "$1"; }

echo "=== TARGET: $TARGET ==="

echo; echo "--- 1) Status akun ---"
q "SELECT u.id, u.username, u.status, u.created_at FROM users u WHERE u.username='$TARGET'"

echo; echo "--- 2) Saldo bonus referral (available = sisa yang belum terpakai) ---"
q "SELECT r.coin, r.available_amount, r.claimed_amount, r.updated_at
     FROM referral_bonus_balances r JOIN users u ON u.id=r.user_id
    WHERE u.username='$TARGET' ORDER BY r.coin"

echo; echo "--- 3) Riwayat bonus referral (akrual / klaim / reversal) ---"
q "SELECT e.coin, e.amount, e.event_type, e.source_external_id, e.occurred_at
     FROM referral_bonus_events e JOIN users u ON u.id=e.user_id
    WHERE u.username='$TARGET'
    ORDER BY e.coin, e.occurred_at"

echo; echo "--- 4) Ringkasan bonus per coin (kemana yang terekam) ---"
q "SELECT e.coin,
        sum(e.amount) FILTER (WHERE e.event_type='TRADING_ACCRUAL') AS bonus_masuk,
        sum(e.amount) FILTER (WHERE e.event_type='CLAIM_COMPLETED') AS bonus_diklaim_user,
        sum(e.amount) FILTER (WHERE e.event_type='CLAIM_REVERSAL')  AS bonus_dipindah_kangden69,
        sum(e.amount)                                                AS total_terekam
     FROM referral_bonus_events e JOIN users u ON u.id=e.user_id
    WHERE u.username='$TARGET'
    GROUP BY e.coin ORDER BY e.coin"

echo; echo "--- 5) Transfer/Withdraw lewat aplikasi (wallet_operations) ---"
q "SELECT o.operation, o.coin, o.amount, o.destination, o.status, o.created_at
     FROM wallet_operations o JOIN users u ON u.id=o.user_id
    WHERE u.username='$TARGET'
    ORDER BY o.created_at"

echo; echo "--- 5a) Riwayat trading: ringkasan bet per coin ---"
q "SELECT p.coin,
        count(*)                                                        AS n_bet,
        sum(p.amount)                                                   AS total_staked,
        sum(p.user_profit)                                              AS net_user_profit,
        sum(p.gross_profit)                                             AS gross_profit,
        sum(coalesce(p.kangden_amount,0))                               AS fee_kangden,
        count(*) FILTER (WHERE p.result='WIN')                          AS win,
        count(*) FILTER (WHERE p.result='LOSS')                         AS loss,
        count(*) FILTER (WHERE p.status='COMPLETED')                    AS completed,
        min(p.prepared_at)                                              AS sejak,
        max(p.prepared_at)                                              AS sampai
     FROM provider_bets p JOIN users u ON u.id=p.user_id
    WHERE u.username='$TARGET'
    GROUP BY p.coin ORDER BY p.coin"

echo; echo "--- 5b) Riwayat trading: 20 bet terakhir ---"
q "SELECT to_char(p.prepared_at,'YYYY-MM-DD HH24:MI') AS waktu, p.coin, p.amount, p.chance,
        p.result, p.user_profit, p.kangden_amount, p.status
     FROM provider_bets p JOIN users u ON u.id=p.user_id
    WHERE u.username='$TARGET'
    ORDER BY p.prepared_at DESC LIMIT 20"

echo; echo "--- 5c) Riwayat trading: sesi (per coin & status) ---"
q "SELECT s.coin, s.status, count(*) AS n_sesi, sum(s.profit) AS profit,
        sum(s.wins) AS win, sum(s.losses) AS loss,
        min(s.started_at) AS sejak, max(s.completed_at) AS selesai
     FROM trading_sessions s JOIN users u ON u.id=s.user_id
    WHERE u.username='$TARGET'
    GROUP BY s.coin, s.status ORDER BY s.coin, s.status"

echo; echo "--- 5d) Event trading per tipe ---"
q "SELECT e.event_type, count(*) AS n
     FROM trading_events e JOIN users u ON u.id=e.user_id
    WHERE u.username='$TARGET'
    GROUP BY e.event_type ORDER BY 2 DESC"

echo; echo "--- 6) Bonus-move ke kangden69 dari SEMUA user (crosscheck) ---"
q "SELECT u.username, e.coin, sum(e.amount) AS ke_kangden69
     FROM referral_bonus_events e JOIN users u ON u.id=e.user_id
    WHERE e.event_type='CLAIM_REVERSAL'
    GROUP BY u.username, e.coin ORDER BY u.username, e.coin"

echo; echo "--- 7) Kemana kangden69 mengirim keluar (COMPLETED) ---"
q "SELECT o.destination, o.coin, sum(o.amount) AS total, count(*) AS n
     FROM wallet_operations o JOIN users u ON u.id=o.user_id
    WHERE u.username='kangden69' AND o.status='COMPLETED'
    GROUP BY o.destination, o.coin ORDER BY o.destination, o.coin"

echo; echo "--- 8) Saldo live Pasino (jika binary tersedia di server) ---"
if [ -x bin/ryubot ]; then
  bin/ryubot wallet-balances --username "$TARGET" --workers 1 || echo "(gagal cek saldo live)"
else
  echo "(bin/ryubot tidak ditemukan — lewati, jalankan manual: bin/ryubot wallet-balances --username $TARGET)"
fi

echo
echo "Catatan: CLAIM_REVERSAL = bonus dipindah ke kangden69 via bonus-move (terekam)."
echo "Konsolidasi WALLET ke kangden69 (wallet-move) TIDAK tercatat di DB."