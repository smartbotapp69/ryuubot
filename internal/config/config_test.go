package config

import "testing"

func TestProductionRejectsWeakSecretAndPublicBind(t *testing.T) {
	t.Setenv("RYUBOT_ENV", "production")
	t.Setenv("RYUBOT_HTTP_ADDR", "0.0.0.0:8080")
	t.Setenv("RYUBOT_SESSION_SECRET", "short")
	t.Setenv("RYUBOT_DATABASE_URL", "postgresql://localhost/test")
	if _, err := Load(); err == nil {
		t.Fatal("expected unsafe production configuration to fail")
	}
}

func TestProductionRejectsImplicitAllInterfaces(t *testing.T) {
	t.Setenv("RYUBOT_ENV", "production")
	t.Setenv("RYUBOT_HTTP_ADDR", ":8080")
	t.Setenv("RYUBOT_SESSION_SECRET", "a-unique-production-secret-over-32-bytes")
	t.Setenv("RYUBOT_DATABASE_URL", "postgresql://localhost/test")
	if _, err := Load(); err == nil {
		t.Fatal("expected implicit public bind to fail")
	}
}

func TestDevelopmentDefaultsAreValid(t *testing.T) {
	t.Setenv("RYUBOT_ENV", "development")
	t.Setenv("RYUBOT_SESSION_SECRET", "")
	t.Setenv("RYUBOT_DATABASE_URL", "postgresql://localhost/test")
	t.Setenv("RYUBOT_ADMIN_USERNAME", "admin")
	t.Setenv("RYUBOT_ADMIN_PASSWORD", "a-secure-admin-password")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.HTTPAddr != "127.0.0.1:8080" {
		t.Fatalf("unexpected address %q", cfg.HTTPAddr)
	}
}
