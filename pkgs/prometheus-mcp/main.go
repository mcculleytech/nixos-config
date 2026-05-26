// prometheus-mcp — MCP server fronting Prometheus (and optionally Alertmanager).
//
// Behavioral parity with the previous Python implementation:
//   - Streamable-HTTP MCP transport at /mcp
//   - Bearer-token auth (tokens loaded from a sops-rendered JSON file)
//   - /health (unauthenticated)
//   - /version (bearer-required) returns name + version
//   - Read-only: every tool is a GET against the upstream, never POST.
//   - Prometheus tools always registered; alertmanager_* tools registered
//     only when PROMETHEUS_MCP_AM_URL is set (graceful fallback pattern).
package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

const (
	name    = "prometheus-mcp"
	version = "0.2.0"
)

const maxResponseBytes = 32 << 20 // 32 MiB cap on upstream response bodies

// ─── Configuration ──────────────────────────────────────────────────────────

type config struct {
	BindIP     string
	Port       int
	TokensFile string
	PromURL    string
	AMURL      string // empty string = Alertmanager not configured
}

func loadConfig() (*config, error) {
	bindIP := getenvOr("PROMETHEUS_MCP_BIND_IP", "auto")
	portStr := getenvOr("PROMETHEUS_MCP_PORT", "4287")
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("PROMETHEUS_MCP_PORT=%q: %w", portStr, err)
	}
	tokensFile := os.Getenv("PROMETHEUS_MCP_TOKENS_FILE")
	if tokensFile == "" {
		return nil, errors.New("PROMETHEUS_MCP_TOKENS_FILE is required")
	}
	promURL := strings.TrimRight(os.Getenv("PROMETHEUS_MCP_PROM_URL"), "/")
	if promURL == "" {
		return nil, errors.New("PROMETHEUS_MCP_PROM_URL is required")
	}
	amURL := strings.TrimRight(os.Getenv("PROMETHEUS_MCP_AM_URL"), "/")
	return &config{
		BindIP:     bindIP,
		Port:       port,
		TokensFile: tokensFile,
		PromURL:    promURL,
		AMURL:      amURL,
	}, nil
}

func getenvOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// resolveBindIP returns the tailnet IPv4 when bindIP=="auto", else passes through.
func resolveBindIP(bindIP string) (string, error) {
	if bindIP != "auto" {
		return bindIP, nil
	}
	out, err := exec.Command("tailscale", "ip", "-4").Output()
	if err != nil {
		return "", fmt.Errorf("tailscale ip -4: %w", err)
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(lines) == 0 || lines[0] == "" {
		return "", errors.New("tailscale ip -4 returned no addresses")
	}
	return lines[0], nil
}

// ─── Bearer-token auth ──────────────────────────────────────────────────────

func loadTokens(path string) (map[string]string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var outer struct {
		Tokens map[string]string `json:"tokens"`
	}
	if err := json.Unmarshal(raw, &outer); err == nil && outer.Tokens != nil {
		return reverseTokenMap(outer.Tokens), nil
	}
	var flat map[string]string
	if err := json.Unmarshal(raw, &flat); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if len(flat) == 0 {
		return nil, fmt.Errorf("%s: expected non-empty token map", path)
	}
	return reverseTokenMap(flat), nil
}

func reverseTokenMap(byClient map[string]string) map[string]string {
	out := make(map[string]string, len(byClient))
	for client, tok := range byClient {
		out[tok] = client
	}
	return out
}

func bearerAuthMiddleware(tokens map[string]string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			next.ServeHTTP(w, r)
			return
		}
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(strings.ToLower(auth), "bearer ") {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing bearer token"})
			return
		}
		tok := strings.TrimSpace(auth[7:])
		tokBytes := []byte(tok)
		matched := false
		for stored := range tokens {
			if subtle.ConstantTimeCompare(tokBytes, []byte(stored)) == 1 {
				matched = true
			}
		}
		if !matched {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid token"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// ─── Upstream HTTP client (Prometheus + Alertmanager share this) ────────────

type promClient struct {
	promURL string
	amURL   string // empty = AM not configured
	hc      *http.Client
}

func newPromClient(cfg *config) *promClient {
	return &promClient{
		promURL: cfg.PromURL,
		amURL:   cfg.AMURL,
		hc:      &http.Client{Timeout: 15 * time.Second},
	}
}

// getJSON performs a GET against `base + path` with optional query params,
// returning parsed JSON (or nil for an empty body). Errors include a
// trimmed body snippet on non-2xx, mirroring the Python helper.
func (p *promClient) getJSON(
	ctx context.Context, base, path string, params url.Values,
) (any, error) {
	u := fmt.Sprintf("%s/%s", base, strings.TrimLeft(path, "/"))
	if params != nil && len(params) > 0 {
		u += "?" + params.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return nil, err
	}
	resp, err := p.hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("GET %s: %w", path, err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes))
	if resp.StatusCode >= 400 {
		snippet := string(respBody)
		if len(snippet) > 500 {
			snippet = snippet[:500]
		}
		return nil, fmt.Errorf("GET %s -> %d: %s", path, resp.StatusCode, snippet)
	}
	if len(respBody) == 0 {
		return nil, nil
	}
	var parsed any
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}
	return parsed, nil
}

// promGet wraps a Prometheus /api/v1/* GET. Returns the unwrapped `data`
// payload when the response is `{status: "success", data: ...}` (the
// standard Prometheus wrapper).
func (p *promClient) promGet(
	ctx context.Context, path string, params url.Values,
) (any, error) {
	resp, err := p.getJSON(ctx, p.promURL, path, params)
	if err != nil {
		return nil, err
	}
	return unwrap(resp), nil
}

// amGet wraps an Alertmanager /api/v2/* GET. Returns the body verbatim
// (Alertmanager doesn't wrap responses the way Prometheus does).
func (p *promClient) amGet(
	ctx context.Context, path string, params url.Values,
) (any, error) {
	if p.amURL == "" {
		return nil, errors.New("alertmanager not configured — set PROMETHEUS_MCP_AM_URL")
	}
	return p.getJSON(ctx, p.amURL, path, params)
}

// unwrap pulls `.data` out of a `{status: "success", data: ...}` envelope.
func unwrap(resp any) any {
	m, ok := resp.(map[string]any)
	if !ok {
		return resp
	}
	if status, _ := m["status"].(string); status == "success" {
		if data, present := m["data"]; present {
			return data
		}
	}
	return resp
}

// ─── Tool result helpers ────────────────────────────────────────────────────

func toolResultJSON(v any) *mcp.CallToolResult {
	b, err := json.Marshal(v)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("encode result: %v", err))
	}
	// Structured + text fallback. MCP structuredContent must be an object, so
	// wrap bare values under "result" (matches FastMCP; clients unwrap).
	structured := any(v)
	if _, isMap := v.(map[string]any); !isMap {
		structured = map[string]any{"result": v}
	}
	return mcp.NewToolResultStructured(structured, string(b))
}

func toolErr(err error) *mcp.CallToolResult {
	return mcp.NewToolResultError(err.Error())
}

// ─── Prometheus tool handlers ───────────────────────────────────────────────

func handlerQuery(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		promql, err := req.RequireString("promql")
		if err != nil {
			return toolErr(err), nil
		}
		params := url.Values{}
		params.Set("query", promql)
		if t := strings.TrimSpace(req.GetString("time", "")); t != "" {
			params.Set("time", t)
		}
		out, err := p.promGet(ctx, "/api/v1/query", params)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerQueryRange(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		promql, err := req.RequireString("promql")
		if err != nil {
			return toolErr(err), nil
		}
		start, err := req.RequireString("start")
		if err != nil {
			return toolErr(err), nil
		}
		end, err := req.RequireString("end")
		if err != nil {
			return toolErr(err), nil
		}
		step, err := req.RequireString("step")
		if err != nil {
			return toolErr(err), nil
		}
		params := url.Values{}
		params.Set("query", promql)
		params.Set("start", start)
		params.Set("end", end)
		params.Set("step", step)
		out, err := p.promGet(ctx, "/api/v1/query_range", params)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerAlerts(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		out, err := p.promGet(ctx, "/api/v1/alerts", nil)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerRules(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var params url.Values
		if rt := strings.TrimSpace(req.GetString("rule_type", "")); rt != "" {
			params = url.Values{}
			params.Set("type", rt)
		}
		out, err := p.promGet(ctx, "/api/v1/rules", params)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerTargets(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		var params url.Values
		if state := strings.TrimSpace(req.GetString("state", "")); state != "" {
			params = url.Values{}
			params.Set("state", state)
		}
		out, err := p.promGet(ctx, "/api/v1/targets", params)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerLabelNames(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		params := url.Values{}
		if s := strings.TrimSpace(req.GetString("start", "")); s != "" {
			params.Set("start", s)
		}
		if e := strings.TrimSpace(req.GetString("end", "")); e != "" {
			params.Set("end", e)
		}
		out, err := p.promGet(ctx, "/api/v1/labels", params)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerLabelValues(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		label, err := req.RequireString("label")
		if err != nil {
			return toolErr(err), nil
		}
		params := url.Values{}
		if s := strings.TrimSpace(req.GetString("start", "")); s != "" {
			params.Set("start", s)
		}
		if e := strings.TrimSpace(req.GetString("end", "")); e != "" {
			params.Set("end", e)
		}
		out, err := p.promGet(ctx, fmt.Sprintf("/api/v1/label/%s/values", label), params)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerSeries(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		selectorsArg, ok := req.GetArguments()["selectors"].([]any)
		if !ok {
			return toolErr(errors.New("selectors: required (array of strings)")), nil
		}
		params := url.Values{}
		for _, v := range selectorsArg {
			s, ok := v.(string)
			if !ok {
				return toolErr(fmt.Errorf("selectors: expected strings, got %T", v)), nil
			}
			params.Add("match[]", s)
		}
		if s := strings.TrimSpace(req.GetString("start", "")); s != "" {
			params.Set("start", s)
		}
		if e := strings.TrimSpace(req.GetString("end", "")); e != "" {
			params.Set("end", e)
		}
		out, err := p.promGet(ctx, "/api/v1/series", params)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerMetricMetadata(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		params := url.Values{}
		if m := strings.TrimSpace(req.GetString("metric", "")); m != "" {
			params.Set("metric", m)
		}
		if limit := req.GetInt("limit", 0); limit != 0 {
			params.Set("limit", strconv.Itoa(limit))
		}
		out, err := p.promGet(ctx, "/api/v1/metadata", params)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerRuntimeInfo(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		runtime, err := p.promGet(ctx, "/api/v1/status/runtimeinfo", nil)
		if err != nil {
			return toolErr(err), nil
		}
		build, err := p.promGet(ctx, "/api/v1/status/buildinfo", nil)
		if err != nil {
			return toolErr(err), nil
		}
		flags, err := p.promGet(ctx, "/api/v1/status/flags", nil)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(map[string]any{
			"runtime": runtime,
			"build":   build,
			"flags":   flags,
		}), nil
	}
}

// ─── Alertmanager tool handlers (gated on AMURL) ────────────────────────────

func handlerAlertmanagerAlerts(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		active := true
		silenced := false
		inhibited := false
		if v, ok := req.GetArguments()["active"].(bool); ok {
			active = v
		}
		if v, ok := req.GetArguments()["silenced"].(bool); ok {
			silenced = v
		}
		if v, ok := req.GetArguments()["inhibited"].(bool); ok {
			inhibited = v
		}
		params := url.Values{}
		params.Set("active", strconv.FormatBool(active))
		params.Set("silenced", strconv.FormatBool(silenced))
		params.Set("inhibited", strconv.FormatBool(inhibited))
		out, err := p.amGet(ctx, "/api/v2/alerts", params)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerAlertmanagerSilences(p *promClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		out, err := p.amGet(ctx, "/api/v2/silences", nil)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

// ─── Tool registration ──────────────────────────────────────────────────────

func registerTools(s *server.MCPServer, p *promClient, amEnabled bool) {
	s.AddTool(mcp.NewTool("query",
		mcp.WithDescription("Run an instant PromQL query against Prometheus. Returns Prometheus's `data` payload — a `{resultType, result}` shape where `result` is a list of `{metric, value: [ts, val]}` for vector/scalar queries."),
		mcp.WithString("promql",
			mcp.Description("The PromQL expression, e.g. `up`, `rate(http_requests_total[5m])`."),
			mcp.Required()),
		mcp.WithString("time",
			mcp.Description("Optional evaluation timestamp (RFC3339 or unix seconds). Defaults to now.")),
	), handlerQuery(p))

	s.AddTool(mcp.NewTool("query_range",
		mcp.WithDescription("Run a PromQL range query and return a time-series matrix. Returns `{resultType: \"matrix\", result: [{metric, values: [[ts, val], ...]}]}`."),
		mcp.WithString("promql",
			mcp.Description("The PromQL expression."),
			mcp.Required()),
		mcp.WithString("start",
			mcp.Description("Start timestamp (RFC3339 or unix seconds)."),
			mcp.Required()),
		mcp.WithString("end",
			mcp.Description("End timestamp (RFC3339 or unix seconds)."),
			mcp.Required()),
		mcp.WithString("step",
			mcp.Description("Query resolution (e.g. `15s`, `1m`, `5m`)."),
			mcp.Required()),
	), handlerQueryRange(p))

	s.AddTool(mcp.NewTool("alerts",
		mcp.WithDescription("List currently active alerts as Prometheus sees them. Returns `{alerts: [{labels, annotations, state, activeAt, value}]}`. State is `pending` or `firing`. Use `alertmanager_alerts` for the Alertmanager view (which adds silencing/inhibition state)."),
	), handlerAlerts(p))

	s.AddTool(mcp.NewTool("rules",
		mcp.WithDescription("List configured alerting and recording rules grouped by file. Returns `{groups: [{name, file, rules: [{name, query, ...}]}]}`."),
		mcp.WithString("rule_type",
			mcp.Description("Optional filter — `alert` or `record`. Default = both.")),
	), handlerRules(p))

	s.AddTool(mcp.NewTool("targets",
		mcp.WithDescription("List scrape targets and their last-scrape status. For each `activeTargets[*]`, key fields: `health` (up|down|unknown), `lastError`, `lastScrape`, `scrapeUrl`, `labels`. Primary use: \"is anything down right now?\"."),
		mcp.WithString("state",
			mcp.Description("Optional filter — `active`, `dropped`, or `any` (default `any`).")),
	), handlerTargets(p))

	s.AddTool(mcp.NewTool("label_names",
		mcp.WithDescription("List every label name Prometheus knows about, optionally restricted to a time window. Useful as a discovery step before `label_values` or when constructing a query."),
		mcp.WithString("start",
			mcp.Description("Optional start timestamp.")),
		mcp.WithString("end",
			mcp.Description("Optional end timestamp.")),
	), handlerLabelNames(p))

	s.AddTool(mcp.NewTool("label_values",
		mcp.WithDescription("List all values seen for a given label. Example: `label_values(\"job\")` returns every scrape-job slug."),
		mcp.WithString("label",
			mcp.Description("Label name to enumerate values for."),
			mcp.Required()),
		mcp.WithString("start",
			mcp.Description("Optional start timestamp.")),
		mcp.WithString("end",
			mcp.Description("Optional end timestamp.")),
	), handlerLabelValues(p))

	s.AddTool(mcp.NewTool("series",
		mcp.WithDescription("Find time series matching one or more label selectors. Returns the matched series as `[{__name__, label1: ..., ...}]`."),
		mcp.WithArray("selectors",
			mcp.Description("Array of selector strings like `up{job=\"node\"}` or `node_cpu_seconds_total{instance=\"saruman:9100\"}`."),
			mcp.Required()),
		mcp.WithString("start",
			mcp.Description("Optional start timestamp.")),
		mcp.WithString("end",
			mcp.Description("Optional end timestamp.")),
	), handlerSeries(p))

	s.AddTool(mcp.NewTool("metric_metadata",
		mcp.WithDescription("Fetch HELP text and TYPE for metrics. With no args, returns every metric's metadata (use `limit`). With `metric`, returns only that metric. Returned shape: `{<metric>: [{type, help, unit}]}`."),
		mcp.WithString("metric",
			mcp.Description("Optional metric name to filter to.")),
		mcp.WithNumber("limit",
			mcp.Description("Optional cap on the number of metrics returned.")),
	), handlerMetricMetadata(p))

	s.AddTool(mcp.NewTool("runtime_info",
		mcp.WithDescription("Prometheus's own runtime + build info: version, storage retention, chunk count, WAL stats, plus build info and flags. Cheap call; useful for \"is the Prometheus server itself healthy?\" probes."),
	), handlerRuntimeInfo(p))

	if amEnabled {
		s.AddTool(mcp.NewTool("alertmanager_alerts",
			mcp.WithDescription("Alerts as Alertmanager sees them — includes silence + inhibition state that Prometheus's own `/alerts` endpoint doesn't surface. By default returns only currently-firing, non-silenced, non-inhibited alerts."),
			mcp.WithBoolean("active",
				mcp.Description("Include currently-firing alerts (default true).")),
			mcp.WithBoolean("silenced",
				mcp.Description("Include silenced alerts (default false).")),
			mcp.WithBoolean("inhibited",
				mcp.Description("Include inhibited alerts (default false).")),
		), handlerAlertmanagerAlerts(p))

		s.AddTool(mcp.NewTool("alertmanager_silences",
			mcp.WithDescription("List active silences (alert-suppression windows). Useful before paging on something — confirm it isn't already known/silenced."),
		), handlerAlertmanagerSilences(p))
	}
}

// ─── HTTP endpoints (non-MCP) ───────────────────────────────────────────────

func healthHandler(cfg *config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body := map[string]any{
			"status":         "ok",
			"prometheus_url": cfg.PromURL,
		}
		if cfg.AMURL != "" {
			body["alertmanager_url"] = cfg.AMURL
		} else {
			body["alertmanager_url"] = nil
		}
		writeJSON(w, http.StatusOK, body)
	}
}

func versionHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"name": name, "version": version})
	}
}

// ─── main ───────────────────────────────────────────────────────────────────

func main() {
	if len(os.Args) >= 2 && os.Args[1] == "--version" {
		fmt.Printf("%s %s\n", name, version)
		return
	}

	logLevel := slog.LevelInfo
	if v := os.Getenv("PROMETHEUS_MCP_LOG_LEVEL"); strings.EqualFold(v, "debug") {
		logLevel = slog.LevelDebug
	}
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: logLevel})))

	cfg, err := loadConfig()
	if err != nil {
		slog.Error("config", "err", err)
		os.Exit(1)
	}
	tokens, err := loadTokens(cfg.TokensFile)
	if err != nil {
		slog.Error("tokens", "err", err)
		os.Exit(1)
	}
	bindIP, err := resolveBindIP(cfg.BindIP)
	if err != nil {
		slog.Error("bind ip", "err", err)
		os.Exit(1)
	}

	p := newPromClient(cfg)
	amEnabled := cfg.AMURL != ""

	mcpServer := server.NewMCPServer(name, version,
		server.WithToolCapabilities(false),
	)
	registerTools(mcpServer, p, amEnabled)

	streamable := server.NewStreamableHTTPServer(mcpServer)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler(cfg))
	mux.HandleFunc("/version", versionHandler())
	mux.Handle("/mcp", streamable)
	mux.Handle("/mcp/", streamable)

	authed := bearerAuthMiddleware(tokens, mux)

	addr := fmt.Sprintf("%s:%d", bindIP, cfg.Port)
	amLog := cfg.AMURL
	if amLog == "" {
		amLog = "<disabled>"
	}
	slog.Info("starting",
		"name", name, "version", version,
		"addr", addr,
		"prometheus_url", cfg.PromURL,
		"alertmanager_url", amLog,
		"tokens", len(tokens),
	)

	srv := &http.Server{
		Addr:    addr,
		Handler: authed,
	}
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("listen", "err", err)
		os.Exit(1)
	}
}
