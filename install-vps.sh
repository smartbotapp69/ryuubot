#!/usr/bin/env bash
#
# ============================================================================
#  Ryubot — Instalasi & Deploy VPS (Debian/Ubuntu)
# ----------------------------------------------------------------------------
#  Yang dikerjakan:
#    1. Install dependensi: PostgreSQL, Nginx, certbot, UFW, build tools, Go 1.27+
#    2. Buat role + database persis sesuai RYUBOT_DATABASE_URL di .env
#    3. Import dump database BERSIH (hanya 6 user operasional)
#    4. Build aplikasi + pasang service systemd (ryubot)
#    5. Reverse-proxy Nginx (termasuk WebSocket) untuk ryuubot.com
#    6. SSL Let's Encrypt (certbot) bila DNS sudah diarahkan
#
#  Cara pakai:
#    1) Letakkan proyek di VPS (mis. /opt/ryubot) + file pendukung:
#         scp -r D:/go/ryubot/* user@IP_VPS:/opt/ryubot/
#         # WAJIB pastikan /opt/ryubot/.env berisi config production (lihat
#         # template yang dibuat otomatis jika .env belum ada)
#    2) Jalankan sebagai root:
#         bash /opt/ryubot/install-vps.sh /opt/ryubot
#    3) Bila DNS ryuubot.com (A + www) SUDAH menunjuk ke IP VPS ini, sertakan
#       email Let's Encrypt agar SSL langsung dibuat:
#         CERT_EMAIL=admin@example.com bash /opt/ryubot/install-vps.sh /opt/ryubot
#       (cukup jalankan ulang — script idempoten; SSL dibuat jika CERT_EMAIL diisi)
#
#  Variabel env override:
#    DOMAIN      default: ryuubot.com
#    CERT_EMAIL  default: kosong (SSL dilewati)
#    DUMP_FILE   default: /opt/ryubot/backup/ryubot_go_clean_2026-09-23.sql
# ============================================================================
set -euo pipefail

DOMAIN="${DOMAIN:-ryuubot.com}"
APP_DIR="${1:-/opt/ryubot}"
CERT_EMAIL="${CERT_EMAIL:-}"
DUMP_FILE="${DUMP_FILE:-$APP_DIR/backup/ryubot_go_clean_2026-09-23.sql}"
GO_MIN_MAJOR=1
GO_MIN_MINOR=27
GO_ARCH="amd64"
SERVICE_USER="ryubot"

say()  { printf '\n\033[1;32m>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Preflight
# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "Jalankan sebagai root (sudo bash $0 ...)"
command -v apt-get >/dev/null 2>&1 || die "Script ini khusus Debian/Ubuntu (apt)."
[ -d "$APP_DIR" ] || die "Direktori aplikasi tidak ditemukan: $APP_DIR"

cd "$APP_DIR"
export DEBIAN_FRONTEND=noninteractive

# .env wajib ada — buat template bila belum
if [ ! -f .env ]; then
  say "Membuat template .env (ISI NILAI PASINO & ADMIN lalu jalankan ulang)"
  SECRET="$(openssl rand -hex 32)"
  ADMIN_PASS="$(openssl rand -hex 12)"
  cat > .env <<EOF
RYUBOT_ENV=production
RYUBOT_HTTP_ADDR=127.0.0.1:8080
RYUBOT_SESSION_SECRET=$SECRET
RYUBOT_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/ryubot_go
RYUBOT_TRUSTED_PROXIES=127.0.0.1/32,::1/128

# Pasino (WAJIB diisi dari .env lokal Anda)
PASINO_API_KEY=
PASINO_CREDENTIAL_ENCRYPTION_KEY=
PASINO_REFERRER=277064
# Opsional: proxy SOCKS5/HTTP ber-IP bersih bila IP VPS diblokir Pasino (403). Contoh: socks5h://user:pass@host:1080
PASINO_PROXY_URL=

# Admin panel (WAJIB diganti passwordnya)
RYUBOT_ADMIN_USERNAME=admin
RYUBOT_ADMIN_PASSWORD=$ADMIN_PASS
EOF
  warn ".env dibuat dengan password admin acak: $ADMIN_PASS"
  warn "Isi PASINO_API_KEY & PASINO_CREDENTIAL_ENCRYPTION_KEY dari .env lokal Anda, lalu jalankan ulang script."
  exit 1
fi

# Parse RYUBOT_DATABASE_URL dan RYUBOT_HTTP_ADDR dari .env
DB_URL="$(grep -E '^RYUBOT_DATABASE_URL=' .env | head -n1 | cut -d= -f2- | tr -d '\r' | sed -e 's/^["'\'']//' -e 's/["'\'']$//')"
if [[ "$DB_URL" =~ ^postgres(ql)?://([^:/]+):([^@]*)@([^:/]+):([0-9]+)/([^? ]+)[?]?.*$ ]]; then
  DB_USER="${BASH_REMATCH[2]}"
  DB_PASS="${BASH_REMATCH[3]}"
  DB_HOST="${BASH_REMATCH[4]}"
  DB_PORT="${BASH_REMATCH[5]}"
  DB_NAME="${BASH_REMATCH[6]}"
else
  die "Tidak bisa parse RYUBOT_DATABASE_URL: $DB_URL"
fi
HTTP_ADDR="$(grep -E '^RYUBOT_HTTP_ADDR=' .env | head -n1 | cut -d= -f2- | tr -d '\r"')"
HTTP_PORT="${HTTP_ADDR##*:}"
[[ "$HTTP_PORT" =~ ^[0-9]+$ ]] || HTTP_PORT=8080

say "Konfigurasi terdeteksi"
echo "   App dir      : $APP_DIR"
echo "   DB           : ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "   HTTP app     : ${HTTP_ADDR:-127.0.0.1:8080} (nginx -> port $HTTP_PORT)"
echo "   Domain       : $DOMAIN"
echo "   Dump import  : $DUMP_FILE"

# ---------------------------------------------------------------------------
# 1. Install paket sistem
# ---------------------------------------------------------------------------
say "Install dependensi sistem (apt)"
apt-get update -y
apt-get install -y --no-install-recommends \
    curl ca-certificates wget git gnupg lsb-release \
    build-essential openssl \
    postgresql postgresql-contrib \
    nginx certbot python3-certbot-nginx \
    ufw

systemctl enable --now postgresql nginx >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 2. Setup database sesuai .env + import dump
# ---------------------------------------------------------------------------
say "Setup role & database PostgreSQL ($DB_NAME)"
DB_SQL="$(mktemp)"
cat > "$DB_SQL" <<SQL
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER') THEN
    EXECUTE format('ALTER ROLE %I PASSWORD %L', '$DB_USER', '$DB_PASS');
  ELSE
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '$DB_USER', '$DB_PASS');
  END IF;
END
\$\$;
SQL
# root membuka file (berisi password DB) dan pipe ke psql sebagai postgres via stdin —
# tanpa mengubah permission file (mktemp default 600 root)
su - postgres -c "psql -v ON_ERROR_STOP=1 -q" < "$DB_SQL"
rm -f "$DB_SQL"

DB_EXISTS="$(su - postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$DB_NAME'\"")"
if [ "$DB_EXISTS" != "1" ]; then
  su - postgres -c "createdb -O '$DB_USER' '$DB_NAME'"
  say "Database $DB_NAME dibuat (owner $DB_USER)"
else
  warn "Database $DB_NAME sudah ada — dipakai apa adanya"
fi

# pastikan koneksi TCP localhost dengan password diperbolehkan
PGBASE="/etc/postgresql"
if [ -d "$PGBASE" ]; then
  HBA="$(ls -1 "$PGBASE"/*/main/pg_hba.conf 2>/dev/null | head -n1)"
  if [ -n "$HBA" ] && ! grep -qE "^host[[:space:]]+all[[:space:]]+all[[:space:]]+127\.0\.0\.1/32.*(scram|md5)" "$HBA"; then
    cp "$HBA" "$HBA.bak"
    printf 'host all all 127.0.0.1/32 scram-sha-256\n' >> "$HBA"
    systemctl restart postgresql
  fi
fi

if [ -f "$DUMP_FILE" ]; then
  say "Import dump bersih: $DUMP_FILE"
  # Dump dibuat di PG18 yang menulis "SET transaction_timeout" (fitur PG17+, tidak dikenal
  # PG16 di Ubuntu) — saring baris tsb. root membuka file, psql (via su) baca dari stdin.
  sed -e '/^SET transaction_timeout = 0;$/d' "$DUMP_FILE" \
    | PGCLIENTENCODING=UTF8 su - postgres -c "psql -v ON_ERROR_STOP=1 -q -d '$DB_NAME'"
  N_USERS="$(su - postgres -c "psql -d '$DB_NAME' -tAc 'SELECT count(*) FROM users'")"
  N_SETTINGS="$(su - postgres -c "psql -d '$DB_NAME' -tAc 'SELECT count(*) FROM app_settings'")"
  say "Verifikasi import: users=$N_USERS (harus 6), app_settings=$N_SETTINGS (harus 36)"
else
  warn "Dump tidak ditemukan: $DUMP_FILE — database dibiarkan kosong!"
  warn "Salin dump:  scp backup/ryubot_go_clean_2026-09-23.sql root@IP_VPS:$APP_DIR/backup/"
fi

# ---------------------------------------------------------------------------
# 3. Install Go 1.27+ (bila belum / versi terlalu lama)
# ---------------------------------------------------------------------------
say "Cek Go toolchain"
GO_OK=0
if command -v go >/dev/null 2>&1; then
  GV="$(go version | awk '{print $3}' | sed 's/^go//')"
  G_MAJ="${GV%%.*}"; G_MIN="${GV#*.}"; G_MIN="${G_MIN%%.*}"
  if [ "${G_MAJ:-0}" -gt "$GO_MIN_MAJOR" ] || { [ "${G_MAJ:-0}" -eq "$GO_MIN_MAJOR" ] && [ "${G_MIN:-0}" -ge "$GO_MIN_MINOR" ]; }; then
    GO_OK=1
  fi
fi
if [ "$GO_OK" -ne 1 ]; then
  say "Mengunduh Go terbaru dari go.dev"
  LATEST_GO="$(curl -fsSL --retry 3 'https://go.dev/VERSION?m=text' | head -n1)"
  [ -n "$LATEST_GO" ] || die "Gagal mengambil versi Go terbaru"
  curl -fsSL --retry 3 -o /tmp/go.tgz "https://go.dev/dl/${LATEST_GO}.linux-${GO_ARCH}.tar.gz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tgz
  export PATH="/usr/local/go/bin:$PATH"
  say "Go terpasang: $(go version)"
else
  say "Go sudah memadai: $(go version)"
fi

# ---------------------------------------------------------------------------
# 4. Build aplikasi + pasang service systemd
# ---------------------------------------------------------------------------
say "Build binary ryubot"
if [ ! -x "$APP_DIR/bin/ryubot" ] || [ ! -z "${FORCE_REBUILD:-}" ]; then
  cd "$APP_DIR"
  [ -d /usr/local/go/bin ] && export PATH="/usr/local/go/bin:$PATH"
  GOFLAGS=-mod=mod CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$APP_DIR/bin/ryubot" ./cmd/ryubot
fi
[ -x "$APP_DIR/bin/ryubot" ] || die "Binary $APP_DIR/bin/ryubot tidak terbentuk"

say "Pasang service systemd ($SERVICE_USER)"
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/ryubot --create-home --shell /usr/sbin/nologin "$SERVICE_USER"
fi
chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"

cat > /etc/systemd/system/ryubot.service <<EOF
[Unit]
Description=Ryubot trading web app
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/bin/ryubot serve
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ryubot
systemctl restart ryubot
sleep 2

# ---------------------------------------------------------------------------
# 5. Nginx reverse proxy (dengan dukungan WebSocket)
# ---------------------------------------------------------------------------
say "Konfigurasi Nginx untuk $DOMAIN"
cat > /etc/nginx/sites-available/ryubot <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    client_max_body_size 25m;

    location / {
        proxy_pass http://127.0.0.1:${HTTP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/ryubot /etc/nginx/sites-enabled/ryubot
nginx -t
systemctl reload nginx

# ---------------------------------------------------------------------------
# 6. Firewall
# ---------------------------------------------------------------------------
say "Aktifkan UFW (SSH + HTTP/HTTPS)"
ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp
ufw allow 'Nginx Full'
ufw --force enable

# ---------------------------------------------------------------------------
# 7. SSL Let's Encrypt
# ---------------------------------------------------------------------------
SSL_DONE=0
if [ -n "${CERT_EMAIL}" ]; then
  say "Minta sertifikat SSL untuk $DOMAIN & www.$DOMAIN"
  if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m "$CERT_EMAIL" --redirect; then
    SSL_DONE=1
  else
    warn "SSL gagal — pastikan DNS ${DOMAIN} (A @ dan www) menunjuk ke IP VPS ini, lalu jalankan ulang dengan CERT_EMAIL."
  fi
fi

# ---------------------------------------------------------------------------
# 8. Verifikasi akhir
# ---------------------------------------------------------------------------
say "Verifikasi akhir"
systemctl is-active ryubot >/dev/null 2>&1 && echo "   service ryubot : ACTIVE" || warn "service ryubot TIDAK aktif — cek: journalctl -u ryubot -n 50"
CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HTTP_PORT}/" || true)"
echo "   HTTP app lokal : $CODE (harusnya 200)"
if [ "$SSL_DONE" -eq 1 ]; then
  echo "   Publik         : https://$DOMAIN  (SSL OK)"
else
  echo "   Publik         : http://$DOMAIN (SSL menyusul — isi CERT_EMAIL saat DNS aktif)"
fi
echo ""
echo "Info penting:"
echo "   - Log service : journalctl -u ryubot -f"
echo "   - Binaries    : $APP_DIR/bin/ryubot  (rebuild: FORCE_REBUILD=1 bash $0 $APP_DIR)"
echo "   - Dump awal   : $APP_DIR/backup/ (jangan di-commit jika repo git)"
echo "   - Renew SSL otomatis: systemctl list-timers | grep certbot"
echo ""
echo "SELESAI ✓"