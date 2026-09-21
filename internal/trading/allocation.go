package trading

import (
	"errors"
	"math/big"
	"strings"
)

// AllocationRule is saved into each session's rule_snapshot. Percentages are
// basis points: 1200 means 12%, so no float arithmetic enters the ledger.
type AllocationRule struct {
	HoldingBPS int64
	KangdenBPS int64
	FeeExemptUsername string
}

type Allocation struct {
	GrossProfit Money
	UserProfit Money
	HoldingAmount Money
	KangdenAmount Money
}

func ParseBPS(percent string) (int64, error) {
	raw := strings.TrimSpace(percent)
	ratio, ok := new(big.Rat).SetString(raw)
	if !ok || ratio.Sign() < 0 { return 0, errors.New("persentase tidak valid") }
	ratio.Mul(ratio, big.NewRat(100, 1))
	if !ratio.IsInt() || !ratio.Num().IsInt64() || ratio.Num().Int64() > 10_000 { return 0, errors.New("persentase harus maksimal 100 dengan dua desimal") }
	return ratio.Num().Int64(), nil
}

func (r AllocationRule) Validate() error {
	if r.HoldingBPS < 0 || r.KangdenBPS < 0 || r.HoldingBPS+r.KangdenBPS > 10_000 { return errors.New("pembagian fee tidak valid") }
	return nil
}

// AllocateProfit keeps any atomic-unit rounding remainder with the user; that
// guarantees gross = user + holding + kangden exactly for every settlement.
func AllocateProfit(gross Money, rule AllocationRule, feeExempt bool) (Allocation, error) {
	if err := rule.Validate(); err != nil { return Allocation{},err }
	result := Allocation{GrossProfit:gross, UserProfit:gross}
	if gross <= 0 || feeExempt { return result,nil }
	var err error
	if result.HoldingAmount, err = percentageOf(gross, rule.HoldingBPS); err != nil { return Allocation{},err }
	if result.KangdenAmount, err = percentageOf(gross, rule.KangdenBPS); err != nil { return Allocation{},err }
	result.UserProfit = gross - result.HoldingAmount - result.KangdenAmount
	return result,nil
}

func percentageOf(amount Money, basisPoints int64) (Money, error) {
	value := new(big.Int).Mul(big.NewInt(int64(amount)), big.NewInt(basisPoints))
	value.Quo(value, big.NewInt(10_000))
	if !value.IsInt64() { return 0, errors.New("nominal pembagian di luar batas") }
	return Money(value.Int64()), nil
}
