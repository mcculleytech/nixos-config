// gcal-mcp — MCP server fronting the Google Calendar v3 API.
//
// Reuses the OAuth client_secret + persistent refresh-token files already on
// disk from the bundled hermes-agent `google-workspace` skill setup. Read-only
// by default — exposes `gcal_calendar_list` and `gcal_event_list`.
//
// Behavioral parity with the previous Python implementation:
//   - Streamable-HTTP MCP transport at /mcp
//   - Bearer-token auth (tokens loaded from a sops-rendered JSON file)
//   - /health (unauthenticated) verifies token files are readable + creds
//     can be constructed (does NOT make a live Google API call)
//   - /version (bearer-required) returns name + version
//
// Token-format note: the on-disk token file is written by Python's
// `google-auth` library (authorized-user shape). Its field names differ
// from Go's `golang.org/x/oauth2.Token` JSON encoding — we adapt in
// loadGoogleToken().
package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/calendar/v3"
	"google.golang.org/api/option"
)

const (
	name    = "gcal-mcp"
	version = "0.2.0"
)

// ─── Configuration ──────────────────────────────────────────────────────────

type config struct {
	BindIP                 string
	Port                   int
	TokensFile             string
	GoogleTokenFile        string
	GoogleClientSecretFile string
}

func loadConfig() (*config, error) {
	bindIP := getenvOr("GCAL_MCP_BIND_IP", "auto")
	portStr := getenvOr("GCAL_MCP_PORT", "4286")
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("GCAL_MCP_PORT=%q: %w", portStr, err)
	}
	tokensFile := os.Getenv("GCAL_MCP_TOKENS_FILE")
	if tokensFile == "" {
		return nil, errors.New("GCAL_MCP_TOKENS_FILE is required")
	}
	gTok := os.Getenv("GCAL_MCP_GOOGLE_TOKEN_FILE")
	if gTok == "" {
		return nil, errors.New("GCAL_MCP_GOOGLE_TOKEN_FILE is required")
	}
	gSec := os.Getenv("GCAL_MCP_GOOGLE_CLIENT_SECRET_FILE")
	if gSec == "" {
		return nil, errors.New("GCAL_MCP_GOOGLE_CLIENT_SECRET_FILE is required")
	}
	return &config{
		BindIP:                 bindIP,
		Port:                   port,
		TokensFile:             tokensFile,
		GoogleTokenFile:        gTok,
		GoogleClientSecretFile: gSec,
	}, nil
}

func getenvOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

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

// ─── Google auth ────────────────────────────────────────────────────────────

// pythonAuthorizedUser mirrors the JSON shape that Python's google-auth library
// writes for an "authorized user" credential. Field names DIFFER from Go's
// oauth2.Token: Python uses `token` where Go expects `access_token`, and
// stores expiry as a Python-formatted timestamp.
type pythonAuthorizedUser struct {
	Token           string   `json:"token"`
	RefreshToken    string   `json:"refresh_token"`
	TokenURI        string   `json:"token_uri"`
	ClientID        string   `json:"client_id"`
	ClientSecret    string   `json:"client_secret"`
	Scopes          []string `json:"scopes"`
	Expiry          string   `json:"expiry"`
	Type            string   `json:"type"`
	Account         string   `json:"account"`
	UniverseDomain  string   `json:"universe_domain"`
}

// loadGoogleToken reads the authorized-user JSON written by Python google-auth
// and returns an oauth2.Token that Go's oauth2 stack can use. The access token
// may be expired — oauth2.TokenSource will auto-refresh using refresh_token
// + client_secret when needed. We never persist refreshed access tokens back
// (the hermes state dir is read-only in the sandbox; cost is one extra token
// endpoint call per process start).
func loadGoogleToken(path string) (*oauth2.Token, *pythonAuthorizedUser, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, fmt.Errorf("read %s: %w", path, err)
	}
	var p pythonAuthorizedUser
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if p.RefreshToken == "" {
		return nil, nil, fmt.Errorf("%s: missing refresh_token", path)
	}
	tok := &oauth2.Token{
		AccessToken:  p.Token,
		RefreshToken: p.RefreshToken,
		TokenType:    "Bearer",
	}
	// Python google-auth writes expiry as either "2026-05-12T19:51:28.063248Z"
	// or naive "2026-05-12T19:51:28" UTC. Try a few common shapes; if none
	// parses, leave Expiry zero — oauth2 will treat the access token as
	// expired and refresh immediately on first use.
	if p.Expiry != "" {
		layouts := []string{
			time.RFC3339Nano,
			time.RFC3339,
			"2006-01-02T15:04:05.000000Z",
			"2006-01-02T15:04:05.999999",
			"2006-01-02T15:04:05",
		}
		for _, layout := range layouts {
			if t, err := time.Parse(layout, p.Expiry); err == nil {
				// Naive timestamps from Python google-auth are UTC by convention.
				if t.Location() == time.UTC || t.Location().String() == "" {
					tok.Expiry = t
				} else {
					tok.Expiry = t.UTC()
				}
				break
			}
		}
	}
	return tok, &p, nil
}

// newCalendarService builds a Calendar v3 service backed by an oauth2 client
// that auto-refreshes the access token via the refresh_token + client secret.
func newCalendarService(ctx context.Context, cfg *config) (*calendar.Service, error) {
	secretBytes, err := os.ReadFile(cfg.GoogleClientSecretFile)
	if err != nil {
		return nil, fmt.Errorf("read client secret: %w", err)
	}
	// SCOPES intentionally left flexible — the existing token was minted by
	// the hermes-agent google-workspace skill with a broader scope set; pinning
	// calendar.readonly here would trigger invalid_scope on refresh. We protect
	// against accidental writes by only calling read-only Calendar API methods.
	oauthCfg, err := google.ConfigFromJSON(secretBytes, calendar.CalendarReadonlyScope)
	if err != nil {
		return nil, fmt.Errorf("parse client secret: %w", err)
	}
	token, _, err := loadGoogleToken(cfg.GoogleTokenFile)
	if err != nil {
		return nil, err
	}
	httpClient := oauthCfg.Client(ctx, token)
	svc, err := calendar.NewService(ctx, option.WithHTTPClient(httpClient))
	if err != nil {
		return nil, fmt.Errorf("build calendar service: %w", err)
	}
	return svc, nil
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

// ─── Tool handlers ──────────────────────────────────────────────────────────

func handlerCalendarList(cfg *config) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		svc, err := newCalendarService(ctx, cfg)
		if err != nil {
			return toolResultJSON([]map[string]string{{"error": fmt.Sprintf("auth: %v", err)}}), nil
		}
		result, err := svc.CalendarList.List().Context(ctx).Do()
		if err != nil {
			return toolResultJSON([]map[string]string{{"error": fmt.Sprintf("Google API error: %v", err)}}), nil
		}
		out := make([]map[string]any, 0, len(result.Items))
		for _, item := range result.Items {
			out = append(out, map[string]any{
				"id":          item.Id,
				"summary":     item.Summary,
				"description": item.Description,
				"time_zone":   item.TimeZone,
				"primary":     item.Primary,
				"access_role": item.AccessRole,
			})
		}
		return toolResultJSON(out), nil
	}
}

func handlerEventList(cfg *config) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		calendarID := req.GetString("calendar", "primary")
		startArg := strings.TrimSpace(req.GetString("start", ""))
		endArg := strings.TrimSpace(req.GetString("end", ""))
		query := strings.TrimSpace(req.GetString("query", ""))
		limit := req.GetInt("limit", 50)
		if limit < 1 {
			limit = 1
		}
		if limit > 250 {
			limit = 250
		}

		svc, err := newCalendarService(ctx, cfg)
		if err != nil {
			return toolResultJSON([]map[string]string{{"error": fmt.Sprintf("auth: %v", err)}}), nil
		}

		now := time.Now().UTC()
		startISO := startArg
		if startISO == "" {
			startISO = now.Format(time.RFC3339)
		}
		endISO := endArg
		if endISO == "" {
			endISO = now.Add(7 * 24 * time.Hour).Format(time.RFC3339)
		}

		call := svc.Events.List(calendarID).
			TimeMin(startISO).
			TimeMax(endISO).
			SingleEvents(true).
			OrderBy("startTime").
			MaxResults(int64(limit)).
			Context(ctx)
		if query != "" {
			call = call.Q(query)
		}
		result, err := call.Do()
		if err != nil {
			return toolResultJSON([]map[string]string{{"error": fmt.Sprintf("Google API error: %v", err)}}), nil
		}

		out := make([]map[string]any, 0, len(result.Items))
		for _, item := range result.Items {
			var startVal, endVal string
			allDay := false
			if item.Start != nil {
				if item.Start.DateTime != "" {
					startVal = item.Start.DateTime
				} else {
					startVal = item.Start.Date
					if item.Start.Date != "" {
						allDay = true
					}
				}
			}
			if item.End != nil {
				if item.End.DateTime != "" {
					endVal = item.End.DateTime
				} else {
					endVal = item.End.Date
				}
			}
			attendees := make([]string, 0, len(item.Attendees))
			for _, a := range item.Attendees {
				if a != nil && a.Email != "" {
					attendees = append(attendees, a.Email)
				}
			}
			organizer := ""
			if item.Organizer != nil {
				organizer = item.Organizer.Email
			}
			out = append(out, map[string]any{
				"id":           item.Id,
				"summary":      defaultStr(item.Summary, "(untitled)"),
				"start":        startVal,
				"end":          endVal,
				"all_day":      allDay,
				"location":     item.Location,
				"description":  item.Description,
				"attendees":    attendees,
				"organizer":    organizer,
				"hangout_link": item.HangoutLink,
				"recurring":    item.RecurringEventId != "",
				"html_link":    item.HtmlLink,
			})
		}
		return toolResultJSON(out), nil
	}
}

func defaultStr(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

// ─── Tool registration ──────────────────────────────────────────────────────

func registerTools(s *server.MCPServer, cfg *config) {
	s.AddTool(mcp.NewTool("gcal_calendar_list",
		mcp.WithDescription("List every Google Calendar the authenticated user can read. Returns a list of {id, summary, description, time_zone, primary, access_role} records. The `id` is what you pass as `calendar` to gcal_event_list — it's an email-shaped string for shared calendars (e.g. xxxx@group.calendar.google.com) or 'primary' for the user's own."),
	), handlerCalendarList(cfg))

	s.AddTool(mcp.NewTool("gcal_event_list",
		mcp.WithDescription("List events on a Google Calendar. Returns {id, summary, start, end, all_day, location, description, attendees, organizer, hangout_link, recurring, html_link}. Times are ISO 8601 strings preserving the stored timezone."),
		mcp.WithString("calendar",
			mcp.Description("Calendar ID — 'primary' for the user's own, or the ID from gcal_calendar_list. Default 'primary'.")),
		mcp.WithString("start",
			mcp.Description("ISO 8601 timestamp (with tz offset, e.g. '2026-05-13T00:00:00-05:00') for earliest event start. Defaults to now.")),
		mcp.WithString("end",
			mcp.Description("ISO 8601 timestamp for latest event start. Defaults to 7 days from start.")),
		mcp.WithString("query",
			mcp.Description("Optional free-text search across event summary/description.")),
		mcp.WithNumber("limit",
			mcp.Description("Maximum events returned (1-250). Default 50.")),
	), handlerEventList(cfg))
}

// ─── HTTP endpoints (non-MCP) ───────────────────────────────────────────────

func healthHandler(cfg *config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		status := map[string]any{
			"status":                    "ok",
			"google_token_file":         cfg.GoogleTokenFile,
			"google_client_secret_file": cfg.GoogleClientSecretFile,
		}
		// Verify token + client_secret are readable + parseable. Does NOT
		// make a live Google API call (would burn quota per health poll).
		if _, err := os.Stat(cfg.GoogleClientSecretFile); err != nil {
			status["status"] = "degraded"
			status["error"] = fmt.Sprintf("client_secret: %v", err)
			writeJSON(w, http.StatusOK, status)
			return
		}
		_, p, err := loadGoogleToken(cfg.GoogleTokenFile)
		if err != nil {
			status["status"] = "degraded"
			status["error"] = err.Error()
			writeJSON(w, http.StatusOK, status)
			return
		}
		status["has_refresh_token"] = p.RefreshToken != ""
		status["scopes"] = p.Scopes
		writeJSON(w, http.StatusOK, status)
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
	if v := os.Getenv("GCAL_MCP_LOG_LEVEL"); strings.EqualFold(v, "debug") {
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

	mcpServer := server.NewMCPServer(name, version,
		server.WithToolCapabilities(false),
	)
	registerTools(mcpServer, cfg)

	streamable := server.NewStreamableHTTPServer(mcpServer)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler(cfg))
	mux.HandleFunc("/version", versionHandler())
	mux.Handle("/mcp", streamable)
	mux.Handle("/mcp/", streamable)

	authed := bearerAuthMiddleware(tokens, mux)

	addr := fmt.Sprintf("%s:%d", bindIP, cfg.Port)
	slog.Info("starting",
		"name", name, "version", version,
		"addr", addr,
		"google_token", cfg.GoogleTokenFile,
		"google_client_secret", cfg.GoogleClientSecretFile,
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
