package main

import (
	"context"
	"encoding/csv"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"ryubot/internal/config"
	"ryubot/internal/pasino"
)

// walletMove transfers the exact amounts listed in a manifest file from each
// user's own Pasino wallet to a target username. The manifest is a CSV with a
// header row: username,coin,amount  (one row per transfer). Amounts come from
// the wallet-balances exports (doge.csv / trx.csv / btt.xlsx / floki.xlsx); a
// row is only included when its balance is > 0.
//
// Wallet balances live only at Pasino (no local ledger to update), so a
// successful transfer needs no database write. Failed transfers leave the
// user's wallet untouched and are reported; processing continues.
//
// Usage: ryubot wallet-move --manifest <csv> [--to kangden69] [--dry-run]
func walletMove(args []string) error {
	flags := flag.NewFlagSet("wallet-move", flag.ExitOnError)
	manifestPath := flags.String("manifest", "", "file CSV manifest: username,coin,amount")
	to := flags.String("to", "kangden69", "username tujuan")
	dryRun := flags.Bool("dry-run", false, "hanya daftarkan rencana, tanpa transfer")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if strings.TrimSpace(*manifestPath) == "" {
		return errors.New("--manifest wajib diisi")
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

	type row struct {
		username string
		coin     string
		amount   string
	}
	var rows []row
	{
		f, err := os.Open(*manifestPath)
		if err != nil {
			return fmt.Errorf("buka manifest: %w", err)
		}
		r := csv.NewReader(f)
		r.FieldsPerRecord = -1
		first := true
		for {
			rec, readErr := r.Read()
			if readErr == io.EOF {
				break
			}
			if readErr != nil {
				f.Close()
				return fmt.Errorf("baca manifest: %w", readErr)
			}
			if first {
				first = false
				continue
			}
			if len(rec) < 3 {
				continue
			}
			username := strings.TrimSpace(rec[0])
			coin := strings.ToUpper(strings.TrimSpace(rec[1]))
			amount := strings.TrimSpace(rec[2])
			if username == "" || amount == "" || amount == "0" {
				continue
			}
			rows = append(rows, row{username, coin, amount})
		}
		f.Close()
	}
	if len(rows) == 0 {
		return errors.New("manifest kosong (tidak ada baris untuk dipindah)")
	}

	targetID, err := queryUserID(ctx, pool, *to)
	if err != nil {
		return fmt.Errorf("id tujuan %q: %w", *to, err)
	}

	fmt.Fprintf(os.Stderr, "wallet-move: %d transfer, dari wallet tiap user -> %s (id %d)\n", len(rows), *to, targetID)
	if *dryRun {
		fmt.Fprintf(os.Stderr, "MODE DRY-RUN: tidak ada transfer.\n")
	}
	moved := make(map[string]float64, 4)
	failed := make([]string, 0, 16)
	for i, r := range rows {
		if *dryRun {
			fmt.Printf("  %4d/%-4d %-16s %-5s %s\n", i+1, len(rows), r.username, r.coin, r.amount)
			continue
		}
		userID, idErr := queryUserID(ctx, pool, r.username)
		if idErr != nil {
			fmt.Fprintf(os.Stderr, "  [%d/%d] %-16s %-5s %s -> GAGAL cari user: %v\n", i+1, len(rows), r.username, r.coin, r.amount, idErr)
			failed = append(failed, fmt.Sprintf("%s %s %s: user tidak ditemukan", r.username, r.coin, r.amount))
			continue
		}
		if userID == targetID {
			fmt.Fprintf(os.Stderr, "  [%d/%d] %-16s %-5s %s -> dilewati (tujuan = user itu sendiri)\n", i+1, len(rows), r.username, r.coin, r.amount)
			continue
		}
		fmt.Fprintf(os.Stderr, "  [%d/%d] %-16s %-5s %s -> %s...\n", i+1, len(rows), r.username, r.coin, r.amount, *to)
		if _, transferErr := provider.Transfer(ctx, userID, r.coin, *to, r.amount); transferErr != nil {
			fmt.Fprintf(os.Stderr, "    GAGAL: %v\n", transferErr)
			failed = append(failed, fmt.Sprintf("%s %s %s: %v", r.username, r.coin, r.amount, transferErr))
			continue
		}
		f, _ := parseFloat(r.amount)
		moved[r.coin] += f
	}

	fmt.Fprintf(os.Stderr, "\nringkasan %d baris (tujuan %s):\n", len(rows), *to)
	for coin, total := range moved {
		fmt.Fprintf(os.Stderr, "  %-5s dikirim: %.8f\n", coin, total)
	}
	if *dryRun {
		fmt.Fprintf(os.Stderr, "  (dry-run: %d baris direncanakan)\n", len(rows))
	}
	if len(failed) > 0 {
		fmt.Fprintf(os.Stderr, "  GAGAL %d baris (wallet user tidak diubah):\n", len(failed))
		for _, f := range failed {
			fmt.Fprintf(os.Stderr, "    - %s\n", f)
		}
	}
	return nil
}