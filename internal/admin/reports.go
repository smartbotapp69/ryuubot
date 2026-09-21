package admin

import (
	"context"
	"fmt"
	"html"
	"html/template"
	"strings"

	"ryubot/internal/pasino"
	"ryubot/internal/trading"
)

func esc(v any) string { return html.EscapeString(fmt.Sprint(v)) }
func (s *Store) Report(ctx context.Context, page string, provider *pasino.Client, csrf string) (template.HTML, error) {
	switch page {
	case "users", "subscriptions":
		return s.userReport(ctx, page)
	case "revenue":
		return s.revenueReport(ctx)
	case "cutoffs":
		return s.cutoffReport(ctx, provider, csrf)
	}
	return "", fmt.Errorf("halaman tidak dikenal")
}
func (s *Store) userReport(ctx context.Context, page string) (template.HTML, error) {
	rows, err := s.pool.Query(ctx, `SELECT id,username,email,status,coalesce(to_char(subscription_trial_ends_at,'DD Mon YYYY HH24:MI'),'-'),coalesce(to_char(subscription_expires_at,'DD Mon YYYY HH24:MI'),'-'),to_char(created_at,'DD Mon YYYY HH24:MI'),CASE WHEN subscription_expires_at>now() THEN 'AKTIF' WHEN subscription_trial_ends_at>now() THEN 'TRIAL' ELSE 'BERAKHIR' END,coalesce(to_char(last_login_at,'DD Mon YYYY HH24:MI'),'Belum pernah'),coalesce(to_char(last_active_at,'DD Mon YYYY HH24:MI'),'Belum pernah'),CASE WHEN last_active_at IS NULL THEN 'BELUM PERNAH' WHEN last_active_at>=now()-interval '7 days' THEN 'AKTIF' ELSE 'TIDAK AKTIF' END FROM users ORDER BY id DESC LIMIT 1000`)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	var b strings.Builder
	b.WriteString(`<div class="report-tools"><input class="report-search" type="search" placeholder="Cari username atau email...">`)
	if page == "subscriptions" {
		b.WriteString(`<select class="subscription-filter"><option value="">Semua status</option><option value="AKTIF">Aktif</option><option value="TRIAL">Trial</option><option value="BERAKHIR">Berakhir</option></select>`)
	}
	b.WriteString(`</div><div class="report-scroll"><table class="searchable"><thead><tr><th>No</th><th>Username</th><th>Email</th><th>Status</th>`)
	if page == "users" {
		b.WriteString(`<th>Aktivitas</th><th>Terakhir Buka</th><th>Berlangganan Sampai</th><th>Terdaftar</th>`)
	} else {
		b.WriteString(`<th>Trial Sampai</th><th>Aktif Sampai</th>`)
	}
	b.WriteString(`<th>Aksi</th></tr></thead><tbody>`)
	n := 0
	for rows.Next() {
		var id int64
		var username, email, status, trial, expires, created, subscriptionStatus, lastLogin, lastActive, activity string
		if err = rows.Scan(&id, &username, &email, &status, &trial, &expires, &created, &subscriptionStatus, &lastLogin, &lastActive, &activity); err != nil {
			return "", err
		}
		n++
		shown := status
		if page == "subscriptions" {
			shown = subscriptionStatus
		}
		badge := "badge-green"
		if shown == "SUSPENDED" || shown == "BERAKHIR" {
			badge = "badge-red"
		} else if shown == "TRIAL" {
			badge = "badge-yellow"
		}
		b.WriteString(`<tr data-subscription-status="` + esc(subscriptionStatus) + `"><td>` + fmt.Sprint(n) + `</td><td><strong>` + esc(username) + `</strong></td><td>` + esc(email) + `</td><td><span class="status-badge ` + badge + `">` + esc(shown) + `</span></td>`)
		if page == "users" {
			activityBadge := "badge-green"
			if activity == "TIDAK AKTIF" {
				activityBadge = "badge-yellow"
			} else if activity == "BELUM PERNAH" {
				activityBadge = "badge-red"
			}
			b.WriteString(`<td><span class="status-badge ` + activityBadge + `">` + esc(activity) + `</span></td><td>` + esc(lastActive) + `</td><td>` + esc(expires) + `</td><td>` + esc(created) + `</td>`)
		} else {
			b.WriteString(`<td>` + esc(trial) + `</td><td>` + esc(expires) + `</td>`)
		}
		b.WriteString(`<td><button type="button" class="view-user" data-id="` + fmt.Sprint(id) + `" data-username="` + esc(username) + `" data-email="` + esc(email) + `" data-status="` + esc(status) + `" data-trial="` + esc(trial) + `" data-expires="` + esc(expires) + `" data-login="` + esc(lastLogin) + `" data-active="` + esc(lastActive) + `" data-return="` + page + `">View</button></td></tr>`)
	}
	if err = rows.Err(); err != nil {
		return "", err
	}
	if n == 0 {
		b.WriteString(`<tr><td colspan="7" class="report-empty">Belum ada data</td></tr>`)
	}
	b.WriteString(`</tbody></table></div>`)
	b.WriteString(`<dialog id="userDetail"><form method="post" class="user-modal"><button type="button" class="modal-close" aria-label="Tutup">x</button><h2 id="modalUsername"></h2><p id="modalEmail" class="modal-email"></p><div class="modal-meta"><span>Status <b id="modalStatus"></b></span><span>Trial <b id="modalTrial"></b></span><span>Aktif sampai <b id="modalExpires"></b></span><span>Login terakhir <b id="modalLogin"></b></span><span>Terakhir buka <b id="modalActive"></b></span></div><input type="hidden" name="csrf"><input type="hidden" name="return_to"><section class="modal-action"><label>Perpanjangan (bulan)<input name="months" type="number" min="1" max="120" value="1"></label><button name="action" value="EXTEND_SUBSCRIPTION">Perpanjang</button></section><section class="modal-action full-user-action"><label>Password baru<input name="password" type="password" minlength="6" autocomplete="new-password"></label><button name="action" value="RESET_PASSWORD">Update Password</button></section><div class="modal-state-actions full-user-action"><button class="danger-button" name="action" value="SUSPEND">Suspend</button><button class="success-button" name="action" value="ACTIVATE">Aktifkan</button></div></form></dialog>`)
	b.WriteString(`<script>(()=>{const q=document.querySelector('.report-search'),f=document.querySelector('.subscription-filter'),d=document.getElementById('userDetail'),filter=()=>{const v=(q?.value||'').toLowerCase(),s=f?.value||'';document.querySelectorAll('table.searchable tbody tr').forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(v)||(s&&r.dataset.subscriptionStatus!==s))};q?.addEventListener('input',filter);f?.addEventListener('change',filter);document.querySelectorAll('.view-user').forEach(x=>x.addEventListener('click',()=>{d.querySelector('form').action='/admin/users/'+x.dataset.id+'/action';d.querySelector('[name=csrf]').value=document.querySelector('.header form [name=csrf]').value;d.querySelector('[name=return_to]').value=x.dataset.return;document.getElementById('modalUsername').textContent=x.dataset.username;document.getElementById('modalEmail').textContent=x.dataset.email;document.getElementById('modalStatus').textContent=x.dataset.status;document.getElementById('modalTrial').textContent=x.dataset.trial;document.getElementById('modalExpires').textContent=x.dataset.expires;document.getElementById('modalLogin').textContent=x.dataset.login;document.getElementById('modalActive').textContent=x.dataset.active;d.querySelectorAll('.full-user-action').forEach(e=>e.hidden=x.dataset.return==='subscriptions');d.showModal()}));d?.querySelector('.modal-close').addEventListener('click',()=>d.close());d?.addEventListener('click',e=>{if(e.target===d)d.close()})})()</script>`)
	return template.HTML(b.String()), nil
}
func (s *Store) revenueReport(ctx context.Context) (template.HTML, error) {
	rows, err := s.pool.Query(ctx, `WITH coins(coin) AS (VALUES ('TRX'),('DOGE'),('FLOKI'),('BTT')) SELECT c.coin,coalesce((SELECT sum(holding_pending) FROM trading_fee_balances WHERE coin=c.coin),0)::text,coalesce((SELECT sum(amount) FROM management_fee_payouts WHERE coin=c.coin AND allocation='HOLDING' AND status='COMPLETED'),0)::text FROM coins c`)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	var b strings.Builder
	b.WriteString(`<div class="report-scroll"><table><thead><tr><th>Coin</th><th>Fee Tertahan</th><th>Fee Terbayarkan</th></tr></thead><tbody>`)
	for rows.Next() {
		var coin, pending, paid string
		if err = rows.Scan(&coin, &pending, &paid); err != nil {
			return "", err
		}
		b.WriteString(`<tr><td><strong>` + esc(coin) + `</strong></td><td><span class="money-held">` + esc(pending) + `</span></td><td><span class="money-paid">` + esc(paid) + `</span></td></tr>`)
	}
	b.WriteString(`</tbody></table></div>`)
	return template.HTML(b.String()), rows.Err()
}
func (s *Store) cutoffReport(ctx context.Context, provider *pasino.Client, csrf string) (template.HTML, error) {
	preview, err := s.cutoffPreview(ctx, provider, csrf)
	if err != nil {
		return "", err
	}
	rows, err := s.pool.Query(ctx, `SELECT to_char(b.business_date,'YYYY-MM-DD'),to_char(b.cutoff_slot,'HH24:MI'),b.coin,b.collector_balance::text,b.reserved_liability::text,b.distributable_amount::text,b.status,coalesce(string_agg(p.allocation||': '||p.amount::text||' ['||p.status||']',' | ' ORDER BY CASE p.allocation WHEN 'NANA' THEN 1 WHEN 'DENI' THEN 2 WHEN 'ARYA' THEN 3 ELSE 4 END),'-') FROM owner_cutoff_batches b LEFT JOIN owner_cutoff_payouts p ON p.batch_id=b.id GROUP BY b.id ORDER BY b.business_date DESC,b.cutoff_slot DESC,b.coin LIMIT 200`)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	var b strings.Builder
	b.WriteString(string(preview))
	b.WriteString(`<div class="cutoff-formula">Saldo Pasino akun penampung - kewajiban bonus referral - payout belum pasti = saldo yang dibagikan</div><div class="report-scroll"><table><thead><tr><th>Tanggal</th><th>Jam</th><th>Coin</th><th>Saldo Penampung</th><th>Kewajiban & Reservasi</th><th>Saldo Dibagikan</th><th>Status</th><th>Owner & Operasional</th></tr></thead><tbody>`)
	n := 0
	for rows.Next() {
		var date, slot, coin, balance, liability, available, status, payouts string
		if err = rows.Scan(&date, &slot, &coin, &balance, &liability, &available, &status, &payouts); err != nil {
			return "", err
		}
		n++
		badge := "badge-green"
		if status == "REVIEW_REQUIRED" {
			badge = "badge-red"
		}
		b.WriteString(`<tr><td>` + esc(date) + `</td><td>` + esc(slot) + `</td><td><strong>` + esc(coin) + `</strong></td><td>` + esc(balance) + `</td><td class="money-held">` + esc(liability) + `</td><td class="money-paid">` + esc(available) + `</td><td><span class="status-badge ` + badge + `">` + esc(status) + `</span></td><td class="payout-detail">` + esc(payouts) + `</td></tr>`)
	}
	if n == 0 {
		b.WriteString(`<tr><td colspan="8" class="report-empty">Belum ada proses cutoff</td></tr>`)
	}
	b.WriteString(`</tbody></table></div>`)
	return template.HTML(b.String()), rows.Err()
}

func (s *Store) cutoffPreview(ctx context.Context, provider *pasino.Client, csrf string) (template.HTML, error) {
	var b strings.Builder
	b.WriteString(`<section class="cutoff-preview"><div class="cutoff-preview-head"><strong>Estimasi Cut Off Per Coin</strong></div><div class="report-scroll"><table><thead><tr><th>Coin</th><th>Saldo Pasino</th><th>Bonus & Reservasi</th><th>Dapat Dibagikan</th><th>Nana</th><th>Deni</th><th>Arya</th><th>Operasional</th></tr></thead><tbody>`)
	for _, coin := range []string{"TRX", "DOGE", "FLOKI", "BTT"} {
		b.WriteString(`<tr data-cutoff-coin="` + coin + `"><td><button class="cutoff-coin-load" type="button">` + coin + `</button></td><td colspan="7" class="cutoff-result">Klik coin untuk mengambil saldo</td></tr>`)
	}
	b.WriteString(`</tbody></table></div></section>`)
	return template.HTML(b.String()), nil
}

type CutoffEstimate struct {
	Coin, Balance, Reserved, Available string
	Amounts, Usernames                 []string
}

func (s *Store) CutoffEstimate(ctx context.Context, provider *pasino.Client, coin string) (CutoffEstimate, error) {
	coin = strings.ToUpper(strings.TrimSpace(coin))
	if coin != "TRX" && coin != "DOGE" && coin != "FLOKI" && coin != "BTT" {
		return CutoffEstimate{}, fmt.Errorf("coin tidak didukung")
	}
	keys := []string{"account.fee_collector_username", "account.owner_nana_username", "account.owner_deni_username", "account.owner_arya_username", "account.operational_username", "owner.nana_percent", "owner.deni_percent", "owner.arya_percent"}
	rows, err := s.pool.Query(ctx, `SELECT key,value FROM app_settings WHERE key=ANY($1)`, keys)
	if err != nil {
		return CutoffEstimate{}, err
	}
	defer rows.Close()
	cfg := map[string]string{}
	for rows.Next() {
		var k, v string
		if err = rows.Scan(&k, &v); err != nil {
			return CutoffEstimate{}, err
		}
		cfg[k] = v
	}
	var collectorID int64
	var ready bool
	if err = s.pool.QueryRow(ctx, `SELECT u.id,(p.password_ciphertext IS NOT NULL AND p.password_ciphertext<>'') FROM users u LEFT JOIN user_pasino_accounts p ON p.user_id=u.id WHERE lower(u.username)=lower($1)`, cfg["account.fee_collector_username"]).Scan(&collectorID, &ready); err != nil || !ready || provider == nil {
		return CutoffEstimate{}, fmt.Errorf("akun penampung belum siap")
	}
	balanceText, err := provider.Balance(ctx, collectorID, coin)
	if err != nil {
		return CutoffEstimate{}, err
	}
	balance, err := trading.ParseMoney(balanceText)
	if err != nil {
		return CutoffEstimate{}, err
	}
	var reservedText string
	if err = s.pool.QueryRow(ctx, `SELECT (coalesce((SELECT sum(available_amount) FROM referral_bonus_balances WHERE coin=$1),0)+coalesce((SELECT sum(p.amount) FROM owner_cutoff_payouts p JOIN owner_cutoff_batches cb ON cb.id=p.batch_id WHERE cb.coin=$1 AND p.status IN ('PREPARED','SENT','REVIEW_REQUIRED')),0))::text`, coin).Scan(&reservedText); err != nil {
		return CutoffEstimate{}, err
	}
	reserved, err := trading.ParseMoney(reservedText)
	if err != nil {
		return CutoffEstimate{}, err
	}
	available := balance - reserved
	if available < 0 {
		available = 0
	}
	amounts := make([]trading.Money, 4)
	allocated := trading.Money(0)
	for i, key := range []string{"owner.nana_percent", "owner.deni_percent", "owner.arya_percent"} {
		bps, e := trading.ParseBPS(cfg[key])
		if e != nil {
			return CutoffEstimate{}, e
		}
		amounts[i] = trading.Money(int64(available) * bps / 10000)
		allocated += amounts[i]
	}
	amounts[3] = available - allocated
	return CutoffEstimate{Coin: coin, Balance: balance.String(), Reserved: reserved.String(), Available: available.String(), Amounts: []string{amounts[0].String(), amounts[1].String(), amounts[2].String(), amounts[3].String()}, Usernames: []string{cfg["account.owner_nana_username"], cfg["account.owner_deni_username"], cfg["account.owner_arya_username"], cfg["account.operational_username"]}}, nil
}
