package trading

import (
	"errors"
	"math/big"
)

type RuntimeConfig struct {
	BaseBet                           Money
	MartingaleOnWin, MartingaleOnLoss string
	ResetAfterWins, ResetAfterLosses  int
	BoomAfterWins, BoomAfterLosses    int
	BoomWinAmount, BoomLossAmount     Money
	ProfitSession                     Money
}
type RuntimeState struct {
	CurrentBet, ProfitCycle Money
	Wins, Losses, Streak    int
	LastResult              Result
	ManualReset             bool
}

// Advance applies exactly one settled result to persisted session state.
func Advance(config RuntimeConfig, state RuntimeState, result Result, netProfit Money) (RuntimeState, error) {
	if config.BaseBet <= 0 || state.CurrentBet <= 0 {
		return RuntimeState{}, errors.New("invalid runtime state")
	}
	if result != Win && result != Loss {
		return RuntimeState{}, errors.New("invalid result")
	}
	state.ProfitCycle += netProfit
	if result == Win {
		state.Wins++
		if state.LastResult == Win {
			state.Streak++
		} else {
			state.Streak = 1
		}
		state.LastResult = Win
	} else {
		state.Losses++
		if state.LastResult == Loss {
			state.Streak++
		} else {
			state.Streak = 1
		}
		state.LastResult = Loss
	}
	if state.ManualReset {
		state.CurrentBet = config.BaseBet
		state.Streak = 0
		state.LastResult = ""
	} else {
		reset := false
		if result == Win && config.ResetAfterWins > 0 && state.Streak%config.ResetAfterWins == 0 {
			reset = true
		}
		if result == Loss && config.ResetAfterLosses > 0 && state.Streak%config.ResetAfterLosses == 0 {
			reset = true
		}
		if reset {
			state.CurrentBet = config.BaseBet
		} else {
			rate := config.MartingaleOnLoss
			if result == Win {
				rate = config.MartingaleOnWin
			}
			next, err := applyRate(state.CurrentBet, rate)
			if err != nil {
				return RuntimeState{}, err
			}
			state.CurrentBet = next
		}
		// Sama dengan base: BOOM adalah override terakhir setelah perhitungan
		// reset/martingale pada streak hasil yang baru saja selesai.
		if result == Win && config.BoomAfterWins > 0 && state.Streak == config.BoomAfterWins && config.BoomWinAmount > 0 {
			state.CurrentBet = config.BoomWinAmount
		}
		if result == Loss && config.BoomAfterLosses > 0 && state.Streak == config.BoomAfterLosses && config.BoomLossAmount > 0 {
			state.CurrentBet = config.BoomLossAmount
		}
	}
	if config.ProfitSession > 0 && state.ProfitCycle >= config.ProfitSession {
		state.CurrentBet = config.BaseBet
		state.ProfitCycle = 0
	}
	return state, nil
}

func applyRate(amount Money, percent string) (Money, error) {
	rate, ok := new(big.Rat).SetString(percent)
	if !ok || rate.Sign() < 0 {
		return 0, errors.New("martingale rate invalid")
	}
	multiplier := new(big.Rat).Add(big.NewRat(100, 1), rate)
	multiplier.Quo(multiplier, big.NewRat(100, 1))
	value := new(big.Rat).Mul(big.NewRat(int64(amount), 1), multiplier)
	integer := new(big.Int).Quo(value.Num(), value.Denom())
	if !integer.IsInt64() || integer.Sign() <= 0 {
		return 0, errors.New("next bet invalid")
	}
	return Money(integer.Int64()), nil
}
