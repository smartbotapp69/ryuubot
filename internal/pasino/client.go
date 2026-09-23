// Package pasino implements the verified Pasino HTTP and WebSocket contract.
// It never persists a wallet balance: provider data remains the source of
// truth until a trading settlement is recorded in the local ledger.
package pasino

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"nhooyr.io/websocket"
	"nhooyr.io/websocket/wsjson"
	"ryubot/internal/config"
)

var ErrUnauthorized = errors.New("Pasino session is not authorized")

// pasinoUserAgent makes pasino API calls look like an ordinary browser. The
// Pasino edge (Cloudflare) can challenge the stock Go user agent from
// datacenter IPs and reply with an HTML block page instead of JSON.
const pasinoUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

type OutcomeUnknownError struct{ Cause error }

func (e *OutcomeUnknownError) Error() string {
	return "outcome Pasino tidak dapat dipastikan: " + e.Cause.Error()
}
func (e *OutcomeUnknownError) Unwrap() error { return e.Cause }

type Client struct {
	pool          *pgxpool.Pool
	apiBaseURL    string
	socketURL     string
	apiKey        string
	credentialKey string
	referrer      string
	http          *http.Client
	dial          *websocket.DialOptions
	socketsMu     sync.Mutex
	sockets       map[int64]*providerSocket
	connectLocks  map[int64]*sync.Mutex
	reconnecting  map[int64]bool
	shutdown      chan struct{}
	shutdownOnce  sync.Once
	balanceMu     sync.Mutex
	balanceCache  map[string]cachedBalance
	lastKnown     map[string]string
	balanceFlight map[string]*balanceFlight
}

type cachedBalance struct {
	value     string
	expiresAt time.Time
}

type balanceFlight struct {
	done  chan struct{}
	value string
	err   error
}

type providerSocket struct {
	connection *websocket.Conn
	mu         sync.Mutex
	incoming   chan json.RawMessage
	readErr    chan error
	stop       chan struct{}
	stopOnce   sync.Once
}

func Open(ctx context.Context, databaseURL string, cfg config.Config) (*Client, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, err
	}
	check, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err = pool.Ping(check); err != nil {
		pool.Close()
		return nil, err
	}
	httpClient := &http.Client{Timeout: 10 * time.Second}
	client := &Client{pool: pool, apiBaseURL: strings.TrimRight(cfg.PasinoAPIBaseURL, "/"), socketURL: cfg.PasinoSocketURL, apiKey: cfg.PasinoAPIKey, credentialKey: cfg.PasinoCredentialKey, referrer: cfg.PasinoReferrer, http: httpClient, sockets: make(map[int64]*providerSocket), connectLocks: make(map[int64]*sync.Mutex), reconnecting: make(map[int64]bool), shutdown: make(chan struct{}), balanceCache: make(map[string]cachedBalance), lastKnown: make(map[string]string), balanceFlight: make(map[string]*balanceFlight)}
	client.dial = &websocket.DialOptions{HTTPHeader: http.Header{"User-Agent": []string{pasinoUserAgent}}}
	if cfg.PasinoProxyURL != "" {
		// Optional clean-IP upstream: Pasino's edge blocks some VPS/datacenter
		// IPs (HTTP 403 + HTML). Pointing PASINO_PROXY_URL at a SOCKS5/HTTP
		// proxy with an allowed IP makes the API and WebSocket egress from
		// that IP (socks5/socks5h and http/https schemes supported).
		proxyURL, err := url.Parse(cfg.PasinoProxyURL)
		if err != nil {
			pool.Close()
			return nil, fmt.Errorf("PASINO_PROXY_URL tidak valid: %w", err)
		}
		transport := http.DefaultTransport.(*http.Transport).Clone()
		transport.Proxy = http.ProxyURL(proxyURL)
		httpClient.Transport = transport
		client.dial.HTTPClient = httpClient
	}
	return client, nil
}
func (c *Client) Close() {
	c.shutdownOnce.Do(func() { close(c.shutdown) })
	c.socketsMu.Lock()
	for _, socket := range c.sockets {
		socket.stopOnce.Do(func() { close(socket.stop) })
		_ = socket.connection.Close(websocket.StatusGoingAway, "server shutdown")
	}
	c.sockets = make(map[int64]*providerSocket)
	c.socketsMu.Unlock()
	c.pool.Close()
}

// RegisterAndLogin preserves the legacy registration sequence. The Pasino
// account is created with the provider referrer before the local account is
// committed, and the returned token is immediately stored encrypted locally.
func (c *Client) RegisterAndLogin(ctx context.Context, username, email, password string) (string, error) {
	_, err := c.post(ctx, "/api/register", map[string]any{
		"user_name": username, "user_email": email, "password": password,
		"agreement": 1, "referrer": c.referrer, "api_key": c.apiKey,
	})
	if err != nil {
		return "", err
	}
	return c.login(ctx, email, password)
}

func (c *Client) EncryptCredential(plain string) (string, error) { return c.encrypt(plain) }

// RefreshFromLogin follows the legacy policy: first accept an imported Pasino
// token, then use the external password only if Pasino rejects that token.
func (c *Client) RefreshFromLogin(ctx context.Context, userID int64, fallbackPassword string) error {
	account, err := c.account(ctx, userID)
	if err != nil {
		return err
	}
	if account.AccessToken != "" {
		if _, err = c.ensureSocket(ctx, userID); err == nil {
			return nil
		}
		if !errors.Is(err, ErrUnauthorized) {
			return err
		}
	}
	password := fallbackPassword
	if account.Password != "" {
		var decryptErr error
		password, decryptErr = c.decrypt(account.Password)
		if decryptErr != nil {
			return fmt.Errorf("credential Pasino tidak dapat dibuka: %w", decryptErr)
		}
	}
	if account.Email == "" || password == "" {
		return ErrUnauthorized
	}
	access, err := c.login(ctx, account.Email, password)
	if err != nil {
		return err
	}
	ciphertext, err := c.encrypt(access)
	if err != nil {
		return err
	}
	if _, err = c.pool.Exec(ctx, `UPDATE user_pasino_accounts SET access_token_ciphertext=$2,last_authenticated_at=now(),updated_at=now() WHERE user_id=$1`, userID, ciphertext); err != nil {
		return err
	}
	// Login is not complete until the socket token has been obtained and the
	// Pasino WebSocket has acknowledged authentication. Balance and trading
	// requests can then reuse this already-open connection.
	_, err = c.ensureSocket(ctx, userID)
	return err
}

// PrepareSocket obtains the socket token and completes Pasino WebSocket
// authentication without issuing a balance or trading command.
func (c *Client) PrepareSocket(ctx context.Context, userID int64) error {
	_, err := c.ensureSocket(ctx, userID)
	return err
}

// Balance reads one live value from the Pasino socket. No cached or database
// balance is returned by this method.
func (c *Client) Balance(ctx context.Context, userID int64, coin string) (string, error) {
	coin = strings.ToUpper(strings.TrimSpace(coin))
	key := fmt.Sprintf("%d:%s", userID, coin)
	c.balanceMu.Lock()
	if cached, ok := c.balanceCache[key]; ok && time.Now().Before(cached.expiresAt) {
		c.balanceMu.Unlock()
		return cached.value, nil
	}
	if running := c.balanceFlight[key]; running != nil {
		c.balanceMu.Unlock()
		select {
		case <-running.done:
			return running.value, running.err
		case <-ctx.Done():
			return "", ctx.Err()
		}
	}
	running := &balanceFlight{done: make(chan struct{})}
	c.balanceFlight[key] = running
	c.balanceMu.Unlock()

	value, err := c.readBalance(ctx, userID, coin)
	c.balanceMu.Lock()
	running.value, running.err = value, err
	if err == nil {
		c.balanceCache[key] = cachedBalance{value: value, expiresAt: time.Now().Add(5 * time.Second)}
		c.lastKnown[key] = value
	}
	delete(c.balanceFlight, key)
	close(running.done)
	c.balanceMu.Unlock()
	return value, err
}

// BalanceForDisplay serves UI reads. It prefers the live provider value and
// falls back to the last known balance while the socket is being
// re-established, so switching coins keeps rendering a number. The stale flag
// marks the fallback; money-moving callers must keep using Balance.
func (c *Client) BalanceForDisplay(ctx context.Context, userID int64, coin string) (value string, stale bool, err error) {
	coin = strings.ToUpper(strings.TrimSpace(coin))
	value, err = c.Balance(ctx, userID, coin)
	if err == nil {
		return value, false, nil
	}
	if errors.Is(err, ErrUnauthorized) || ctx.Err() != nil {
		return "", false, err
	}
	c.balanceMu.Lock()
	last, ok := c.lastKnown[fmt.Sprintf("%d:%s", userID, coin)]
	c.balanceMu.Unlock()
	if ok {
		return last, true, nil
	}
	return "", false, err
}

// Balances requests several coins over one authenticated socket round-trip.
// This is used by management views that need every supported coin at once;
// reading them through Balance sequentially would multiply the provider
// timeout by the number of coins.
func (c *Client) Balances(ctx context.Context, userID int64, coins []string) (map[string]string, error) {
	wanted := make([]string, 0, len(coins))
	remaining := make(map[string]bool, len(coins))
	for _, rawCoin := range coins {
		coin := strings.ToUpper(strings.TrimSpace(rawCoin))
		if coin != "" && !remaining[coin] {
			wanted = append(wanted, coin)
			remaining[coin] = true
		}
	}
	result := make(map[string]string, len(wanted))
	if len(wanted) == 0 {
		return result, nil
	}
	socket, err := c.ensureSocket(ctx, userID)
	if err != nil {
		return result, err
	}
	socket.mu.Lock()
	defer socket.mu.Unlock()
	readCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	for _, coin := range wanted {
		if err = wsjson.Write(readCtx, socket.connection, map[string]any{"method": "get_balance", "coin": coin}); err != nil {
			c.dropSocket(userID, socket)
			return result, fmt.Errorf("koneksi socket Pasino perlu diperbarui: %w", err)
		}
	}
	for len(remaining) > 0 {
		var raw json.RawMessage
		select {
		case raw = <-socket.incoming:
		case err = <-socket.readErr:
			c.dropSocket(userID, socket)
			return result, fmt.Errorf("saldo Pasino belum tersedia: %w", err)
		case <-readCtx.Done():
			if ctx.Err() == nil {
				c.dropSocket(userID, socket)
			}
			return result, fmt.Errorf("saldo Pasino belum lengkap: %w", readCtx.Err())
		}
		var message map[string]any
		if json.Unmarshal(raw, &message) != nil || messageString(message, "action") != "update_balance" {
			continue
		}
		coin := strings.ToUpper(messageString(message, "coin"))
		if !remaining[coin] {
			// Pasino can omit coin in update_balance. Responses follow request
			// order, matching the legacy client's last requested coin fallback.
			for _, pendingCoin := range wanted {
				if remaining[pendingCoin] {
					coin = pendingCoin
					break
				}
			}
		}
		balance := messageString(message, "balance")
		if balance == "" {
			balance = messageString(message, "user_balance")
		}
		if balance == "" {
			balance = messageString(message, "Balance")
		}
		if coin == "" || balance == "" {
			continue
		}
		result[coin] = balance
		delete(remaining, coin)
	}
	now := time.Now()
	c.balanceMu.Lock()
	for coin, value := range result {
		key := fmt.Sprintf("%d:%s", userID, coin)
		c.balanceCache[key] = cachedBalance{value: value, expiresAt: now.Add(5 * time.Second)}
		c.lastKnown[key] = value
	}
	c.balanceMu.Unlock()
	return result, nil
}

// ClearBalanceCache mirrors the legacy provider session: every operation that
// can alter a provider balance invalidates the short-lived read cache and the
// last known fallback, so a stale value can never survive a mutation.
func (c *Client) ClearBalanceCache(userID int64, coin string) {
	key := fmt.Sprintf("%d:%s", userID, strings.ToUpper(strings.TrimSpace(coin)))
	c.balanceMu.Lock()
	delete(c.balanceCache, key)
	delete(c.lastKnown, key)
	c.balanceMu.Unlock()
}

func (c *Client) readBalance(ctx context.Context, userID int64, coin string) (string, error) {
	value, err := c.readBalanceOnce(ctx, userID, coin)
	if err == nil {
		return value, nil
	}
	// Socket failures and internal timeouts are retried once on a fresh
	// socket (readBalanceOnce dropped the dead one). A cancelled HTTP request
	// or an unauthorized account must not pay the extra round-trip.
	if ctx.Err() != nil || errors.Is(err, ErrUnauthorized) {
		return "", err
	}
	select {
	case <-ctx.Done():
		return "", ctx.Err()
	case <-time.After(300 * time.Millisecond):
	}
	return c.readBalanceOnce(ctx, userID, coin)
}

func (c *Client) readBalanceOnce(ctx context.Context, userID int64, coin string) (string, error) {
	socket, err := c.ensureSocket(ctx, userID)
	if err != nil {
		return "", err
	}
	socket.mu.Lock()
	defer socket.mu.Unlock()
	readCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err = wsjson.Write(readCtx, socket.connection, map[string]any{"method": "get_balance", "coin": coin}); err != nil {
		c.dropSocket(userID, socket)
		return "", fmt.Errorf("koneksi socket Pasino perlu diperbarui: %w", err)
	}
	for {
		var raw json.RawMessage
		select {
		case raw = <-socket.incoming:
		case err = <-socket.readErr:
			c.dropSocket(userID, socket)
			return "", fmt.Errorf("saldo Pasino belum tersedia: %w", err)
		case <-readCtx.Done():
			// Pembatalan request HTTP tidak boleh menutup socket bersama.
			// Timeout internal berarti socket benar-benar tidak menjawab dan
			// harus diganti pada request berikutnya.
			if ctx.Err() == nil {
				c.dropSocket(userID, socket)
			}
			return "", fmt.Errorf("saldo Pasino belum tersedia: %w", readCtx.Err())
		}
		var message map[string]any
		if json.Unmarshal(raw, &message) != nil {
			continue
		}
		if messageString(message, "action") != "update_balance" {
			continue
		}
		responseCoin := strings.ToUpper(messageString(message, "coin"))
		if responseCoin != "" && responseCoin != coin {
			continue
		}
		balance := messageString(message, "balance")
		if balance == "" {
			balance = messageString(message, "user_balance")
		}
		if balance == "" {
			balance = messageString(message, "Balance")
		}
		if balance == "" {
			return "", errors.New("respons saldo Pasino tidak lengkap")
		}
		return balance, nil
	}
}

func (c *Client) DepositInfo(ctx context.Context, userID int64, coin string) (map[string]any, error) {
	account, err := c.account(ctx, userID)
	if err != nil {
		return nil, err
	}
	if account.AccessToken == "" {
		return nil, ErrUnauthorized
	}
	access, err := c.decrypt(account.AccessToken)
	if err != nil {
		return nil, fmt.Errorf("credential Pasino tidak dapat dibuka: %w", err)
	}
	return c.post(ctx, "/deposit/get-deposit-information", map[string]string{"token": access, "coin": strings.ToUpper(coin)})
}
func (c *Client) Withdraw(ctx context.Context, userID int64, coin, address, amount string) (map[string]any, error) {
	result, err := c.walletMutation(ctx, userID, "/withdraw/place-withdrawal", map[string]any{"coin": coin, "method": "DIRECT", "address": address, "amount": amount})
	if err == nil {
		c.ClearBalanceCache(userID, coin)
	}
	return result, err
}
func (c *Client) Transfer(ctx context.Context, userID int64, coin, username, amount string) (map[string]any, error) {
	result, err := c.walletMutation(ctx, userID, "/transfer/send-transfer", map[string]any{"coin": coin, "user_name": username, "amount": amount})
	if err == nil {
		c.ClearBalanceCache(userID, coin)
	}
	return result, err
}
func (c *Client) walletMutation(ctx context.Context, userID int64, path string, body map[string]any) (map[string]any, error) {
	account, err := c.account(ctx, userID)
	if err != nil {
		return nil, err
	}
	if account.AccessToken == "" {
		return nil, ErrUnauthorized
	}
	token, err := c.decrypt(account.AccessToken)
	if err != nil {
		return nil, err
	}
	body["token"] = token
	encoded, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, c.apiBaseURL+path, strings.NewReader(string(encoded)))
	if err != nil {
		return nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("User-Agent", pasinoUserAgent)
	response, err := c.http.Do(request)
	if err != nil {
		return nil, &OutcomeUnknownError{Cause: fmt.Errorf("Pasino tidak dapat dihubungi: %w", err)}
	}
	defer response.Body.Close()
	var payload map[string]any
	if err = json.NewDecoder(response.Body).Decode(&payload); err != nil {
		snippet, _ := io.ReadAll(io.LimitReader(response.Body, 256))
		return nil, &OutcomeUnknownError{Cause: fmt.Errorf("respons Pasino tidak valid (HTTP %s): %q", response.Status, strings.TrimSpace(string(snippet)))}
	}
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
		return nil, ErrUnauthorized
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		message := messageString(payload, "message")
		if message == "" {
			message = messageString(payload, "error")
		}
		return nil, fmt.Errorf("%s", message)
	}
	if success, ok := payload["success"].(bool); ok && !success {
		message := messageString(payload, "message")
		if message == "" {
			message = messageString(payload, "error")
		}
		return nil, errors.New(message)
	}
	return payload, nil
}

// PlaceBet waits for the correlated Pasino bet_update on the same authenticated
// socket. Once the payload has been written, a read/disconnect failure is an
// unknown outcome and the caller must reconcile instead of retrying.
func (c *Client) PlaceBet(ctx context.Context, userID int64, payload map[string]any) (json.RawMessage, error) {
	socket, err := c.ensureSocket(ctx, userID)
	if err != nil {
		return nil, err
	}
	socket.mu.Lock()
	defer socket.mu.Unlock()
	ctx, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()
	if err = wsjson.Write(ctx, socket.connection, payload); err != nil {
		c.dropSocket(userID, socket)
		return nil, &OutcomeUnknownError{Cause: err}
	}
	for {
		var raw json.RawMessage
		select {
		case raw = <-socket.incoming:
		case err = <-socket.readErr:
			c.dropSocket(userID, socket)
			return nil, &OutcomeUnknownError{Cause: err}
		case <-ctx.Done():
			// Bet yang sudah dikirim tetapi timeout tidak boleh meninggalkan
			// bet_update terlambat untuk dibaca sebagai hasil roll berikutnya.
			c.dropSocket(userID, socket)
			return nil, &OutcomeUnknownError{Cause: ctx.Err()}
		}
		var envelope struct {
			Action string `json:"action"`
		}
		if json.Unmarshal(raw, &envelope) != nil {
			continue
		}
		if envelope.Action == "bet_update" {
			if coin, ok := payload["coin"].(string); ok {
				c.ClearBalanceCache(userID, coin)
			}
			return raw, nil
		}
	}
}

func (c *Client) waitAuthenticated(ctx context.Context, connection *websocket.Conn) error {
	for {
		var message map[string]any
		if err := wsjson.Read(ctx, connection, &message); err != nil {
			return fmt.Errorf("autentikasi socket Pasino: %w", err)
		}
		if messageString(message, "action") == "authenticated" {
			return nil
		}
		if success, ok := message["success"].(bool); ok && !success {
			return ErrUnauthorized
		}
	}
}

func (c *Client) ensureSocket(ctx context.Context, userID int64) (*providerSocket, error) {
	c.socketsMu.Lock()
	if current := c.sockets[userID]; current != nil {
		select {
		case <-current.stop:
			delete(c.sockets, userID)
		default:
			c.socketsMu.Unlock()
			return current, nil
		}
	}
	c.socketsMu.Unlock()

	// Mencegah request balance serentak meminta beberapa socket token untuk
	// user yang sama, tanpa menghambat koneksi user lain.
	c.socketsMu.Lock()
	connectionLock := c.connectLocks[userID]
	if connectionLock == nil {
		connectionLock = &sync.Mutex{}
		c.connectLocks[userID] = connectionLock
	}
	c.socketsMu.Unlock()
	connectionLock.Lock()
	defer connectionLock.Unlock()
	c.socketsMu.Lock()
	if current := c.sockets[userID]; current != nil {
		select {
		case <-current.stop:
			delete(c.sockets, userID)
		default:
			c.socketsMu.Unlock()
			return current, nil
		}
	}
	c.socketsMu.Unlock()

	account, err := c.account(ctx, userID)
	if err != nil {
		return nil, err
	}
	if account.AccessToken == "" {
		return nil, ErrUnauthorized
	}
	access, err := c.decrypt(account.AccessToken)
	if err != nil {
		return nil, fmt.Errorf("credential Pasino tidak dapat dibuka: %w", err)
	}
	socketToken, err := c.socketToken(ctx, access)
	if err != nil {
		return nil, err
	}
	connectCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	connection, _, err := websocket.Dial(connectCtx, c.socketURL, c.dial)
	if err != nil {
		return nil, fmt.Errorf("hubungkan socket Pasino: %w", err)
	}
	if err = wsjson.Write(connectCtx, connection, map[string]any{"method": "initialization", "socket_token": socketToken}); err != nil {
		_ = connection.Close(websocket.StatusInternalError, "initialization failed")
		return nil, err
	}
	if err = c.waitAuthenticated(connectCtx, connection); err != nil {
		_ = connection.Close(websocket.StatusPolicyViolation, "authentication failed")
		return nil, err
	}
	created := &providerSocket{
		connection: connection,
		incoming:   make(chan json.RawMessage, 32),
		readErr:    make(chan error, 1),
		stop:       make(chan struct{}),
	}
	c.socketsMu.Lock()
	if current := c.sockets[userID]; current != nil {
		c.socketsMu.Unlock()
		_ = connection.Close(websocket.StatusNormalClosure, "duplicate connection")
		return current, nil
	}
	c.sockets[userID] = created
	c.socketsMu.Unlock()
	go c.readSocket(userID, created)
	go c.keepSocketAlive(userID, created)
	return created, nil
}

// readSocket is the only reader for a live connection. HTTP cancellation can
// therefore never cancel or corrupt the socket that is also used by trading.
func (c *Client) readSocket(userID int64, socket *providerSocket) {
	for {
		var raw json.RawMessage
		if err := wsjson.Read(context.Background(), socket.connection, &raw); err != nil {
			select {
			case socket.readErr <- err:
			default:
			}
			c.dropSocket(userID, socket)
			return
		}
		select {
		case socket.incoming <- raw:
		case <-socket.stop:
			return
		}
	}
}
func (c *Client) dropSocket(userID int64, target *providerSocket) {
	c.socketsMu.Lock()
	if c.sockets[userID] == target {
		delete(c.sockets, userID)
	}
	c.socketsMu.Unlock()
	// Close may wait for the peer's close handshake. Never hold socketsMu here,
	// otherwise a reconnect can observe and reuse the stale connection.
	target.stopOnce.Do(func() {
		close(target.stop)
		_ = target.connection.Close(websocket.StatusNormalClosure, "reconnect")
	})
	c.scheduleReconnect(userID)
}

// scheduleReconnect re-establishes the dropped socket in the background so the
// next user request does not pay the full dial+authenticate latency. Only one
// loop per user runs at a time; concurrent drops rely on the running loop.
func (c *Client) scheduleReconnect(userID int64) {
	c.socketsMu.Lock()
	if c.reconnecting[userID] {
		c.socketsMu.Unlock()
		return
	}
	c.reconnecting[userID] = true
	c.socketsMu.Unlock()
	go func() {
		defer func() {
			c.socketsMu.Lock()
			delete(c.reconnecting, userID)
			c.socketsMu.Unlock()
		}()
		c.reconnectLoop(userID)
	}()
}

// reconnectLoop retries the Pasino socket with exponential backoff. It stops
// once any live socket exists for the user, when credentials are rejected, or
// after bounded attempts; the next request then falls back to the lazy
// connect inside ensureSocket.
func (c *Client) reconnectLoop(userID int64) {
	delay := time.Second
	for attempt := 0; attempt < 8; attempt++ {
		select {
		case <-c.shutdown:
			return
		case <-time.After(delay):
		}
		c.socketsMu.Lock()
		current := c.sockets[userID]
		c.socketsMu.Unlock()
		if current != nil {
			select {
			case <-current.stop:
			default:
				return
			}
		}
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		_, err := c.ensureSocket(ctx, userID)
		cancel()
		if err == nil {
			return
		}
		if errors.Is(err, ErrUnauthorized) {
			return
		}
		delay *= 2
		if delay > 30*time.Second {
			delay = 30 * time.Second
		}
	}
}

// DropUserSocket forces the next operation to authenticate with the latest
// encrypted credentials stored for the account.
func (c *Client) DropUserSocket(userID int64) {
	prefix := fmt.Sprintf("%d:", userID)
	c.balanceMu.Lock()
	for key := range c.balanceCache {
		if strings.HasPrefix(key, prefix) {
			delete(c.balanceCache, key)
		}
	}
	for key := range c.lastKnown {
		if strings.HasPrefix(key, prefix) {
			delete(c.lastKnown, key)
		}
	}
	c.balanceMu.Unlock()
	c.socketsMu.Lock()
	target := c.sockets[userID]
	c.socketsMu.Unlock()
	if target != nil {
		c.dropSocket(userID, target)
	}
}

func (c *Client) keepSocketAlive(userID int64, socket *providerSocket) {
	ticker := time.NewTicker(20 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			socket.mu.Lock()
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			err := wsjson.Write(ctx, socket.connection, map[string]any{"method": "ping"})
			cancel()
			socket.mu.Unlock()
			if err != nil {
				c.dropSocket(userID, socket)
				return
			}
		case <-socket.stop:
			return
		}
	}
}

type providerAccount struct{ Email, Password, AccessToken string }

func (c *Client) account(ctx context.Context, userID int64) (providerAccount, error) {
	var a providerAccount
	err := c.pool.QueryRow(ctx, `SELECT coalesce(provider_email,''),coalesce(password_ciphertext,''),coalesce(access_token_ciphertext,'') FROM user_pasino_accounts WHERE user_id=$1`, userID).Scan(&a.Email, &a.Password, &a.AccessToken)
	if errors.Is(err, pgx.ErrNoRows) {
		return a, ErrUnauthorized
	}
	return a, err
}
func (c *Client) socketToken(ctx context.Context, access string) (string, error) {
	payload, err := c.post(ctx, "/account/get-socket-token", map[string]string{"token": access})
	if err != nil {
		return "", err
	}
	token := messageString(payload, "socket_token")
	if token == "" {
		return "", ErrUnauthorized
	}
	return token, nil
}
func (c *Client) login(ctx context.Context, email, password string) (string, error) {
	if c.apiKey == "" {
		return "", errors.New("PASINO_API_KEY belum dikonfigurasi")
	}
	payload, err := c.post(ctx, "/api/login", map[string]string{"user": email, "password": password, "api_key": c.apiKey})
	if err != nil {
		return "", err
	}
	token := messageString(payload, "token")
	if token == "" {
		return "", ErrUnauthorized
	}
	return token, nil
}
func (c *Client) post(ctx context.Context, path string, body any) (map[string]any, error) {
	encoded, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, c.apiBaseURL+path, strings.NewReader(string(encoded)))
	if err != nil {
		return nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("User-Agent", pasinoUserAgent)
	response, err := c.http.Do(request)
	if err != nil {
		return nil, fmt.Errorf("Pasino tidak dapat dihubungi: %w", err)
	}
	defer response.Body.Close()
	var payload map[string]any
	if err = json.NewDecoder(response.Body).Decode(&payload); err != nil {
		snippet, _ := io.ReadAll(io.LimitReader(response.Body, 256))
		return nil, fmt.Errorf("respons Pasino tidak valid (HTTP %s): %q", response.Status, strings.TrimSpace(string(snippet)))
	}
	if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
		return nil, ErrUnauthorized
	}
	if success, ok := payload["success"].(bool); ok && !success {
		message := strings.ToLower(messageString(payload, "message") + " " + messageString(payload, "error"))
		if strings.Contains(message, "token") || strings.Contains(message, "session") {
			return nil, ErrUnauthorized
		}
		return nil, fmt.Errorf("%s", messageString(payload, "message"))
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, fmt.Errorf("Pasino HTTP %d", response.StatusCode)
	}
	if data, ok := payload["data"].(map[string]any); ok {
		return data, nil
	}
	return payload, nil
}

func (c *Client) key() ([]byte, error) {
	if c.credentialKey == "" {
		return nil, errors.New("PASINO_CREDENTIAL_ENCRYPTION_KEY belum dikonfigurasi")
	}
	sum := sha256.Sum256([]byte(c.credentialKey))
	return sum[:], nil
}
func (c *Client) decrypt(encoded string) (string, error) {
	parts := strings.Split(encoded, ".")
	if len(parts) != 4 || parts[0] != "v1" {
		return "", errors.New("format credential terenkripsi tidak valid")
	}
	key, err := c.key()
	if err != nil {
		return "", err
	}
	iv, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return "", err
	}
	tag, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return "", err
	}
	encrypted, err := base64.RawURLEncoding.DecodeString(parts[3])
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	plain, err := gcm.Open(nil, iv, append(encrypted, tag...), nil)
	if err != nil {
		return "", err
	}
	return string(plain), nil
}
func (c *Client) encrypt(plain string) (string, error) {
	if plain == "" {
		return "", errors.New("credential Pasino kosong")
	}
	key, err := c.key()
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	iv := make([]byte, gcm.NonceSize())
	if _, err = rand.Read(iv); err != nil {
		return "", err
	}
	sealed := gcm.Seal(nil, iv, []byte(plain), nil)
	tagLength := gcm.Overhead()
	ciphertext, tag := sealed[:len(sealed)-tagLength], sealed[len(sealed)-tagLength:]
	return "v1." + base64.RawURLEncoding.EncodeToString(iv) + "." + base64.RawURLEncoding.EncodeToString(tag) + "." + base64.RawURLEncoding.EncodeToString(ciphertext), nil
}
func messageString(message map[string]any, key string) string {
	if value, ok := message[key]; ok && value != nil {
		return fmt.Sprint(value)
	}
	return ""
}
