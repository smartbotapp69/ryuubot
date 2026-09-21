package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"ryubot/internal/admin"
	"ryubot/internal/buildinfo"
	"ryubot/internal/config"
	"ryubot/internal/database"
	"ryubot/internal/httpserver"
	"ryubot/internal/legacyimport"
	"ryubot/internal/management"
	"ryubot/internal/pasino"
	"ryubot/internal/trading"
	"ryubot/internal/user"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(os.Args[1:], logger); err != nil {
		logger.Error("command failed", "error", err)
		os.Exit(1)
	}
}

func run(args []string, logger *slog.Logger) error {
	if len(args) == 0 {
		return errors.New("usage: ryubot <serve|worker|init-database|migrate|import-legacy|bootstrap-admin|verify|version>")
	}
	switch args[0] {
	case "serve":
		return serve(logger)
	case "worker":
		return worker(logger)
	case "migrate":
		return migrate()
	case "import-legacy":
		return importLegacy()
	case "init-database":
		cfg, err := config.Load()
		if err != nil {
			return err
		}
		return database.EnsureDatabase(context.Background(), cfg.DatabaseURL, "ryubot_go")
	case "bootstrap-admin":
		if len(args) != 2 {
			return errors.New("usage: ryubot bootstrap-admin <username>; password comes from RYUBOT_BOOTSTRAP_ADMIN_PASSWORD")
		}
		return bootstrapAdmin(args[1])
	case "verify":
		return verifySetup()
	case "version":
		fmt.Printf("%s commit=%s built=%s\n", buildinfo.Version, buildinfo.Commit, buildinfo.BuiltAt)
		return nil
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func serve(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if cfg.AdminUsername == "" || cfg.AdminPassword == "" {
		return errors.New("RYUBOT_ADMIN_USERNAME and RYUBOT_ADMIN_PASSWORD are required for serve")
	}
	store, err := admin.Open(context.Background(), cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("open database: %w", err)
	}
	defer store.Close()
	userStore, err := user.Open(context.Background(), cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("open user store: %w", err)
	}
	defer userStore.Close()
	pasinoClient, err := pasino.Open(context.Background(), cfg.DatabaseURL, cfg)
	if err != nil {
		return fmt.Errorf("open Pasino client: %w", err)
	}
	defer pasinoClient.Close()
	panel := admin.NewHTTP(store, pasinoClient, logger, cfg.Environment == "production", cfg.AdminUsername, cfg.AdminPassword)
	tradingPool, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("open trading database: %w", err)
	}
	defer tradingPool.Close()
	workerID, _ := os.Hostname()
	workerID = fmt.Sprintf("%s-%d", workerID, os.Getpid())
	tradingEngine := trading.NewEngine(tradingPool, pasinoClient, logger, workerID)
	userAPI := user.NewHTTP(userStore, pasinoClient, tradingEngine, logger, cfg.Environment == "production")
	server := httpserver.New(cfg, logger, panel, userAPI)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go tradingEngine.ListenEvents(ctx)
	go func() {
		if runErr := tradingEngine.RunWorker(ctx); runErr != nil && !errors.Is(runErr, context.Canceled) {
			logger.Error("trading worker stopped", "error", runErr)
			stop()
		}
	}()
	go runRetention(ctx, userStore, logger)
	go management.New(tradingPool, pasinoClient, logger).Run(ctx)
	result := make(chan error, 1)
	go func() {
		logger.Info("HTTP server starting", "address", cfg.HTTPAddr, "environment", cfg.Environment)
		result <- server.ListenAndServe()
	}()
	select {
	case err := <-result:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
		defer cancel()
		return server.Shutdown(shutdown)
	}
}

func worker(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()
	client, err := pasino.Open(ctx, cfg.DatabaseURL, cfg)
	if err != nil {
		return err
	}
	defer client.Close()
	host, _ := os.Hostname()
	engine := trading.NewEngine(pool, client, logger, fmt.Sprintf("%s-%d", host, os.Getpid()))
	go management.New(pool, client, logger).Run(ctx)
	logger.Info("trading worker starting")
	return engine.RunWorker(ctx)
}

func runRetention(ctx context.Context, store *user.Store, logger *slog.Logger) {
	cleanup := func() {
		cleanupCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		defer cancel()
		if err := store.CleanupTransientHistory(cleanupCtx); err != nil && !errors.Is(err, context.Canceled) {
			logger.Error("transient history cleanup failed", "error", err)
		}
	}
	cleanup()
	ticker := time.NewTicker(time.Hour)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			cleanup()
		case <-ctx.Done():
			return
		}
	}
}

func migrate() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	pool, err := pgxpool.New(context.Background(), cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()
	return database.Migrate(context.Background(), pool)
}

func bootstrapAdmin(username string) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	password := os.Getenv("RYUBOT_BOOTSTRAP_ADMIN_PASSWORD")
	if password == "" {
		return errors.New("RYUBOT_BOOTSTRAP_ADMIN_PASSWORD is required")
	}
	store, err := admin.Open(context.Background(), cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer store.Close()
	return store.BootstrapAdmin(context.Background(), username, password)
}

func importLegacy() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if cfg.LegacyDatabaseURL == "" {
		return errors.New("RYUBOT_LEGACY_DATABASE_URL is required")
	}
	summary, err := legacyimport.Run(context.Background(), cfg.LegacyDatabaseURL, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	fmt.Printf("import complete: users=%d referrals=%d trading_settings=%d pasino_accounts=%d bonus_balances=%d\n", summary.Users, summary.Referrals, summary.TradingSettings, summary.ProviderAccounts, summary.BonusRows)
	return nil
}

func verifySetup() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("config: %w", err)
	}
	fmt.Printf("config OK (env=%s addr=%s)\n", cfg.Environment, cfg.HTTPAddr)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("database pool: %w", err)
	}
	defer pool.Close()
	if err = pool.Ping(ctx); err != nil {
		return fmt.Errorf("database ping: %w", err)
	}
	var version string
	if err = pool.QueryRow(ctx, `SELECT version()`).Scan(&version); err != nil {
		return fmt.Errorf("database query: %w", err)
	}
	fmt.Printf("database OK (%s)\n", version)

	var migrated int
	if err = pool.QueryRow(ctx, `SELECT count(*) FROM schema_migrations`).Scan(&migrated); err != nil {
		return fmt.Errorf("migration table missing or unreadable: %w", err)
	}
	fmt.Printf("migrations OK (%d applied)\n", migrated)

	if cfg.PasinoAPIKey == "" {
		return errors.New("PASINO_API_KEY is not set")
	}
	if cfg.PasinoCredentialKey == "" {
		return errors.New("PASINO_CREDENTIAL_ENCRYPTION_KEY is not set")
	}
	fmt.Println("pasino credentials OK")

	var missingKeys []string
	requiredSettings := []string{
		"trading.user_percent", "trading.holding_percent", "trading.kangden_percent",
		"trading.fee_exempt_username",
		"referral.level_1_percent", "referral.level_2_percent", "referral.level_3_percent",
		"account.fee_collector_username", "account.kangden_username",
		"owner.cutoff_1", "owner.cutoff_2",
		"owner.nana_percent", "owner.deni_percent", "owner.arya_percent", "owner.operational_percent",
		"account.owner_nana_username", "account.owner_deni_username",
		"account.owner_arya_username", "account.operational_username",
		"subscription.trial_days", "subscription.price_trx",
	}
	rows, err := pool.Query(ctx, `SELECT key FROM app_settings WHERE key=ANY($1) AND value IS NOT NULL AND trim(value)<>''`, requiredSettings)
	if err != nil {
		return fmt.Errorf("app_settings query: %w", err)
	}
	present := map[string]bool{}
	for rows.Next() {
		var k string
		if err = rows.Scan(&k); err != nil {
			rows.Close()
			return err
		}
		present[k] = true
	}
	rows.Close()
	if err = rows.Err(); err != nil {
		return err
	}
	for _, k := range requiredSettings {
		if !present[k] {
			missingKeys = append(missingKeys, k)
		}
	}
	if len(missingKeys) > 0 {
		return fmt.Errorf("app_settings missing or empty: %v", missingKeys)
	}
	fmt.Printf("app_settings OK (%d required keys present)\n", len(requiredSettings))

	fmt.Println("verify OK — system is ready")
	return nil
}
