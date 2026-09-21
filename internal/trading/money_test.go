package trading

import "testing"

func TestMoneyStringPreservesNegativeFraction(t *testing.T) {
	amount, err := ParseSignedMoney("-0.12500000")
	if err != nil {
		t.Fatal(err)
	}
	if got := amount.String(); got != "-0.125" {
		t.Fatalf("got %q", got)
	}
}

func TestProviderMoneyNormalizesToEightDecimals(t *testing.T) {
	amount, err := ParseProviderSignedMoney("0.123456789123")
	if err != nil {
		t.Fatal(err)
	}
	if got := amount.FixedString(); got != "0.12345678" {
		t.Fatalf("got %q", got)
	}
}

func TestAllocateProfitConservesEveryAtomicUnit(t *testing.T) {
	gross, err := ParseMoney("1.00000001")
	if err != nil {
		t.Fatal(err)
	}
	allocation, err := AllocateProfit(gross, AllocationRule{HoldingBPS: 1200, KangdenBPS: 200}, false)
	if err != nil {
		t.Fatal(err)
	}
	if allocation.UserProfit+allocation.HoldingAmount+allocation.KangdenAmount != gross {
		t.Fatal("allocation leaked an atomic unit")
	}
	if allocation.UserProfit.String() != "0.86000001" {
		t.Fatalf("unexpected user amount %s", allocation.UserProfit)
	}
}

func TestAllocateProfitFeeExempt(t *testing.T) {
	gross, _ := ParseMoney("5")
	allocation, err := AllocateProfit(gross, AllocationRule{HoldingBPS: 1200, KangdenBPS: 200}, true)
	if err != nil {
		t.Fatal(err)
	}
	if allocation.UserProfit != gross || allocation.HoldingAmount != 0 || allocation.KangdenAmount != 0 {
		t.Fatal("fee-exempt account was charged")
	}
}
