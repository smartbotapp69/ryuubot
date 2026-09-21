package trading

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"math/big"
	"strings"
)

type BetConfig struct{ Coin, ChanceMin, ChanceMax string }
type BetPayload struct {
	Method        string `json:"method"`
	BetAmount     string `json:"bet_amt"`
	Coin          string `json:"coin"`
	ClientSeed    string `json:"client_seed"`
	Type          int    `json:"type"`
	Payout        string `json:"payout"`
	WinningChance string `json:"winning_chance"`
	Profit        string `json:"profit"`
}

// BuildBetPayload follows the existing Pasino payload contract while retaining
// exact 0.01 chance increments and atomic-unit profit arithmetic.
func BuildBetPayload(amount Money, config BetConfig) (BetPayload, Money, error) {
	if amount <= 0 || strings.TrimSpace(config.Coin) == "" {
		return BetPayload{}, 0, errors.New("taruhan tidak valid")
	}
	min, err := chanceBPS(config.ChanceMin)
	if err != nil {
		return BetPayload{}, 0, err
	}
	max, err := chanceBPS(config.ChanceMax)
	if err != nil {
		return BetPayload{}, 0, err
	}
	if min <= 0 || max < min || max >= 10_000 {
		return BetPayload{}, 0, errors.New("rentang chance tidak valid")
	}
	delta, err := rand.Int(rand.Reader, big.NewInt(max-min+1))
	if err != nil {
		return BetPayload{}, 0, err
	}
	chance := min + delta.Int64()
	// This is the same 95% payout formula used by the Node runner, scaled to
	// five decimal places. The division is intentionally floored.
	payoutScaled := int64(95*100*100000) / chance
	expectedValue := new(big.Int).Mul(big.NewInt(int64(amount)), big.NewInt(payoutScaled-100000))
	expectedValue.Quo(expectedValue, big.NewInt(100000))
	if !expectedValue.IsInt64() {
		return BetPayload{}, 0, errors.New("profit taruhan di luar batas")
	}
	expected := Money(expectedValue.Int64())
	seed := make([]byte, 16)
	if _, err = rand.Read(seed); err != nil {
		return BetPayload{}, 0, err
	}
	side, err := rand.Int(rand.Reader, big.NewInt(2))
	if err != nil {
		return BetPayload{}, 0, err
	}
	payoutWhole, payoutFraction := payoutScaled/100000, payoutScaled%100000
	return BetPayload{Method: "place_bet", BetAmount: amount.FixedString(), Coin: strings.ToUpper(config.Coin), ClientSeed: hex.EncodeToString(seed), Type: int(side.Int64()) + 1, Payout: formatDecimal(payoutWhole, payoutFraction, 5), WinningChance: formatDecimal(chance/100, chance%100, 2), Profit: expected.FixedString()}, expected, nil
}

func chanceBPS(value string) (int64, error) {
	ratio, ok := new(big.Rat).SetString(strings.TrimSpace(value))
	if !ok {
		return 0, errors.New("chance tidak valid")
	}
	ratio.Mul(ratio, big.NewRat(100, 1))
	if !ratio.IsInt() || !ratio.Num().IsInt64() {
		return 0, errors.New("chance harus kelipatan 0.01")
	}
	return ratio.Num().Int64(), nil
}
func formatDecimal(whole, fraction int64, places int) string {
	digits := new(big.Int).SetInt64(fraction).String()
	return new(big.Int).SetInt64(whole).String() + "." + strings.Repeat("0", places-len(digits)) + digits
}
