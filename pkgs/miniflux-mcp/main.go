// miniflux-mcp — MCP server fronting a Miniflux RSS reader instance.
//
// Behavioral parity with the previous Python implementation:
//   - Streamable-HTTP MCP transport at /mcp
//   - Bearer-token auth (tokens loaded from a sops-rendered JSON file)
//   - /health (unauthenticated) verifies upstream Miniflux reachability
//   - /version (bearer-required) returns name + version
//   - 14 tools mirroring the Python tool surface 1:1
package main

import (
	"context"
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
	name    = "miniflux-mcp"
	version = "0.2.0"
)

// ─── Configuration ──────────────────────────────────────────────────────────

type config struct {
	BindIP        string
	Port          int
	TokensFile    string
	MinifluxURL   string
	MinifluxToken string
}

func loadConfig() (*config, error) {
	bindIP := getenvOr("MINIFLUX_MCP_BIND_IP", "auto")
	portStr := getenvOr("MINIFLUX_MCP_PORT", "4284")
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("MINIFLUX_MCP_PORT=%q: %w", portStr, err)
	}
	tokensFile := os.Getenv("MINIFLUX_MCP_TOKENS_FILE")
	if tokensFile == "" {
		return nil, errors.New("MINIFLUX_MCP_TOKENS_FILE is required")
	}
	mfxURL := strings.TrimRight(os.Getenv("MINIFLUX_MCP_MINIFLUX_URL"), "/")
	if mfxURL == "" {
		return nil, errors.New("MINIFLUX_MCP_MINIFLUX_URL is required")
	}
	mfxTok := os.Getenv("MINIFLUX_MCP_MINIFLUX_TOKEN")
	if mfxTok == "" {
		return nil, errors.New("MINIFLUX_MCP_MINIFLUX_TOKEN is required")
	}
	return &config{
		BindIP:        bindIP,
		Port:          port,
		TokensFile:    tokensFile,
		MinifluxURL:   mfxURL,
		MinifluxToken: mfxTok,
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

// loadTokens reads the JSON tokens file and returns a map from token to client name.
// Source file shape: {"tokens": {"client_name": "hex_token", ...}} or the inner map.
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

// bearerAuthMiddleware enforces bearer-token auth on all paths except /health.
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
		if _, ok := tokens[tok]; !ok {
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

// ─── Miniflux client ────────────────────────────────────────────────────────

type minifluxClient struct {
	baseURL string
	token   string
	hc      *http.Client
}

func newMinifluxClient(cfg *config) *minifluxClient {
	return &minifluxClient{
		baseURL: cfg.MinifluxURL,
		token:   cfg.MinifluxToken,
		hc:      &http.Client{Timeout: 15 * time.Second},
	}
}

// call performs a Miniflux v1 API request. path is relative to /v1/.
// Returns parsed JSON (or nil for empty response).
func (m *minifluxClient) call(
	ctx context.Context, method, path string,
	params url.Values, jsonBody any,
) (any, error) {
	u := fmt.Sprintf("%s/v1/%s", m.baseURL, strings.TrimLeft(path, "/"))
	if params != nil {
		u += "?" + params.Encode()
	}
	var body io.Reader
	if jsonBody != nil {
		buf, err := json.Marshal(jsonBody)
		if err != nil {
			return nil, fmt.Errorf("encode body: %w", err)
		}
		body = strings.NewReader(string(buf))
	}
	req, err := http.NewRequestWithContext(ctx, method, u, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-Auth-Token", m.token)
	if jsonBody != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := m.hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("miniflux %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 400 {
		snippet := string(respBody)
		if len(snippet) > 500 {
			snippet = snippet[:500]
		}
		return nil, fmt.Errorf("miniflux %s %s -> %d: %s", method, path, resp.StatusCode, snippet)
	}
	if len(respBody) == 0 {
		return nil, nil
	}
	var parsed any
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("parse miniflux response: %w", err)
	}
	return parsed, nil
}

// ─── Tool result helpers ────────────────────────────────────────────────────

// toolResultJSON marshals v as JSON and returns it as a text-content tool result.
// Errors propagate as MCP error results so the model sees them.
func toolResultJSON(v any) *mcp.CallToolResult {
	b, err := json.Marshal(v)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("encode result: %v", err))
	}
	return mcp.NewToolResultText(string(b))
}

func toolErr(err error) *mcp.CallToolResult {
	return mcp.NewToolResultError(err.Error())
}

// ─── Tool handlers ──────────────────────────────────────────────────────────

func handlerMe(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		out, err := mfx.call(ctx, "GET", "/me", nil, nil)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerFeedList(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		catID := req.GetInt("category_id", 0)
		path := "/feeds"
		if catID != 0 {
			path = fmt.Sprintf("/categories/%d/feeds", catID)
		}
		out, err := mfx.call(ctx, "GET", path, nil, nil)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerFeedGet(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		id, err := req.RequireInt("feed_id")
		if err != nil {
			return toolErr(err), nil
		}
		out, err := mfx.call(ctx, "GET", fmt.Sprintf("/feeds/%d", id), nil, nil)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerCategoryList(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		out, err := mfx.call(ctx, "GET", "/categories", nil, nil)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerCategoryCreate(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		title, err := req.RequireString("title")
		if err != nil {
			return toolErr(err), nil
		}
		out, err := mfx.call(ctx, "POST", "/categories", nil, map[string]string{"title": title})
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerCategoryDelete(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		id, err := req.RequireInt("category_id")
		if err != nil {
			return toolErr(err), nil
		}
		if _, err := mfx.call(ctx, "DELETE", fmt.Sprintf("/categories/%d", id), nil, nil); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(map[string]any{"category_id": id, "deleted": true}), nil
	}
}

func handlerFeedDiscover(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		u, err := req.RequireString("url")
		if err != nil {
			return toolErr(err), nil
		}
		out, err := mfx.call(ctx, "POST", "/discover", nil, map[string]string{"url": u})
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerFeedAdd(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		feedURL, err := req.RequireString("feed_url")
		if err != nil {
			return toolErr(err), nil
		}
		body := map[string]any{"feed_url": feedURL}
		if catID := req.GetInt("category_id", 0); catID != 0 {
			body["category_id"] = catID
		}
		out, err := mfx.call(ctx, "POST", "/feeds", nil, body)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerFeedDelete(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		id, err := req.RequireInt("feed_id")
		if err != nil {
			return toolErr(err), nil
		}
		if _, err := mfx.call(ctx, "DELETE", fmt.Sprintf("/feeds/%d", id), nil, nil); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(map[string]any{"feed_id": id, "deleted": true}), nil
	}
}

func handlerEntryList(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		params := url.Values{}
		params.Set("limit", strconv.Itoa(req.GetInt("limit", 50)))
		params.Set("offset", strconv.Itoa(req.GetInt("offset", 0)))
		params.Set("order", req.GetString("order", "published_at"))
		params.Set("direction", req.GetString("direction", "desc"))
		if v := req.GetString("status", ""); v != "" {
			params.Set("status", v)
		}
		if v := req.GetString("search", ""); v != "" {
			params.Set("search", v)
		}
		if starred, ok := req.GetArguments()["starred"].(bool); ok {
			if starred {
				params.Set("starred", "true")
			} else {
				params.Set("starred", "false")
			}
		}
		path := "/entries"
		if feedID := req.GetInt("feed_id", 0); feedID != 0 {
			path = fmt.Sprintf("/feeds/%d/entries", feedID)
		} else if catID := req.GetInt("category_id", 0); catID != 0 {
			path = fmt.Sprintf("/categories/%d/entries", catID)
		}
		out, err := mfx.call(ctx, "GET", path, params, nil)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerEntryGet(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		id, err := req.RequireInt("entry_id")
		if err != nil {
			return toolErr(err), nil
		}
		out, err := mfx.call(ctx, "GET", fmt.Sprintf("/entries/%d", id), nil, nil)
		if err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerEntryMarkStatus(mfx *minifluxClient, status string) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		idsArg, ok := req.GetArguments()["entry_ids"].([]any)
		if !ok {
			return toolErr(errors.New("entry_ids: required (array of integers)")), nil
		}
		ids := make([]int, 0, len(idsArg))
		for _, v := range idsArg {
			switch n := v.(type) {
			case float64:
				ids = append(ids, int(n))
			case int:
				ids = append(ids, n)
			default:
				return toolErr(fmt.Errorf("entry_ids: expected integers, got %T", v)), nil
			}
		}
		body := map[string]any{"entry_ids": ids, "status": status}
		if _, err := mfx.call(ctx, "PUT", "/entries", nil, body); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(map[string]any{"updated": ids, "status": status}), nil
	}
}

func handlerEntryStar(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		id, err := req.RequireInt("entry_id")
		if err != nil {
			return toolErr(err), nil
		}
		if _, err := mfx.call(ctx, "PUT", fmt.Sprintf("/entries/%d/bookmark", id), nil, nil); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(map[string]any{"entry_id": id, "starred": "toggled"}), nil
	}
}

func handlerFeedRefresh(mfx *minifluxClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		id, err := req.RequireInt("feed_id")
		if err != nil {
			return toolErr(err), nil
		}
		if _, err := mfx.call(ctx, "PUT", fmt.Sprintf("/feeds/%d/refresh", id), nil, nil); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(map[string]any{"feed_id": id, "refreshed": true}), nil
	}
}

// ─── Tool registration ──────────────────────────────────────────────────────

func registerTools(s *server.MCPServer, mfx *minifluxClient) {
	s.AddTool(mcp.NewTool("me",
		mcp.WithDescription("Return the current Miniflux user (whoever owns the configured API key)."),
	), handlerMe(mfx))

	s.AddTool(mcp.NewTool("feed_list",
		mcp.WithDescription("List subscribed feeds. Optionally filter to a specific category."),
		mcp.WithNumber("category_id", mcp.Description("Restrict to this category id (optional).")),
	), handlerFeedList(mfx))

	s.AddTool(mcp.NewTool("feed_get",
		mcp.WithDescription("Get a single feed by id."),
		mcp.WithNumber("feed_id", mcp.Description("Feed id."), mcp.Required()),
	), handlerFeedGet(mfx))

	s.AddTool(mcp.NewTool("category_list",
		mcp.WithDescription("List all feed categories on the account."),
	), handlerCategoryList(mfx))

	s.AddTool(mcp.NewTool("category_create",
		mcp.WithDescription("Create a new category. Miniflux rejects duplicate titles with HTTP 400."),
		mcp.WithString("title", mcp.Description("Category title."), mcp.Required()),
	), handlerCategoryCreate(mfx))

	s.AddTool(mcp.NewTool("category_delete",
		mcp.WithDescription("Delete a category. Feeds in it are reassigned to the default category."),
		mcp.WithNumber("category_id", mcp.Description("Category id."), mcp.Required()),
	), handlerCategoryDelete(mfx))

	s.AddTool(mcp.NewTool("feed_discover",
		mcp.WithDescription("Discover feeds reachable from a homepage URL. Returns candidates with {url, title, type} — pick one and pass its url to feed_add. Useful when you only have a site URL and need the feed URL."),
		mcp.WithString("url", mcp.Description("Homepage URL to scan for feeds."), mcp.Required()),
	), handlerFeedDiscover(mfx))

	s.AddTool(mcp.NewTool("feed_add",
		mcp.WithDescription("Subscribe to a feed by its direct feed URL (Atom/RSS/JSON). When category_id is omitted Miniflux files the feed under the default category. Returns {feed_id} on success; raises on duplicates."),
		mcp.WithString("feed_url", mcp.Description("Direct feed URL."), mcp.Required()),
		mcp.WithNumber("category_id", mcp.Description("Optional category id.")),
	), handlerFeedAdd(mfx))

	s.AddTool(mcp.NewTool("feed_delete",
		mcp.WithDescription("Unsubscribe from a feed permanently. Removes the feed and all its entries from the account."),
		mcp.WithNumber("feed_id", mcp.Description("Feed id."), mcp.Required()),
	), handlerFeedDelete(mfx))

	s.AddTool(mcp.NewTool("entry_list",
		mcp.WithDescription("List entries. By default returns the 50 most recent across all feeds. Filters combinable."),
		mcp.WithString("status", mcp.Description("'unread', 'read', or 'removed'.")),
		mcp.WithNumber("feed_id", mcp.Description("Restrict to one feed.")),
		mcp.WithNumber("category_id", mcp.Description("Restrict to one category.")),
		mcp.WithString("search", mcp.Description("Substring search across title + content.")),
		mcp.WithBoolean("starred", mcp.Description("Filter to starred entries only.")),
		mcp.WithNumber("limit", mcp.Description("Page size (default 50).")),
		mcp.WithNumber("offset", mcp.Description("Page offset (default 0).")),
		mcp.WithString("order", mcp.Description("Sort field; default 'published_at'.")),
		mcp.WithString("direction", mcp.Description("Sort direction; 'asc' or 'desc' (default 'desc').")),
	), handlerEntryList(mfx))

	s.AddTool(mcp.NewTool("entry_get",
		mcp.WithDescription("Fetch a single entry by id, with full content."),
		mcp.WithNumber("entry_id", mcp.Description("Entry id."), mcp.Required()),
	), handlerEntryGet(mfx))

	s.AddTool(mcp.NewTool("entry_mark_read",
		mcp.WithDescription("Mark one or more entries as read."),
		mcp.WithArray("entry_ids", mcp.Description("Array of entry ids."), mcp.Required()),
	), handlerEntryMarkStatus(mfx, "read"))

	s.AddTool(mcp.NewTool("entry_mark_unread",
		mcp.WithDescription("Mark one or more entries as unread."),
		mcp.WithArray("entry_ids", mcp.Description("Array of entry ids."), mcp.Required()),
	), handlerEntryMarkStatus(mfx, "unread"))

	s.AddTool(mcp.NewTool("entry_star",
		mcp.WithDescription("Toggle star on an entry (Miniflux's star endpoint is a toggle)."),
		mcp.WithNumber("entry_id", mcp.Description("Entry id."), mcp.Required()),
	), handlerEntryStar(mfx))

	s.AddTool(mcp.NewTool("feed_refresh",
		mcp.WithDescription("Force-refresh a feed (fetch immediately, bypassing the scheduler)."),
		mcp.WithNumber("feed_id", mcp.Description("Feed id."), mcp.Required()),
	), handlerFeedRefresh(mfx))
}

// ─── HTTP endpoints (non-MCP) ───────────────────────────────────────────────

func healthHandler(mfx *minifluxClient) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		out, err := mfx.call(r.Context(), "GET", "/me", nil, nil)
		body := map[string]any{
			"status":        "ok",
			"miniflux_url":  mfx.baseURL,
		}
		if err != nil {
			body["status"] = "degraded"
			body["errors"] = map[string]string{"miniflux": err.Error()}
		} else if userMap, ok := out.(map[string]any); ok {
			body["user"] = userMap["username"]
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
	if v := os.Getenv("MINIFLUX_MCP_LOG_LEVEL"); strings.EqualFold(v, "debug") {
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

	mfx := newMinifluxClient(cfg)

	mcpServer := server.NewMCPServer(name, version,
		server.WithToolCapabilities(false),
	)
	registerTools(mcpServer, mfx)

	streamable := server.NewStreamableHTTPServer(mcpServer)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler(mfx))
	mux.HandleFunc("/version", versionHandler())
	mux.Handle("/mcp", streamable)
	mux.Handle("/mcp/", streamable)

	authed := bearerAuthMiddleware(tokens, mux)

	addr := fmt.Sprintf("%s:%d", bindIP, cfg.Port)
	slog.Info("starting",
		"name", name, "version", version,
		"addr", addr, "miniflux_url", cfg.MinifluxURL,
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

// ctx unused (placeholder)
var _ = context.Background
