package security

import (
	"net/http/httptest"
	"net/netip"
	"testing"
)

func TestForwardedIPOnlyFromTrustedProxy(t *testing.T) {
	resolver := NewClientIPResolver([]netip.Prefix{netip.MustParsePrefix("127.0.0.1/32")})
	request := httptest.NewRequest("GET", "/", nil)
	request.RemoteAddr = "127.0.0.1:1234"
	request.Header.Set("X-Forwarded-For", "198.51.100.20, 127.0.0.1")
	if got := resolver.Resolve(request).String(); got != "198.51.100.20" {
		t.Fatalf("got %s", got)
	}

	request.RemoteAddr = "203.0.113.5:1234"
	if got := resolver.Resolve(request).String(); got != "203.0.113.5" {
		t.Fatalf("trusted spoofed header: %s", got)
	}
}
