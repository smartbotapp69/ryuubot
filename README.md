# Ryubot Go

Secure rebuild of RyuuBot as one Go codebase and one deployable binary. The
binary has explicit `serve`, `worker`, `migrate`, and `verify` modes so the API
and trading runner can be isolated without maintaining different builds.

Current scope is deliberately non-financial: configuration validation,
bounded HTTP handling, trusted-proxy parsing, per-client rate limiting,
security headers, health endpoints, and graceful shutdown. The worker,
migrations, authentication, ledger, and Pasino mutations remain disabled until
their business behavior is captured by compatibility tests.

## Commands

```powershell
go test ./...
go build -trimpath -ldflags "-s -w" -o bin/ryubot.exe ./cmd/ryubot
```

To run locally, copy `.env.example` values into the process environment and
run `ryubot serve`. Environment files are not loaded implicitly, preventing a
production service from accidentally reading a developer file.

## Upload & Restart Server (VPS)

Target: systemd service `ryubot` di `/opt/ryubot` (binary `bin/ryubot`, berjalan
sebagai user `ryubot`, nginx sebagai edge). Frontend (`assets/`) sudah di-embed
ke dalam binary, jadi perubahan frontend **wajib rebuild binary lalu restart** —
mengganti file asset saja tidak cukup.

### Deploy sekali jalan (disarankan)

```bat
deploy-vps.bat IP_VPS            rem atur RYUBOT_VPS_IP=dulu, lalu cukup: deploy-vps.bat
```

One command does everything: upload the full source **including `.env`** to
`/opt/ryubot`, then run `deploy-vps.sh` on the server, which forces
`RYUBOT_ENV=production`, rebuilds `bin/ryubot`, runs DB migrations, restarts
`ryubot.service`, and verifies it is `active`. Manual steps below are only for
special cases (debugging, or when no Windows machine is available).

> **Gotcha (fixed 2026-09-23):** di cmd.exe, `tar -C "%SRC%"` gagal dengan
> `Must specify one of -c, -r, -t, -u, -x` ketika direktori berakhir `\`
> (`"D:\go\ryubot\"`) — cmd menelan sisa baris jadi satu argumen. Bat kini
> membuang backslash ekor (`%SRC:~0,-1%`) dan menambah `mkdir -p /opt/ryubot` di
> sisi server. `deploy-vps.sh` juga menambah `/usr/local/go/bin` ke PATH (ssh
> non-login tidak source profile, jadi Go yang dipasang install-vps.sh tak
> terlihat).

```bash
# Manual di server (tanpa Windows):
bash /opt/ryubot/deploy-vps.sh
```

### 1) Build binary

```powershell
# Lokal (Windows)
go build -trimpath -ldflags "-s -w" -o bin\ryubot.exe ./cmd/ryubot

# Cross-compile untuk Linux (VPS amd64)
$env:GOOS='linux'; $env:GOARCH='amd64'
go build -trimpath -ldflags "-s -w" -o bin\ryubot-linux ./cmd/ryubot

# Di server langsung (disarankan — arsitektur selalu cocok)
cd /opt/ryubot && GOFLAGS=-mod=mod CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o bin/ryubot ./cmd/ryubot && chown ryubot:ryubot bin/ryubot
```

### 2) Upload

**A. Sinkron seluruh source (untuk rebuild di server — cara utama):**

```bash
# dari Windows (PowerShell)
scp -r D:/go/ryubot/* root@IP_VPS:/opt/ryubot/
scp D:/go/ryubot/.env root@IP_VPS:/opt/ryubot/.env   # dotfile TIDAK ikut wildcard *
```

**B. Update cepat: binary saja**

```bash
scp D:/go/ryubot/bin/ryubot-linux root@IP_VPS:/tmp/ryubot
# JANGAN scp langsung ke /opt/ryubot/bin/ryubot — binary sedang dieksekusi (error "dest open Failure"/ETXTBSY).
ssh root@IP_VPS "mv /tmp/ryubot /opt/ryubot/bin/ryubot && chown ryubot:ryubot /opt/ryubot/bin/ryubot && chmod +x /opt/ryubot/bin/ryubot"
```

> Catatan: `go build -o` di Linux aman menimpa binary yang sedang berjalan
> (ditulis via file temp + rename). Yang bermasalah adalah `scp`/`cp` yang
> menulis **ke dalam** file binary yang sedang dieksekusi.

### 3) Restart & verifikasi

```bash
ssh root@IP_VPS "systemctl restart ryubot"
ssh root@IP_VPS "systemctl status ryubot"
ssh root@IP_VPS "journalctl -u ryubot -n 50"     # error terakhir
ssh root@IP_VPS "journalctl -u ryubot -f"        # ikuti log live
```

- nginx hanya perlu `systemctl reload nginx` bila konfigurasinya berubah.
- Setelah deploy, browser user perlu **Ctrl+F5** agar tidak memakai asset lama.
- `.env` wajib ada di `/opt/ryubot` (tidak pernah di-commit) dan
  `RYUBOT_ENV=production` di VPS.
- Untuk rebuild+install penuh (termasuk verify users=6, app_settings=36):
  `ssh root@IP_VPS "FORCE_REBUILD=1 bash /opt/ryubot/install-vps.sh /opt/ryubot"`
- Cek layanan: `systemctl is-active ryubot` (diharapkan `active`).

## Security boundary

The Go service binds to loopback in the supplied configuration and must sit
behind nginx. Application limits reduce resource abuse but do not replace a
provider firewall/CDN for volumetric DDoS protection. Only nginx addresses
listed in `RYUBOT_TRUSTED_PROXIES` may supply `X-Forwarded-For`.
