package trading

import "testing"

func TestAdvanceLossUsesSessionSnapshot(t *testing.T) {
	base, _ := ParseMoney("1")
	state, err := Advance(RuntimeConfig{BaseBet: base, MartingaleOnWin: "0", MartingaleOnLoss: "100"}, RuntimeState{CurrentBet: base}, Loss, Money(-100))
	if err != nil {
		t.Fatal(err)
	}
	if state.CurrentBet.String() != "2" || state.Streak != 1 || state.Losses != 1 {
		t.Fatalf("unexpected state %#v", state)
	}
}

func TestAdvanceBoomOverridesMartingaleAndReset(t *testing.T) {
	base, _ := ParseMoney("1")
	boom, _ := ParseMoney("7.12345678")
	state, err := Advance(RuntimeConfig{BaseBet: base, MartingaleOnLoss: "100", ResetAfterLosses: 2, BoomAfterLosses: 2, BoomLossAmount: boom}, RuntimeState{CurrentBet: Money(200000000), Losses: 1, Streak: 1, LastResult: Loss}, Loss, Money(-200000000))
	if err != nil {
		t.Fatal(err)
	}
	if state.CurrentBet != boom {
		t.Fatalf("boom must be final override: %s", state.CurrentBet.String())
	}
}
