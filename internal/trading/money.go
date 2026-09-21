package trading

import (
	"errors"
	"math/big"
	"strconv"
	"strings"
)

const Scale int64 = 100_000_000

type Money int64

func ParseMoney(value string) (Money, error) {
	raw := strings.TrimSpace(value)
	if strings.HasPrefix(raw, "-") {
		return 0, errors.New("nominal tidak valid")
	}
	return parseSignedMoney(raw)
}

func ParseSignedMoney(value string) (Money, error) {
	return parseSignedMoney(strings.TrimSpace(value))
}

func parseSignedMoney(raw string) (Money, error) {
	if raw == "" {
		return 0, errors.New("nominal tidak valid")
	}
	parts := strings.Split(raw, ".")
	unsigned := strings.TrimPrefix(raw, "-")
	parts = strings.Split(unsigned, ".")
	if len(parts) > 2 || len(parts) == 2 && len(parts[1]) > 8 {
		return 0, errors.New("maksimal delapan desimal")
	}
	rational, ok := new(big.Rat).SetString(raw)
	if !ok {
		return 0, errors.New("nominal tidak valid")
	}
	rational.Mul(rational, big.NewRat(Scale, 1))
	if !rational.IsInt() || !rational.Num().IsInt64() {
		return 0, errors.New("nominal di luar batas")
	}
	return Money(rational.Num().Int64()), nil
}

func (m Money) String() string {
	value := big.NewInt(int64(m))
	negative := value.Sign() < 0
	value.Abs(value)
	whole, fraction := new(big.Int), new(big.Int)
	whole.QuoRem(value, big.NewInt(Scale), fraction)
	result := whole.String() + "." + fmtFraction(fraction.Int64())
	result = strings.TrimRight(strings.TrimRight(result, "0"), ".")
	if negative && result != "0" {
		return "-" + result
	}
	return result
}

// FixedString is the eight-decimal wire representation required by Pasino.
func (m Money) FixedString() string {
	value := big.NewInt(int64(m))
	negative := value.Sign() < 0
	value.Abs(value)
	whole, fraction := new(big.Int), new(big.Int)
	whole.QuoRem(value, big.NewInt(Scale), fraction)
	result := whole.String() + "." + fmtFraction(fraction.Int64())
	if negative {
		return "-" + result
	}
	return result
}

// ParseProviderSignedMoney follows the legacy runner: Pasino values are
// normalized to atomic units by truncating digits beyond eight decimals.
func ParseProviderSignedMoney(value string) (Money, error) {
	raw := strings.TrimSpace(value)
	if raw == "" {
		return 0, errors.New("nominal Pasino tidak valid")
	}
	negative := strings.HasPrefix(raw, "-")
	unsigned := strings.TrimPrefix(strings.TrimPrefix(raw, "-"), "+")
	parts := strings.Split(unsigned, ".")
	if len(parts) > 2 || parts[0] == "" {
		return 0, errors.New("nominal Pasino tidak valid")
	}
	fraction := ""
	if len(parts) == 2 {
		fraction = parts[1]
	}
	if len(fraction) > 8 {
		fraction = fraction[:8]
	}
	normalized := parts[0] + "." + fraction + strings.Repeat("0", 8-len(fraction))
	if negative {
		normalized = "-" + normalized
	}
	return parseSignedMoney(normalized)
}

func fmtFraction(value int64) string {
	text := strconv.FormatInt(value, 10)
	return strings.Repeat("0", 8-len(text)) + text
}
