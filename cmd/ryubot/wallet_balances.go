package main

import (
	"context"
	"encoding/csv"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"text/tabwriter"

	"github.com/jackc/pgx/v5/pgxpool"
	"ryubot/internal/config"
	"ryubot/internal/pasino"
)

type userRow struct {
	id, username, email, status string
	expires, trial, created     string
	wallet                      map[string]string
	note                        string
}

// walletBalances lists every user together with their live Pasino wallet
// balances. The balances come directly from the Pasino provider socket (never
// from the local database), so the output shows the real money per account.
//
// Usage: ryubot wallet-balances [--coin TRX,DOGE,FLOKI,BTT] [--limit N] [--workers N] [--csv] [--no-balance]
func walletBalances(args []string) error {
	flags := flag.NewFlagSet("wallet-balances", flag.ExitOnError)
	coinList := flags.String("coin", "TRX,DOGE,FLOKI,BTT", "daftar coin dipisah koma")
	limit := flags.Int("limit", 0, "batas jumlah user (0 = semua)")
	workers := flags.Int("workers", 4, "jumlah user yang dicek saldo sekaligus")
	csvOut := flags.Bool("csv", false, "output CSV (untuk Excel)")
	noBalance := flags.Bool("no-balance", false, "hanya data user dari DB, tanpa cek saldo Pasino")
	usernameFilter := flags.String("username", "", "hanya user dengan username ini")
	if err := flags.Parse(args); err != nil {
		return err
	}
	coins := splitCoins(*coinList)
	if len(coins) == 0 {
		return errors.New("--coin tidak boleh kosong")
	}
	if *workers < 1 {
		return errors.New("--workers minimal 1")
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
	var provider *pasino.Client
	if !*noBalance {
		provider, err = pasino.Open(ctx, cfg.DatabaseURL, cfg)
		if err != nil {
			return fmt.Errorf("buka klien Pasino: %w", err)
		}
		defer provider.Close()
	}

	query := `SELECT id::text,username,email,status,
		coalesce(to_char(subscription_expires_at,'YYYY-MM-DD HH24:MI'),'-'),
		coalesce(to_char(subscription_trial_ends_at,'YYYY-MM-DD HH24:MI'),'-'),
		coalesce(to_char(created_at,'YYYY-MM-DD HH24:MI'),'-')
		FROM users`
	var queryArgs []any
	if *usernameFilter != "" {
		query += ` WHERE lower(username)=lower($1)`
		queryArgs = append(queryArgs, *usernameFilter)
	}
	query += ` ORDER BY id`
	rows, err := pool.Query(ctx, query, queryArgs...)
	if err != nil {
		return err
	}
	defer rows.Close()

	var users []userRow
	for rows.Next() {
		if *limit > 0 && len(users) >= *limit {
			break
		}
		var u userRow
		if err = rows.Scan(&u.id, &u.username, &u.email, &u.status, &u.expires, &u.trial, &u.created); err != nil {
			return err
		}
		users = append(users, u)
	}
	if err = rows.Err(); err != nil {
		return err
	}

	if provider != nil {
		if err = fetchAllBalances(ctx, provider, users, coins, *workers); err != nil {
			return err
		}
	}

	if *csvOut {
		return printWalletCSV(os.Stdout, users, coins)
	}
	printWalletTable(os.Stdout, users, coins)
	return nil
}

// fetchAllBalances reads live Pasino balances for every user in parallel
// (--workers goroutines). Balances are read one coin at a time because the
// Pasino socket answers a single get_balance per round-trip and ignores bursts
// of several requests at once (the batch Balances call always times out).
func fetchAllBalances(ctx context.Context, provider *pasino.Client, users []userRow, coins []string, workers int) error {
	fmt.Fprintf(os.Stderr, "memeriksa saldo %d user (%d coin, %d worker)...\n", len(users), len(coins), workers)
	jobs := make(chan int)
	var wg sync.WaitGroup
	var doneCount, failCount atomic.Int64
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for index := range jobs {
				u := &users[index]
				done := doneCount.Add(1)
				fmt.Fprintf(os.Stderr, "  [%d/%d] memeriksa %s (id %s)...\n", done, len(users), u.username, u.id)
				userID, _ := strconv.ParseInt(u.id, 10, 64)
				balances := make(map[string]string, len(coins))
				for _, coin := range coins {
					value, balanceErr := provider.Balance(ctx, userID, coin)
					if balanceErr != nil {
						u.note = fmt.Sprintf("saldo %s gagal: %v", coin, balanceErr)
						failCount.Add(1)
						break
					}
					balances[coin] = value
				}
				if u.note == "" {
					u.wallet = balances
				}
			}
		}()
	}
	go func() {
		for index := range users {
			jobs <- index
		}
		close(jobs)
	}()
	wg.Wait()
	failed := failCount.Load()
	if failed > 0 {
		fmt.Fprintf(os.Stderr, "selesai: %d user dicek, %d user gagal (lihat kolom NOTE).\n", len(users), failed)
	} else {
		fmt.Fprintf(os.Stderr, "selesai: %d user dicek, semua berhasil.\n", len(users))
	}
	return nil
}

func splitCoins(raw string) []string {
	var coins []string
	for _, c := range strings.Split(raw, ",") {
		if c = strings.ToUpper(strings.TrimSpace(c)); c != "" {
			coins = append(coins, c)
		}
	}
	return coins
}

func printWalletTable(w io.Writer, users []userRow, coins []string) {
	if len(users) == 0 {
		fmt.Fprintln(w, "(tidak ada user)")
		return
	}
	tw := tabwriter.NewWriter(w, 0, 4, 2, ' ', 0)
	header := "ID\tUSERNAME\tSTATUS\tSUB_EXPIRES\tTRIAL_END\tCREATED"
	for _, c := range coins {
		header += "\t" + c
	}
	header += "\tNOTE"
	fmt.Fprintln(tw, header)
	for _, u := range users {
		line := strings.Join([]string{u.id, u.username, u.status, u.expires, u.trial, u.created}, "\t")
		for _, c := range coins {
			value, ok := u.wallet[c]
			if !ok {
				value = "-"
			}
			line += "\t" + value
		}
		line += "\t" + u.note
		fmt.Fprintln(tw, line)
	}
	_ = tw.Flush()
}

func printWalletCSV(w io.Writer, users []userRow, coins []string) error {
	cw := csv.NewWriter(w)
	header := []string{"id", "username", "email", "status", "subscription_expires_at", "subscription_trial_ends_at", "created_at"}
	for _, c := range coins {
		header = append(header, strings.ToLower(c))
	}
	header = append(header, "note")
	if err := cw.Write(header); err != nil {
		return err
	}
	for _, u := range users {
		row := []string{u.id, u.username, u.email, u.status, u.expires, u.trial, u.created}
		for _, c := range coins {
			value, ok := u.wallet[c]
			if !ok {
				value = ""
			}
			row = append(row, value)
		}
		row = append(row, u.note)
		if err := cw.Write(row); err != nil {
			return err
		}
	}
	cw.Flush()
	return cw.Error()
}