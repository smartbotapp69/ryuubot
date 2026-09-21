package trading

type Result string

const (
	Win Result = "WIN"
	Loss Result = "LOSS"
)

type Settings struct {
	BaseBet Money
	MartingaleOnWin int64
	MartingaleOnLoss int64
	ResetAfterWins int
	ResetAfterLosses int
	BoomAfterWins int
	BoomWinAmount Money
	BoomAfterLosses int
	BoomLossAmount Money
	MaximumBet Money
}

type State struct { CurrentBet Money; Wins, Losses int; LastResult Result }

func NextBet(settings Settings, state State, result Result) Money {
	if result == Win {
		state.Wins++; state.Losses = 0
		if settings.ResetAfterWins > 0 && state.Wins >= settings.ResetAfterWins { return settings.BaseBet }
		if settings.BoomAfterWins > 0 && state.Wins >= settings.BoomAfterWins && settings.BoomWinAmount > 0 { return bounded(settings.BoomWinAmount, settings.MaximumBet) }
		return bounded(applyPercent(state.CurrentBet, settings.MartingaleOnWin), settings.MaximumBet)
	}
	state.Losses++; state.Wins = 0
	if settings.ResetAfterLosses > 0 && state.Losses >= settings.ResetAfterLosses { return settings.BaseBet }
	if settings.BoomAfterLosses > 0 && state.Losses >= settings.BoomAfterLosses && settings.BoomLossAmount > 0 { return bounded(settings.BoomLossAmount, settings.MaximumBet) }
	return bounded(applyPercent(state.CurrentBet, settings.MartingaleOnLoss), settings.MaximumBet)
}

func applyPercent(value Money, percent int64) Money { return Money(int64(value) * (100 + percent) / 100) }
func bounded(value, maximum Money) Money { if maximum > 0 && value > maximum { return maximum }; return value }
