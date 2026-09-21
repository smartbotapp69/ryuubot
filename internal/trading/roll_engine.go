package trading

import "fmt"

// BotRollConfiguration is the immutable configuration used by one active bot
// session. Amounts are provider atomic units, never float values.
// A changed user setting is saved as the configuration for the next session.
type BotRollConfiguration struct {
	Coin                 string
	BaseBetUnits         int64
	MartingaleBps        int64 // 20_000 means 2x, 15_000 means 1.5x.
	MaxLossStreak        int
	StopProfitUnits      int64 // zero disables the limit.
	StopLossUnits        int64 // zero disables the limit.
	ResetBetAfterWin     bool
}

func (c BotRollConfiguration) Validate() error {
	if c.Coin == "" {
		return fmt.Errorf("coin is required")
	}
	if c.BaseBetUnits <= 0 {
		return fmt.Errorf("base bet must be greater than zero")
	}
	if c.MartingaleBps < 10_000 {
		return fmt.Errorf("martingale multiplier must be at least 1x")
	}
	if c.MaxLossStreak < 0 {
		return fmt.Errorf("max loss streak cannot be negative")
	}
	if c.StopProfitUnits < 0 || c.StopLossUnits < 0 {
		return fmt.Errorf("stop limits cannot be negative")
	}
	return nil
}

// BotRollState is persisted after every settled provider bet. NetProfitUnits
// must be the provider settlement after all applicable trading fees.
type BotRollState struct {
	CurrentBetUnits int64
	NetProfitUnits  int64
	LossStreak      int
}

type SettledRoll struct {
	NetProfitUnits int64
	Won            bool
}

type RollDecision struct {
	NextBetUnits int64
	Stop         bool
	StopReason   string
}

// ApplySettledRoll produces the only valid next-roll decision. It deliberately
// does not mutate configuration: a session always runs with its saved snapshot.
func ApplySettledRoll(config BotRollConfiguration, state BotRollState, settled SettledRoll) (BotRollState, RollDecision, error) {
	if err := config.Validate(); err != nil {
		return BotRollState{}, RollDecision{}, err
	}
	if state.CurrentBetUnits <= 0 {
		state.CurrentBetUnits = config.BaseBetUnits
	}

	state.NetProfitUnits += settled.NetProfitUnits
	if settled.Won {
		state.LossStreak = 0
		if config.ResetBetAfterWin {
			state.CurrentBetUnits = config.BaseBetUnits
		}
	} else {
		state.LossStreak++
		next, err := multiplyUnits(state.CurrentBetUnits, config.MartingaleBps)
		if err != nil {
			return BotRollState{}, RollDecision{}, err
		}
		state.CurrentBetUnits = next
	}

	if config.StopProfitUnits > 0 && state.NetProfitUnits >= config.StopProfitUnits {
		return state, RollDecision{Stop: true, StopReason: "target_profit_reached"}, nil
	}
	if config.StopLossUnits > 0 && -state.NetProfitUnits >= config.StopLossUnits {
		return state, RollDecision{Stop: true, StopReason: "stop_loss_reached"}, nil
	}
	if config.MaxLossStreak > 0 && state.LossStreak >= config.MaxLossStreak {
		return state, RollDecision{Stop: true, StopReason: "max_loss_streak_reached"}, nil
	}
	return state, RollDecision{NextBetUnits: state.CurrentBetUnits}, nil
}

func multiplyUnits(amount, bps int64) (int64, error) {
	if amount <= 0 || bps <= 0 || amount > (1<<63-1)/bps {
		return 0, fmt.Errorf("next bet exceeds supported amount")
	}
	// Round upward so the calculated recovery bet is never below the configured
	// multiplier because of atomic-unit truncation.
	return (amount*bps + 9_999) / 10_000, nil
}
