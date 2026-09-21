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

## Security boundary

The Go service binds to loopback in the supplied configuration and must sit
behind nginx. Application limits reduce resource abuse but do not replace a
provider firewall/CDN for volumetric DDoS protection. Only nginx addresses
listed in `RYUBOT_TRUSTED_PROXIES` may supply `X-Forwarded-For`.
