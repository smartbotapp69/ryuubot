package admin

import (
	"context"
	"errors"
	"math/big"
	"regexp"
	"time"
)

type Setting struct {
	Key, Category, Label, Value, Type string
	Minimum, Maximum                  *string
}

func (s *Store) Settings(ctx context.Context, category string) ([]Setting, error) {
	rows, err := s.pool.Query(ctx, `SELECT key,category,label,value,value_type,minimum::text,maximum::text FROM app_settings WHERE category=$1 ORDER BY sort_order,key`, category)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []Setting
	for rows.Next() {
		var item Setting
		if err = rows.Scan(&item.Key, &item.Category, &item.Label, &item.Value, &item.Type, &item.Minimum, &item.Maximum); err != nil {
			return nil, err
		}
		result = append(result, item)
	}
	return result, rows.Err()
}
func (s *Store) SaveSettings(ctx context.Context, adminID int64, category string, values map[string]string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	for key, value := range values {
		var old, kind string
		var min, max *string
		if err = tx.QueryRow(ctx, `SELECT value,value_type,minimum::text,maximum::text FROM app_settings WHERE key=$1 AND category=$2 FOR UPDATE`, key, category).Scan(&old, &kind, &min, &max); err != nil {
			return err
		}
		if err = validateSetting(kind, value, min, max); err != nil {
			return errors.New(key + ": " + err.Error())
		}
		if old == value {
			continue
		}
		if _, err = tx.Exec(ctx, `UPDATE app_settings SET value=$2,updated_by=nullif($3,0),updated_at=now() WHERE key=$1`, key, value, adminID); err != nil {
			return err
		}
		if _, err = tx.Exec(ctx, `INSERT INTO app_settings_audit(setting_key,old_value,new_value,admin_user_id) VALUES($1,$2,$3,nullif($4,0))`, key, old, value, adminID); err != nil {
			return err
		}
	}
	var valid bool
	switch category {
	case "trading":
		err = tx.QueryRow(ctx, `SELECT (SELECT value::numeric FROM app_settings WHERE key='trading.user_percent')+(SELECT value::numeric FROM app_settings WHERE key='trading.holding_percent')+(SELECT value::numeric FROM app_settings WHERE key='trading.kangden_percent')=100`).Scan(&valid)
	case "referral":
		err = tx.QueryRow(ctx, `SELECT (SELECT value::numeric FROM app_settings WHERE key='referral.level_1_percent')+(SELECT value::numeric FROM app_settings WHERE key='referral.level_2_percent')+(SELECT value::numeric FROM app_settings WHERE key='referral.level_3_percent')<=(SELECT value::numeric FROM app_settings WHERE key='trading.holding_percent')`).Scan(&valid)
	case "subscription":
		err = tx.QueryRow(ctx, `SELECT (SELECT value::numeric FROM app_settings WHERE key='subscription.upline_trx')+(SELECT value::numeric FROM app_settings WHERE key='subscription.management_trx')=(SELECT value::numeric FROM app_settings WHERE key='subscription.price_trx')`).Scan(&valid)
	case "owner":
		err = tx.QueryRow(ctx, `SELECT (SELECT value::numeric FROM app_settings WHERE key='owner.nana_percent')+(SELECT value::numeric FROM app_settings WHERE key='owner.deni_percent')+(SELECT value::numeric FROM app_settings WHERE key='owner.arya_percent')+(SELECT value::numeric FROM app_settings WHERE key='owner.operational_percent')=100`).Scan(&valid)
	default:
		valid = true
	}
	if err != nil {
		return err
	}
	if !valid {
		return errors.New("total pembagian tidak valid")
	}
	return tx.Commit(ctx)
}
func validateSetting(kind, value string, min, max *string) error {
	switch kind {
	case "decimal", "integer":
		n, ok := new(big.Rat).SetString(value)
		if !ok {
			return errors.New("angka tidak valid")
		}
		if kind == "integer" && !n.IsInt() {
			return errors.New("harus bilangan bulat")
		}
		if min != nil {
			m, _ := new(big.Rat).SetString(*min)
			if n.Cmp(m) < 0 {
				return errors.New("di bawah minimum")
			}
		}
		if max != nil {
			m, _ := new(big.Rat).SetString(*max)
			if n.Cmp(m) > 0 {
				return errors.New("di atas maksimum")
			}
		}
	case "time":
		if _, err := time.Parse("15:04", value); err != nil {
			return errors.New("waktu tidak valid")
		}
	case "boolean":
		if value != "true" && value != "false" {
			return errors.New("boolean tidak valid")
		}
	case "text":
		if !regexp.MustCompile(`^[A-Za-z0-9_.@-]{1,100}$`).MatchString(value) {
			return errors.New("teks tidak valid")
		}
	default:
		return errors.New("tipe tidak dikenal")
	}
	return nil
}
