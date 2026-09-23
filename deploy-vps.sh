#!/usr/bin/env bash
#
# deploy-vps.sh — DEPLOY SATU KALI JALAN di server.
# Build binary dari source, migrate DB, restart service, dan verify.
#
# Dipanggil otomatis oleh deploy-vps.bat setelah source di-upload,
# atau jalankan manual di server:  bash /opt/ryubot/deploy-vps.sh
#
# Asumsi: service systemd "ryubot" (WorkingDirectory=/opt/ryubot,
# ExecStart=/opt/ryubot/bin/ryubot serve), user "ryubot".
#
set -euo pipefail

APP_DIR="${1:-/opt/ryubot}"
cd "$APP_DIR"

echo "=== Deploy Ryubot di $APP_DIR ==="

# 1) .env wajib ada
[ -f .env ] || { echo "ERROR: .env tidak ditemukan di $APP_DIR" >&2; exit 1; }

# 2) Pastikan environment produksi
if grep -q '^RYUBOT_ENV=' .env; then
  sed -i 's/^RYUBOT_ENV=.*/RYUBOT_ENV=production/' .env
else
  echo 'RYUBOT_ENV=production' >> .env
fi

# 3) Kepemilikan & permission aman
chown -R ryubot:ryubot "$APP_DIR/." 2>/dev/null || true
chmod 640 .env
chmod +x bin/ryubot 2>/dev/null || true

# 4) Rebuild binary (aman menimpa binary yang sedang berjalan: go build
#    menulis via temp + rename, bukan menulis ke dalam file yang dieksekusi)
# Go toolchain dipasang install-vps.sh di /usr/local/go — pastikan ada di PATH.
if [ -x /usr/local/go/bin/go ]; then
  export PATH="/usr/local/go/bin:$PATH"
fi
command -v go >/dev/null 2>&1 || { echo "ERROR: Go tidak terpasang di server — jalankan install-vps.sh dulu" >&2; exit 1; }
echo "[1/4] Build binary..."
GOFLAGS=-mod=mod CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o bin/ryubot ./cmd/ryubot
chown ryubot:ryubot bin/ryubot
chmod +x bin/ryubot

# 5) Migrasi DB (idempoten via schema_migrations)
echo "[2/4] Migrasi database..."
./bin/ryubot migrate || echo "WARNING: migrate gagal — cek: journalctl -u ryubot -n 50" >&2

# 6) Restart service
echo "[3/4] Restart service ryubot..."
systemctl restart ryubot
sleep 2

# 7) Verify
echo "[4/4] Verify..."
if systemctl is-active --quiet ryubot; then
  echo "  service ryubot : ACTIVE"
else
  echo "  service ryubot : TIDAK AKTIF" >&2
  systemctl status ryubot --no-pager -n 30 >&2 || true
  journalctl -u ryubot -n 30 --no-pager >&2 || true
  exit 1
fi
systemctl is-enabled --quiet ryubot 2>/dev/null && echo "  enabled        : ya" || echo "  enabled        : TIDAK (jalankan: systemctl enable ryubot)"
echo "  endpoint       : https://ryuubot.com  (Ctrl+F5 di browser user setelah deploy)"
echo "=== Deploy selesai ==="