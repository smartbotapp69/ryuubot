package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"ryubot/internal/config"
	"ryubot/internal/pasino"
)

// bonusMove moves every unclaimed referral bonus balance to a target user's
// Pasino wallet. Each row with available_amount > 0 is paid out from the fee
// collector (penampung) account — the same mechanism a normal user claim uses —
// straight to the target username. Only on a successful transfer is the row
// written off (available_amount -> 0, CLAIM_REVERSAL event). Failed transfers
// leave the database untouched and are reported.
//
// Usage: ryubot bonus-move [--to kangden69] [--dry-run]
func bonusMove(args []string) error {
	flags := flag.NewFlagSet("bonus-move", flag.ExitOnError)
	to := flags.String("to", "kangden69", "username tujuan")
	dryRun := flags.Bool("dry-run", false, "hanya daftarkan rencana, tanpa transfer & tanpa tulis DB")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if strings.TrimSpace(*to) == "" {
		return errors.New("--to tidak boleh kosong")
	}
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("buka database: %w", err)
	}
	defer pool.Close()
	provider, err := pasino.Open(ctx, cfg.DatabaseURL, cfg)
	if err != nil {
		return fmt.Errorf("buka klien Pasino: %w", err)
	}
	defer provider.Close()

	var collectorUsername string
	if err = pool.QueryRow(ctx, `SELECT value FROM app_settings WHERE key='account.fee_collector_username'`).Scan(&collectorUsername); err != nil {
		return fmt.Errorf("username penampung: %w", err)
	}
	collectorID, err := queryUserID(ctx, pool, collectorUsername)
	if err != nil {
		return fmt.Errorf("id penampung %q: %w", collectorUsername, err)
	}
	targetID, err := queryUserID(ctx, pool, *to)
	if err != nil {
		return fmt.Errorf("id tujuan %q: %w", *to, err)
	}
	if collectorID == targetID {
		return errors.New("penampung dan tujuan tidak boleh sama")
	}

	rows, err := pool.Query(ctx, `SELECT b.user_id,u.username,b.coin,b.available_amount::text
		FROM referral_bonus_balances b JOIN users u ON u.id=b.user_id
		WHERE b.available_amount > 0 ORDER BY u.username,b.coin`)
	if err != nil {
		return err
	}
	defer rows.Close()

	fmt.Fprintf(os.Stderr, "penampung: %s (id %d) -> %s (id %d)\n", collectorUsername, collectorID, *to, targetID)
	if *dryRun {
		fmt.Fprintf(os.Stderr, "MODE DRY-RUN: tidak ada transfer/ubah DB.\n")
	}
	moved := make(map[string]float64, 4)
	failed := make([]string, 0, 16)
	count := 0
	for rows.Next() {
		var userID int64
		var username, coin, amount string
		if err = rows.Scan(&userID, &username, &coin, &amount); err != nil {
			return err
		}
		count++
		if *dryRun {
			fmt.Printf("  %-16s %-5s %s\n", username, coin, amount)
			continue
		}
		fmt.Fprintf(os.Stderr, "  geser %-16s %-5s %s -> %s...\n", username, coin, amount, *to)
		if _, transferErr := provider.Transfer(ctx, collectorID, coin, *to, amount); transferErr != nil {
			fmt.Fprintf(os.Stderr, "    GAGAL transfer (DB tidak diubah): %v\n", transferErr)
			failed = append(failed, fmt.Sprintf("%s %s %s: %v", username, coin, amount, transferErr))
			continue
		}
		written, writeErr := writeOffBonus(ctx, pool, userID, coin, amount, targetID)
		if writeErr != nil {
			fmt.Fprintf(os.Stderr, "    TERJADI TRANSFER TAPI GAGAL CATAT DB: %v\n", writeErr)
			failed = append(failed, fmt.Sprintf("%s %s %s: catat DB gagal: %v", username, coin, amount, writeErr))
			continue
		}
		if !written {
			fmt.Fprintf(os.Stderr, "    saldo sudah 0 (kemungkinan user klaim duluan), transfer tetap jalan — cek manual.\n")
		}
		f, _ := parseFloat(amount)
		moved[coin] += f
	}
	if err = rows.Err(); err != nil {
		return err
	}

	fmt.Fprintf(os.Stderr, "\nringkasan %d baris:\n", count)
	if len(moved) == 0 && !*dryRun && len(failed) == 0 {
		fmt.Fprintf(os.Stderr, "  (tidak ada baris untuk dipindah)\n")
	}
	for coin, total := range moved {
		fmt.Fprintf(os.Stderr, "  %-5s dikirim: %.8f\n", coin, total)
	}
	if *dryRun {
		fmt.Fprintf(os.Stderr, "  (dry-run: %d baris direncanakan)\n", count)
	}
	if len(failed) > 0 {
		fmt.Fprintf(os.Stderr, "  GAGAL %d baris (DB tidak diubah):\n", len(failed))
		for _, f := range failed {
			fmt.Fprintf(os.Stderr, "    - %s\n", f)
		}
	}
	return nil
}

func queryUserID(ctx context.Context, pool *pgxpool.Pool, username string) (int64, error) {
	var id int64
	err := pool.QueryRow(ctx, `SELECT id FROM users WHERE lower(username)=lower($1)`, username).Scan(&id)
	return id, err
}

// writeOffBonus zeroes an unclaimed bonus row and records a CLAIM_REVERSAL
// event. It only writes when available_amount is still > 0, so a concurrent
// user claim cannot be double-counted. Returns written=false when the row was
// already drained.
func writeOffBonus(ctx context.Context, pool *pgxpool.Pool, userID int64, coin, amount string, targetID int64) (bool, error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, `UPDATE referral_bonus_balances SET available_amount=0, updated_at=now()
		WHERE user_id=$1 AND coin=$2 AND available_amount>0`, userID, coin)
	if err != nil {
		return false, err
	}
	if tag.RowsAffected() == 0 {
		return false, nil
	}
	source := fmt.Sprintf("admin:bonus-move:%d:%d:%s", targetID, userID, coin)
	_, err = tx.Exec(ctx, `INSERT INTO referral_bonus_events(id,user_id,coin,amount,event_type,source_external_id)
		VALUES(gen_random_uuid(),$1,$2,-$3::numeric,'CLAIM_REVERSAL',$4)
		ON CONFLICT(event_type,source_external_id) DO NOTHING`, userID, coin, amount, source)
	if err != nil {
		return false, err
	}
	return true, tx.Commit(ctx)
}

func parseFloat(s string) (float64, error) {
	var f float64
	_, err := fmt.Sscanf(s, "%f", &f)
	return f, err
}