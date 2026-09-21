package admin

import (
	"encoding/json"
	"html/template"
	"net/http"
	"strings"
)

func (h *HTTP) cutoffEstimate(w http.ResponseWriter, r *http.Request) {
	estimate, err := h.store.CutoffEstimate(r.Context(), h.provider, r.URL.Query().Get("coin"))
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
		_ = json.NewEncoder(w).Encode(map[string]string{"message": err.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(estimate)
}

var categories = map[string]string{
	"trading": "Trading & Fee", "referral": "Referral", "subscription": "Aturan Langganan", "owner": "Owner & Cut Off", "accounts": "Akun Bisnis", "coins": "Coin & Minimum",
}

type adminPage struct {
	Admin          Admin
	PageTitle      string
	Current        string
	Category       string
	Dashboard      bool
	Placeholder    bool
	Report         template.HTML
	Saved          bool
	Error          string
	Items          []Setting
	CoinGroups     []CoinGroup
	Categories     []Category
	DashboardStats DashboardStats
	SettingsOpen   bool
	ManagementOpen bool
	FinanceOpen    bool
}

type DashboardStats struct {
	TotalMembers, MembersToday, LoginsToday, TradingMembers int64
	Revenue                                                 []DashboardRevenue
}

type DashboardRevenue struct{ Coin, Amount string }

type CoinGroup struct {
	Coin  string
	Icon  string
	Items []Setting
}

func (h *HTTP) dashboard(w http.ResponseWriter, r *http.Request) {
	stats, err := h.store.DashboardStats(r.Context())
	if err != nil {
		h.fail(w, err)
		return
	}
	h.renderAdmin(w, adminPage{Admin: current(r), Current: "dashboard", Dashboard: true, DashboardStats: stats})
}

func (h *HTTP) placeholderPage(w http.ResponseWriter, r *http.Request) {
	page := r.PathValue("page")
	titles := map[string]string{"users": "User", "subscriptions": "Berlangganan", "revenue": "Pendapatan", "cutoffs": "Cut Off"}
	title, ok := titles[page]
	if !ok {
		http.NotFound(w, r)
		return
	}
	report, err := h.store.Report(r.Context(), page, h.provider, current(r).CSRF)
	if err != nil {
		h.fail(w, err)
		return
	}
	h.renderAdmin(w, adminPage{Admin: current(r), PageTitle: title, Current: page, Report: report, Saved: r.URL.Query().Get("saved") != "", ManagementOpen: page == "users" || page == "subscriptions", FinanceOpen: page == "revenue" || page == "cutoffs"})
}

func (h *HTTP) settingsPage(w http.ResponseWriter, r *http.Request) {
	category := r.PathValue("category")
	title, ok := categories[category]
	if !ok {
		http.NotFound(w, r)
		return
	}
	items, err := h.store.Settings(r.Context(), category)
	if err != nil {
		h.fail(w, err)
		return
	}
	h.renderAdmin(w, adminPage{Admin: current(r), PageTitle: title, Current: settingCurrent(category), Category: category, SettingsOpen: true, Saved: r.URL.Query().Get("saved") != "", Items: items, CoinGroups: groupCoinRuleTypes(items)})
}

func (h *HTTP) saveSettings(w http.ResponseWriter, r *http.Request) {
	admin := current(r)
	if !h.validCSRF(r, admin) {
		http.Error(w, "CSRF tidak valid", http.StatusForbidden)
		return
	}
	category := r.PathValue("category")
	if _, ok := categories[category]; !ok {
		http.NotFound(w, r)
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, "request tidak valid", http.StatusBadRequest)
		return
	}
	values := map[string]string{}
	for key, list := range r.Form {
		if strings.HasPrefix(key, "setting:") && len(list) > 0 {
			values[strings.TrimPrefix(key, "setting:")] = strings.TrimSpace(list[0])
		}
	}
	if err := h.store.SaveSettings(r.Context(), admin.ID, category, values); err != nil {
		items, loadErr := h.store.Settings(r.Context(), category)
		if loadErr != nil {
			h.fail(w, err)
			return
		}
		for index := range items {
			if value, ok := values[items[index].Key]; ok {
				items[index].Value = value
			}
		}
		h.renderAdmin(w, adminPage{Admin: admin, PageTitle: categories[category], Current: settingCurrent(category), Category: category, SettingsOpen: true, Error: err.Error(), Items: items, CoinGroups: groupCoinRuleTypes(items)})
		return
	}
	http.Redirect(w, r, "/admin/settings/"+category+"?saved=1", http.StatusSeeOther)
}

func groupCoinRuleTypes(items []Setting) []CoinGroup {
	types := []struct{ suffix, label, icon string }{
		{"minimum_bet", "Minimum Bet", "circle-dollar-sign"},
		{"minimum_claim", "Minimum Claim Bonus", "gift"},
		{"minimum_withdrawal", "Minimum Withdrawal", "arrow-down-to-line"},
	}
	groups := make([]CoinGroup, 0, len(types))
	for _, ruleType := range types {
		group := CoinGroup{Coin: ruleType.label, Icon: ruleType.icon}
		for _, item := range items {
			if strings.HasSuffix(item.Key, "."+ruleType.suffix) {
				group.Items = append(group.Items, item)
			}
		}
		if len(group.Items) > 0 {
			groups = append(groups, group)
		}
	}
	return groups
}

func settingCurrent(category string) string {
	if category == "subscription" {
		return "subscription-settings"
	}
	return category
}

func (h *HTTP) renderAdmin(w http.ResponseWriter, data adminPage) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := adminTemplates.Execute(w, data); err != nil {
		h.logger.Error("render admin", "error", err)
	}
}
