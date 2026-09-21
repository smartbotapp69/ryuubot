package trading

import "testing"

func TestBuildBetPayloadUsesExactChanceAndProfit(t *testing.T) {
	amount, _ := ParseMoney("1")
	payload, expected, err := BuildBetPayload(amount, BetConfig{Coin: "TRX", ChanceMin: "50", ChanceMax: "50"})
	if err != nil {
		t.Fatal(err)
	}
	if payload.WinningChance != "50.00" {
		t.Fatalf("chance %s", payload.WinningChance)
	}
	if payload.Payout != "1.90000" {
		t.Fatalf("payout %s", payload.Payout)
	}
	if expected.String() != "0.9" || payload.BetAmount != "1.00000000" || payload.Profit != "0.90000000" {
		t.Fatalf("amount=%s profit=%s", payload.BetAmount, payload.Profit)
	}
}
