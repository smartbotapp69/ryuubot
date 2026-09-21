package security

import (
	"net/netip"
	"sync"
	"time"
)

type visitor struct {
	tokens  float64
	updated time.Time
}

type Limiter struct {
	mu        sync.Mutex
	rate      float64
	burst     float64
	visitors  map[netip.Addr]visitor
	lastSweep time.Time
}

func NewLimiter(rate float64, burst int) *Limiter {
	return &Limiter{rate: rate, burst: float64(burst), visitors: make(map[netip.Addr]visitor), lastSweep: time.Now()}
}

func (l *Limiter) Allow(address netip.Addr, now time.Time) bool {
	if !address.IsValid() {
		return false
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	v, ok := l.visitors[address]
	if !ok {
		v = visitor{tokens: l.burst, updated: now}
	}
	v.tokens += now.Sub(v.updated).Seconds() * l.rate
	if v.tokens > l.burst {
		v.tokens = l.burst
	}
	v.updated = now
	allowed := v.tokens >= 1
	if allowed {
		v.tokens--
	}
	l.visitors[address] = v
	if now.Sub(l.lastSweep) > 5*time.Minute {
		for key, entry := range l.visitors {
			if now.Sub(entry.updated) > 10*time.Minute {
				delete(l.visitors, key)
			}
		}
		l.lastSweep = now
	}
	return allowed
}
