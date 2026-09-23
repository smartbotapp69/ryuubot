package config

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Environment         string
	HTTPAddr            string
	ShutdownTimeout     time.Duration
	TrustedProxies      []netip.Prefix
	RatePerSecond       float64
	RateBurst           int
	MaxBodyBytes        int64
	SessionSecret       string
	DatabaseURL         string
	LegacyDatabaseURL   string
	PasinoAPIBaseURL    string
	PasinoSocketURL     string
	PasinoProxyURL      string
	PasinoAPIKey        string
	PasinoCredentialKey string
	PasinoReferrer      string
	AdminUsername       string
	AdminPassword       string
}

func Load() (Config, error) {
	if err := loadDotEnv(".env"); err != nil {
		return Config{}, fmt.Errorf("load .env: %w", err)
	}
	cfg := Config{
		Environment:         value("RYUBOT_ENV", "development"),
		HTTPAddr:            value("RYUBOT_HTTP_ADDR", "127.0.0.1:8080"),
		ShutdownTimeout:     15 * time.Second,
		RatePerSecond:       10,
		RateBurst:           30,
		MaxBodyBytes:        1 << 20,
		SessionSecret:       os.Getenv("RYUBOT_SESSION_SECRET"),
		DatabaseURL:         strings.TrimSpace(os.Getenv("RYUBOT_DATABASE_URL")),
		LegacyDatabaseURL:   strings.TrimSpace(os.Getenv("RYUBOT_LEGACY_DATABASE_URL")),
		PasinoAPIBaseURL:    value("PASINO_API_BASE_URL", "https://api.pasino.io"),
		PasinoSocketURL:     value("PASINO_SOCKET_URL", "wss://socket.pasino.io/dice/"),
		PasinoProxyURL:      strings.TrimSpace(os.Getenv("PASINO_PROXY_URL")),
		PasinoAPIKey:        strings.TrimSpace(os.Getenv("PASINO_API_KEY")),
		PasinoCredentialKey: strings.TrimSpace(os.Getenv("PASINO_CREDENTIAL_ENCRYPTION_KEY")),
		PasinoReferrer:      strings.TrimSpace(value("PASINO_REFERRER", "277064")),
		AdminUsername:       strings.TrimSpace(os.Getenv("RYUBOT_ADMIN_USERNAME")),
		AdminPassword:       os.Getenv("RYUBOT_ADMIN_PASSWORD"),
	}

	var err error
	if raw := os.Getenv("RYUBOT_SHUTDOWN_TIMEOUT"); raw != "" {
		cfg.ShutdownTimeout, err = time.ParseDuration(raw)
		if err != nil {
			return Config{}, fmt.Errorf("RYUBOT_SHUTDOWN_TIMEOUT: %w", err)
		}
	}
	if cfg.TrustedProxies, err = prefixes(os.Getenv("RYUBOT_TRUSTED_PROXIES")); err != nil {
		return Config{}, err
	}
	if cfg.RatePerSecond, err = floatValue("RYUBOT_RATE_PER_SECOND", cfg.RatePerSecond); err != nil {
		return Config{}, err
	}
	if cfg.RateBurst, err = intValue("RYUBOT_RATE_BURST", cfg.RateBurst); err != nil {
		return Config{}, err
	}
	if cfg.MaxBodyBytes, err = int64Value("RYUBOT_MAX_BODY_BYTES", cfg.MaxBodyBytes); err != nil {
		return Config{}, err
	}
	if err := cfg.Validate(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func (c Config) Validate() error {
	if c.Environment != "development" && c.Environment != "test" && c.Environment != "production" {
		return errors.New("RYUBOT_ENV must be development, test, or production")
	}
	if c.HTTPAddr == "" || c.ShutdownTimeout <= 0 || c.RatePerSecond <= 0 || c.RateBurst < 1 || c.MaxBodyBytes < 1 {
		return errors.New("HTTP and resource limits must be positive")
	}
	if c.DatabaseURL == "" {
		return errors.New("RYUBOT_DATABASE_URL is required")
	}
	if c.Environment == "production" {
		if len(c.SessionSecret) < 32 || c.SessionSecret == "development-only-change-this-value" {
			return errors.New("production RYUBOT_SESSION_SECRET must be unique and at least 32 bytes")
		}
		host, _, err := net.SplitHostPort(c.HTTPAddr)
		if err != nil {
			return fmt.Errorf("RYUBOT_HTTP_ADDR: %w", err)
		}
		if host == "" || host == "0.0.0.0" || host == "::" {
			return errors.New("production HTTP must bind to a private address; use nginx as the public edge")
		}
	}
	return nil
}

func value(key, fallback string) string {
	if result := strings.TrimSpace(os.Getenv(key)); result != "" {
		return result
	}
	return fallback
}

func prefixes(raw string) ([]netip.Prefix, error) {
	if strings.TrimSpace(raw) == "" {
		return nil, nil
	}
	var result []netip.Prefix
	for _, item := range strings.Split(raw, ",") {
		prefix, err := netip.ParsePrefix(strings.TrimSpace(item))
		if err != nil {
			return nil, fmt.Errorf("RYUBOT_TRUSTED_PROXIES: %w", err)
		}
		result = append(result, prefix)
	}
	return result, nil
}

func floatValue(key string, fallback float64) (float64, error) {
	if os.Getenv(key) == "" {
		return fallback, nil
	}
	v, err := strconv.ParseFloat(os.Getenv(key), 64)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", key, err)
	}
	return v, nil
}

func intValue(key string, fallback int) (int, error) {
	if os.Getenv(key) == "" {
		return fallback, nil
	}
	v, err := strconv.Atoi(os.Getenv(key))
	if err != nil {
		return 0, fmt.Errorf("%s: %w", key, err)
	}
	return v, nil
}

func int64Value(key string, fallback int64) (int64, error) {
	if os.Getenv(key) == "" {
		return fallback, nil
	}
	v, err := strconv.ParseInt(os.Getenv(key), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", key, err)
	}
	return v, nil
}
