# Ryubot — Tugas yang Belum Selesai

## 1. Migrasi Database — ✅ SELESAI
- **File**: `migrations/027_provider_bets_cascade.sql`
- **Status**: ✅ Migrasi diterapkan via `bin\ryubot.exe migrate`
- **FK `provider_bets_session_id_fkey`**: Sudah `ON DELETE CASCADE`

## 2. UI — Claim Button Text
- **Status**: ✅ HTML sudah menggunakan "Klaim" (Indonesian), JS `loadBonus` mengubah text menjadi "Belum cukup" saat `available < minimum_claim`
- **Button HTML**: `<button id="claimBonusBtn" disabled>Klaim</button>`
- **JS Logic**: `claimBtn.textContent=canClaim?'Klaim':'Belum cukup'`

## 3. Code Splitting — ✅ SELESAI
- `assets/index.html`, `assets/style.css`, `assets/app.js` — diekstrak dari template inline
- `assets_embed.go` — `//go:embed` directives
- `ui.go` — menggunakan `embed.FS` untuk template
- `http.go` — `Register` method dan utility functions
- `auth.go` — `login`, `register`, `logout`, `session`, `optionalSession`
- `trading.go` — `getTradingSettings`, `saveTradingSettings`, `tradingStatus`, dll.
- `wallet.go` — `balance`, `depositInfo`, `marketPrice`, `withdraw`, `transfer`, dll.
- `referral.go` — `claimReferralBonus`, `referralBonus`

## 4. UI — Balance Tidak Real-Time Saat Ganti Coin — ✅ SELESAI
- **Masalah**: Saat berganti coin di menu Trading maupun Wallet/Finansial, balance tidak update secara real-time. Kadang terhambat atau tidak muncul.
- **Penyebab Utama**: WebSocket Pasino putus, HTTP timeout, `ActiveTradingBalance` hanya saat trading aktif, dan `provider.Balance()` gagal saat socket closed.
- **Solusi (sudah diterapkan)**:
  - `BalanceForDisplay` di `internal/pasino/client.go` — live balance dengan fallback ke last-known (`stale=true`) selama socket dipulihkan.
  - `http.go` `balance` handler + `trading.go` `realtime` memakai `BalanceForDisplay`; status `source` (`pasino_live_net` / `pasino_last_known` / `settlement_ledger`) dikirim ke UI.
  - Frontend `app.js`: `loadWalletBalance` (HTTP) + `loadBalance`/`requestRealtimeBalance` (WS) dengan loading state, `balance_retry` reconnect 700ms, dan `toast` auto-retry saat "Saldo belum tersedia".
- **Status**: ✅ Selesai

## 5. Pasino WebSocket Reconnection — ✅ SELESAI
- **Masalah**: WebSocket connection ke Pasino bisa putus dan tidak reconnect otomatis
- **Solusi (sudah diterapkan di `internal/pasino/client.go`)**:
  - `dropSocket` → hapus socket + `scheduleReconnect`
  - `scheduleReconnect` + `reconnectLoop` — retry periodik dengan exponential backoff (1s → 30s, maks 8 attempt), berhenti saat socket live / `ErrUnauthorized` / shutdown
  - `readSocket` (satu pembaca per socket), `keepSocketAlive` ping tiap 20 detik
  - `connectLocks[userID]` mencegah dial ganda serentak; `stopOnce` mencegah double-close
- **Status**: ✅ Selesai

## 6. Context Deadline pada Balance Fetch — ✅ SELESAI
- **Masalah**: `h.provider.Balance()` timeout dengan `context deadline exceeded` saat Pasino server lambat
- **Solusi (sudah diterapkan)`:
  - `readBalance` — retry sekali (300ms) pada socket baru bila gagal (kecuali ctx cancel / unauthorized)
  - `balanceCache` 5 detik + `balanceFlight` dedup untuk request berbarengan
  - Context timeout 5 detik didefinisikan konsisten; abort HTTP tidak menutup socket bersama
- **Status**: ✅ Selesai

---

## Checklist Penyelesaian

- [x] Jalankan `bin\ryubot.exe migrate` untuk apply migration 027
- [x] Perbaiki claim button text di HTML + JS
- [x] Split monolithic UI/code menjadi file-file terpisah
- [x] Fix `SettleImmediate` + `AccrueSessionFees` (defer fee transfer)
- [x] Fixed `time.LoadLocation` panic di `management/service.go`
- [x] Added `PASINO_REFERRER` config
- [x] Fixed `RegisterAndLogin` missing `api_key` in payload
- [x] Removed "Pasino menolak permintaan" prefix from error
- [x] Changed `internal_error` to show actual error message
- [x] Rekonstruksi handler `trading.go`/`wallet.go`/`referral.go` (bukan stub lagi)
- [x] Fix typo import `nhoeyr.io/websocket` di `trading.go`
- [x] Perbaiki WebSocket reconnection di `pasino/client.go`
- [x] Tambahkan fallback balance saat socket putus (`BalanceForDisplay` + last-known)
- [x] Tambahkan retry/backoff untuk balance fetch yang timeout
- [x] Test semua perubahan dengan `go test ./internal/...`
- [x] Rebuild binary dan verify

## Catatan Perubahan yang Sudah Selesai

| Tanggal | Perubahan | Status |
|---------|-----------|--------|
| 2026-09-23 | Fixed `SettleImmediate` + `AccrueSessionFees` (defer fee transfer) | ✅ |
| 2026-09-23 | Fixed `time.LoadLocation` panic di `management/service.go` | ✅ |
| 2026-09-23 | Added `PASINO_REFERRER` config | ✅ |
| 2026-09-23 | Fixed `RegisterAndLogin` missing `api_key` in payload | ✅ |
| 2026-09-23 | Removed "Pasino menolak permintaan" prefix from error | ✅ |
| 2026-09-23 | Changed `internal_error` to show actual error message | ✅ |
| 2026-09-23 | Created migration 027 (`ON DELETE CASCADE`) | ✅ Applied |
| 2026-09-23 | Code split: extracted assets, split http.go into handler files | ✅ |
| 2026-09-23 | Rekonstruksi `trading.go`/`wallet.go`/`referral.go` (tidak lagi stub) | ✅ |
| 2026-09-23 | `BalanceForDisplay` + last-known fallback di `pasino/client.go` | ✅ |
| 2026-09-23 | WebSocket reconnection (`scheduleReconnect`/`reconnectLoop`/ping) | ✅ |
| 2026-09-23 | Retry/backoff + cache 5s + flight dedup pada balance fetch | ✅ |
| 2026-09-23 | Frontend: loading state, auto-retry, balance_retry reconnect | ✅ |
| 2026-09-23 | Fix typo import `nhoeyr.io/websocket` di `internal/user/trading.go` | ✅ |
| 2026-09-23 | Build dan semua test pass (`go build` + `go test ./internal/...`) | ✅ |
| 2026-09-23 | Rebuilt binary `bin/ryubot.exe` | ✅ |

| 2026-09-23 | Fix socket handler: onmessage/onclose dipasang langsung, update pakai tradeCoin/walletCoin dinamis | Done. |
| 2026-09-23 | Refresh app default kembali ke coin TRX (kecuali sesi RUNNING) | Done. |
| 2026-09-23 | Header trading kompak (appbar 52px, coin button 28x27) | Done. |
| 2026-09-23 | Bottom nav diperkecil (58px, icon 18px) | Done. |
| 2026-09-23 | Card wallet & referral lebih kecil (padding 12px, komponen lebih ramping) | Done. |
| 2026-09-23 | Fix SQLSTATE 23514: validasi delay_ms server disamakan dengan constraint DB 250-600000; input #tradeDelay dibatasi min/max | Done. |
| 2026-09-23 | Fix mojibake encoding app.js (30× `—`, `÷`, `·`) + index.html (8× `—`) — penyebab "huruf gak jelas" di card saldo | Done. |
| 2026-09-23 | Balance trading tampil instan saat idle: loadTradeConsole fetch `wallet/balance` (fast path) + placeholder `Memuat...`, WS tetap untuk live/retry | Done. |
| 2026-09-23 | Button claim referral selalu "Klaim", disabled saat bonus < minimal claim (dihapus teks "Belum cukup") | Done. |
| 2026-09-23 | Fix delay trading: clamp 1s di engine.go diganti floor 250ms (sesuai batas API/DB) — delay 300ms kini berjalan ~300ms | Done. |
| 2026-09-23 | Coin trading dipertahankan setelah STOP/refresh via lastTradedCoin + localStorage (`ryu_last_coin`), direset saat logout | Done. |
| 2026-09-23 | Minimum delay 100ms: migrasi 028 (constraint DB 100–600000), API min 100, engine floor 100ms, input #tradeDelay min 100 | Done. |
| 2026-09-23 | W/L/R, PROFIT GLOBAL & roll list hanya tampil jika coin cocok; di-clear saat muat pertama halaman (refresh/login), TETAP tampil setelah STOP; swap coin manual tetap clear | Done. |
| 2026-09-23 | W/L/R: R live memakai `streak` (bukan wins+losses); warna PROFIT & R live hijau/merah per roll via paintTradingStats | Done. |
| 2026-09-23 | Proteksi akun: user SUSPENDED & subscription expired tetap bisa login tapi diarahkan ke layar gate (`/suspended`, `/subscribe`); middleware `requireActive` memblokir semua API bisnis (kecuali logout/session); worker management stop trading sesi yang subscription-nya habis; route `/login`,`/register`,`/suspended`,`/subscribe` dilayani `userPage` | Done. |
| 2026-09-23 | Tool admin `show-wallets.bat` → subcommand `wallet-balances`: daftar semua user + saldo wallet **live Pasino** (per-coin via `provider.Balance`). Bat tanya coin dulu lalu jalan satu-satu (`--workers 1`); flag `--csv`/`--limit`/`--workers`/`--no-balance` ada; progress `[i/N]` + ringkasan ke stderr; semua teks UI bat ke `1>&2` → `--csv > saldo.csv` kini CSV murni & progress tetap terlihat | Done. |
| 2026-09-23 | Temuan: socket Pasino abaikan burst `get_balance` — `Balances` (multi-coin) selalu timeout; subcommand memakai baca per-coin. Kalau mau akselerasi 700+ user, investigasi protokol Pasino utk balance jamak | Open. |
| 2026-09-23 | Subcommand `bonus-move` (flag `--dry-run`, `--to`): geser semua bonus referral belum diklaim dari penampung ke tujuan; DB write-off hanya setelah transfer sukses; event `CLAIM_REVERSAL` idempoten | Done. |
| 2026-09-23 | EKSEKUSI atas perintah owner: 51 bonus belum diklaim (22 user; TRX 1,33 / DOGE 33,82 / FLOKI 196.965,09 / BTT 16.306.733,06) dipindah `smartbotapp` → `kangden69`. Verifikasi: 0 sisa available, 51 event CLAIM_REVERSAL, wallet kangden69 naik sesuai | Done. |
| 2026-09-23 | Subcommand `wallet-move` (flag `--manifest`, `--dry-run`, `--to`): transfer nominal dari manifest CSV dari wallet masing-masing user → tujuan; sumber = user; tanpa ubah DB | Done. |
| 2026-09-23 | CLEANING DB `ryubot_go`: 180 user + data anak dihapus permanen, sisakan 6 akun operasional + pengaturan sistem. Backup: `backup\2026-09-23_ryubot_go_pre_cleanup.sql`, script: `backup\2026-09-23_cleanup_users.sql`. DB server lain tidak disentuh | Done. |
| 2026-09-23 | Deploy VPS: `install-vps.sh` (Debian/Ubuntu, domain ryuubot.com) + dump bersih `backup\ryubot_go_clean_2026-09-23.sql` (6 user) untuk diimpor di VPS. Script idempoten: PG/nginx/certbot/UFW/Go, parse .env, systemd, SSL | Done. |
| 2026-09-23 | Tabel roll (`tradeRollList`) backfill di-stagger sesuai delay: history dibatasi 10 baris, baris pertama langsung, sisanya muncul 1-per-`delay_ms` (clamp 100–1000ms) — tidak serentak lagi; guard `sequence`/`tradeCoin` membatalkan sisa backfill saat reload/ganti coin; CSS `@keyframes ryuRollIn` fade-in tiap baris. Rebuild `bin\ryubot.exe` + `bin\ryubot-linux` | Done. |
| 2026-09-23 | Deploy sekali jalan: `deploy-vps.sh` (server: build+migrate+restart+verify, paksa RYUBOT_ENV=production, chown/permission) + `deploy-vps.bat` (Windows: tar-pipe semua source termasuk `.env` ke /opt/ryubot lalu jalankan deploy-vps.sh). README bagian "Upload & Restart Server (VPS)" diupdate | Done. |
| 2026-09-23 | FIX `deploy-vps.bat`: quoting bug cmd.exe — `-C "D:\go\ryubot\"` (backslash sebelum kutip penutup) membuat cmd menelan seluruh baris jadi 1 argumen → `tar: Must specify one of -c, -r, -t, -u, -x` (bekerja di PowerShell, gagal di cmd). Solusi: strip backslash ekor `%SRC:~0,-1%` + tambah `mkdir -p` di sisi server | Done. |
| 2026-09-23 | `deploy-vps.sh` kini otomatis tambah `/usr/local/go/bin` ke PATH (ssh non-login tidak source profile → `command -v go` gagal padahal Go ada) | Done. |
| 2026-09-23 | DEPLOY BERHASIL ke VPS baru **172.232.249.71** (Ubuntu 24.04, sudah ter-install dari `install-vps.sh`, service ACTIVE, SSL ryuubot.com): upload source, build+migrate+restart+verify OK, endpoint https://ryuubot.com live | Done. |
| 2026-09-23 | Cek Pasino dari IP VPS baru 172.232.249.71: `/api/login` + `/account/get-socket-token` KEDUANYA `OK` (200 + JSON) → IP baru **lolos** blokir edge Pasino (beda dgn IP VPS lama 104.64.210.127 yang 403+HTML) | Done. |
| 2026-09-23 | FIX animasi roll saat STOP ("masih ada animasi → rancu"): `command_result` setelah STOP memicu `loadTradeConsole` yang backfill 10 roll lama dgn stagger → terlihat seperti masih jalan. Kini stagger/animasi **hanya saat status persis `RUNNING`**; saat STOP/IDLE (termasuk STOP_REQUESTED) roll lama dirender **langsung statis** (`liveRolls = state.status==='RUNNING'` + class `.no-anim` `animation:none` di CSS); saat START baru roll muncul lagi (backfill bertahap + roll live). Rebuild + deploy ke VPS | Done. |
| 2026-09-23 | FIX "auto logout oleh time": (1) sesi 30 hari absolut -> horizon 10 tahun + sliding refresh (expires_at didorong ke now()+10y bila <9y tersisa) + cookie di-re-issue di setiap respon terautentikasi; (2) hapus DELETE FROM user_sessions saat login -> multi-sesi, login device lain TIDAK meng-kick bot; (3) blip DB/net tidak lagi menghapus cookie (hanya ErrUnauthenticated), respon 500 session_check_failed agar frontend retry; (4) load() frontend retry 4x lalu diam -> hanya tampil /login bila server eksplisit authenticated:false; (5) subscription 6 akun operasional diperpanjang ke now()+10y (opryuubot kedaluwarsa 2026-09-07, 5 lainnya 2026-10-05) di DB lokal + VPS; 4 user trial baru (2233-2236) tidak disentuh. Build+vet OK, deploy VPS + Pasino OK | Done. |

| 2026-09-23 | REDESAIN tabel roll sesuai feedback: konsep "backfill 10 roll terakhir" (dgn stagger sesuai delay) DIHAPUS dari alur START/STOP. Kini: roll hanya live lewat WS (ROLL_SETTLED) selama RUNNING; STOP -> tabel DIAM (bekukan kondisi terakhir, tidak di-rebuild dari history); START -> tabel dikosongkan (Belum ada roll) lalu roll baru muncul live; `{freshRolls}` diteruskan via loadTradeConsole(opts) saat command_result START; historyData/API history tak lagi dipanggil di loadTradeConsole. Rebuild + deploy VPS OK, Pasino OK | Done. |
