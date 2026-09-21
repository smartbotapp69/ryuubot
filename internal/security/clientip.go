package security

import (
	"net"
	"net/http"
	"net/netip"
	"strings"
)

type ClientIPResolver struct{ trusted []netip.Prefix }

func NewClientIPResolver(trusted []netip.Prefix) ClientIPResolver {
	return ClientIPResolver{trusted: append([]netip.Prefix(nil), trusted...)}
}

func (r ClientIPResolver) Resolve(request *http.Request) netip.Addr {
	peer := parseAddress(request.RemoteAddr)
	if !peer.IsValid() || !r.isTrusted(peer) {
		return peer
	}
	forwarded := strings.Split(request.Header.Get("X-Forwarded-For"), ",")
	for index := len(forwarded) - 1; index >= 0; index-- {
		candidate := parseAddress(strings.TrimSpace(forwarded[index]))
		if candidate.IsValid() && !r.isTrusted(candidate) {
			return candidate
		}
	}
	return peer
}

func (r ClientIPResolver) isTrusted(address netip.Addr) bool {
	for _, prefix := range r.trusted {
		if prefix.Contains(address) {
			return true
		}
	}
	return false
}

func parseAddress(raw string) netip.Addr {
	if host, _, err := net.SplitHostPort(raw); err == nil {
		raw = host
	}
	address, _ := netip.ParseAddr(strings.Trim(raw, "[]"))
	return address.Unmap()
}
