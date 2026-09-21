package trading

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// BusinessRules is loaded from the admin-managed app_settings table when a
// session starts. The serialized value is stored in trading_sessions so later
// admin changes can never rewrite the meaning of an existing roll.
type BusinessRules struct {
	UserBPS           int64   `json:"user_bps"`
	HoldingBPS        int64   `json:"holding_bps"`
	KangdenBPS        int64   `json:"kangden_bps"`
	FeeExemptUsername string  `json:"fee_exempt_username"`
	ReferralBPS       []int64 `json:"referral_bps"`
	MinimumBet        Money   `json:"minimum_bet_units"`
}

func LoadBusinessRules(ctx context.Context, pool *pgxpool.Pool, coin string) (BusinessRules, json.RawMessage, error) {
	keys := []string{
		"trading.user_percent", "trading.holding_percent", "trading.kangden_percent",
		"trading.fee_exempt_username", "referral.level_1_percent", "referral.level_2_percent",
		"referral.level_3_percent", "coin." + strings.ToUpper(coin) + ".minimum_bet",
	}
	rows, err := pool.Query(ctx, `SELECT key,value FROM app_settings WHERE key=ANY($1)`, keys)
	if err != nil {
		return BusinessRules{}, nil, err
	}
	defer rows.Close()
	values := make(map[string]string, len(keys))
	for rows.Next() {
		var key, value string
		if err = rows.Scan(&key, &value); err != nil {
			return BusinessRules{}, nil, err
		}
		values[key] = value
	}
	if err = rows.Err(); err != nil {
		return BusinessRules{}, nil, err
	}
	for _, key := range keys {
		if strings.TrimSpace(values[key]) == "" {
			return BusinessRules{}, nil, fmt.Errorf("pengaturan admin %s belum tersedia", key)
		}
	}
	var rules BusinessRules
	if rules.UserBPS, err = ParseBPS(values[keys[0]]); err != nil {
		return BusinessRules{}, nil, err
	}
	if rules.HoldingBPS, err = ParseBPS(values[keys[1]]); err != nil {
		return BusinessRules{}, nil, err
	}
	if rules.KangdenBPS, err = ParseBPS(values[keys[2]]); err != nil {
		return BusinessRules{}, nil, err
	}
	rules.FeeExemptUsername = strings.TrimSpace(values[keys[3]])
	for _, key := range keys[4:7] {
		bps, parseErr := ParseBPS(values[key])
		if parseErr != nil {
			return BusinessRules{}, nil, parseErr
		}
		rules.ReferralBPS = append(rules.ReferralBPS, bps)
	}
	if rules.MinimumBet, err = ParseMoney(values[keys[7]]); err != nil {
		return BusinessRules{}, nil, err
	}
	if rules.UserBPS+rules.HoldingBPS+rules.KangdenBPS != 10_000 {
		return BusinessRules{}, nil, errors.New("total pembagian profit admin harus tepat 100%")
	}
	var referralTotal int64
	for _, bps := range rules.ReferralBPS {
		referralTotal += bps
	}
	if referralTotal > rules.HoldingBPS {
		return BusinessRules{}, nil, errors.New("total referral melebihi bagian akun penampung")
	}
	snapshot, err := json.Marshal(rules)
	if err != nil {
		return BusinessRules{}, nil, err
	}
	return rules, snapshot, nil
}
