#!/usr/bin/env bash
#
# check-pasino-ip.sh — uji cepat sebuah IP terhadap API Pasino.
#
# Tujuan: sebelum deploy ke VPS baru (atau sebelum menyewa proxy ber-IP bersih),
# pastikan IP tersebut TIDAK diblokir edge Pasino. Kalau diblokir, endpoint API
# membalas halaman HTML (HTTP 403) alih-alih JSON.
#
# Pemakaian:
#   # 1) Di VPS yang mau dicek (sebelum/ketika app dipasang):
#   PASINO_API_KEY=<key> bash check-pasino-ip.sh
#
#   # 2) Dari mana saja, untuk memvalidasi IP keluar sebuah proxy bersih:
#   PASINO_API_KEY=<key> bash check-pasino-ip.sh socks5h://user:pass@host:1080
#   PASINO_API_KEY=<key> bash check-pasino-ip.sh http://user:pass@host:8080
#
# Hasil per endpoint:
#   OK       -> respons JSON (IP normal, boleh dipakai)
#   BLOCKED  -> HTTP 403/4xx/5xx + bukan JSON (IP kena blokir edge/Cloudflare)
#   ???      -> 200 tapi tidak berbentuk JSON (curiga, cek manual)
#
set -euo pipefail

PROXY="${1:-}"
KEY="${PASINO_API_KEY:-}"
if [ -z "$KEY" ] && [ -f .env ]; then
  KEY="$(awk -F= '/^PASINO_API_KEY=/{print $2}' .env | tr -d '\r')"
fi
if [ -z "$KEY" ]; then
  echo "PASINO_API_KEY tidak ditemukan — set via env atau sediakan .env di CWD."
  exit 1
fi

probe() {
  local name="$1" body="$2"
  local tmp status first
  tmp="$(mktemp)"
  status="$(
    curl -sS --max-time 20 ${PROXY:+-x "$PROXY"} -o "$tmp" -w '%{http_code}' \
      -X POST -H "Content-Type: application/json" -d "$body" \
      "https://api.pasino.io$name" 2>/dev/null || echo 000
  )"
  first="$(head -1 "$tmp" 2>/dev/null | tr -d '\r' | cut -c1-100)"
  if [ "$status" = 200 ] && [[ "$first" == \{* ]]; then
    printf '  OK      %s  %s  ->  %s\n' "$status" "$name" "$first"
  elif [ "$status" = 200 ]; then
    printf '  ???     %s  %s  (200 tapi bukan JSON)  ->  %s\n' "$status" "$name" "$first"
  else
    printf '  BLOCKED %s  %s  ->  %s\n' "$status" "$name" "$first"
  fi
  rm -f "$tmp"
}

echo "Keluar lewat: ${PROXY:-- (langsung, IP mesin ini)}"
echo ""
probe "/api/login" "{\"user\":\"ip-check@example.com\",\"password\":\"x\",\"api_key\":\"$KEY\"}"
probe "/account/get-socket-token" '{"token":"dummy-invalid-token"}'
echo ""
echo "Catatan: 'OK' artinya IP LOLOS ke API Pasino (respons JSON), bukan berarti kredensial benar."