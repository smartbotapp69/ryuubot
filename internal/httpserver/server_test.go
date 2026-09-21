package httpserver

import (
	"io"
	"log/slog"
	"net/http/httptest"
	"testing"

	"ryubot/internal/config"
)

func TestHealthHasSecurityHeaders(t *testing.T) {
	server := New(config.Config{HTTPAddr: "127.0.0.1:0", RatePerSecond: 10, RateBurst: 10, MaxBodyBytes: 1024}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	request := httptest.NewRequest("GET", "/healthz", nil)
	request.RemoteAddr = "192.0.2.10:1234"
	response := httptest.NewRecorder()
	server.Handler.ServeHTTP(response, request)
	if response.Code != 200 {
		t.Fatalf("status %d", response.Code)
	}
	if response.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatal("missing security header")
	}
}
