// signal-mcp — Outbound Signal messaging MCP with a mandatory two-step
// approval gate.
//
// Wraps a local signal-cli HTTP JSON-RPC daemon. Every outbound message
// must first be queued via `signal_send_message` (which only INSERTs into a
// persistent SQLite `pending` table) and then explicitly approved via
// `signal_pending_approve` before signal-cli actually transmits it.
//
// There is no direct-send path. The only place that calls signal-cli's
// `send` RPC is `signal_pending_approve`, and only for rows whose status
// is still 'pending'. This is structural, not advisory.
//
// Behavioral parity with the previous Python implementation:
//   - Streamable-HTTP MCP transport at /mcp
//   - Bearer-token auth (sops-rendered JSON token map)
//   - /health (unauthenticated) verifies DB + signal-cli reachability
//   - /version (bearer-required) returns name + version
//   - SQLite schema matches the Python SCHEMA constant exactly
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
	_ "modernc.org/sqlite"
)

const (
	name    = "signal-mcp"
	version = "0.2.0"
)

// ─── Configuration ──────────────────────────────────────────────────────────

type config struct {
	BindIP         string
	Port           int
	TokensFile     string
	SignalHTTPURL  string
	SignalAccount  string
	DBPath         string
}

func loadConfig() (*config, error) {
	bindIP := getenvOr("SIGNAL_MCP_BIND_IP", "auto")
	portStr := getenvOr("SIGNAL_MCP_PORT", "4282")
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("SIGNAL_MCP_PORT=%q: %w", portStr, err)
	}
	tokensFile := os.Getenv("SIGNAL_MCP_TOKENS_FILE")
	if tokensFile == "" {
		return nil, errors.New("SIGNAL_MCP_TOKENS_FILE is required")
	}
	signalURL := strings.TrimRight(getenvOr("SIGNAL_MCP_SIGNAL_HTTP_URL", "http://127.0.0.1:8088"), "/")
	signalAccount := os.Getenv("SIGNAL_MCP_SIGNAL_ACCOUNT")
	if signalAccount == "" {
		return nil, errors.New("SIGNAL_MCP_SIGNAL_ACCOUNT is required")
	}
	dbPath := getenvOr("SIGNAL_MCP_DB", "/var/lib/signal-mcp/pending.db")
	return &config{
		BindIP:        bindIP,
		Port:          port,
		TokensFile:    tokensFile,
		SignalHTTPURL: signalURL,
		SignalAccount: signalAccount,
		DBPath:        dbPath,
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

// ─── Persistence ────────────────────────────────────────────────────────────
//
// SCHEMA must match the previous Python implementation byte-for-byte —
// existing pending.db files are reused across the port.

const schemaSQL = `
CREATE TABLE IF NOT EXISTS pending (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  recipient    TEXT NOT NULL,
  body         TEXT NOT NULL,
  created_at   TEXT NOT NULL,
  created_by   TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending',
  status_at    TEXT,
  status_by    TEXT,
  status_note  TEXT,
  send_result  TEXT
);
`

func openDB(path string) (*sql.DB, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return nil, fmt.Errorf("mkdir %s: %w", filepath.Dir(path), err)
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open sqlite %s: %w", path, err)
	}
	if _, err := db.Exec(schemaSQL); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("init schema: %w", err)
	}
	return db, nil
}

// pendingRow models a single row of the `pending` table. Pointer-typed columns
// are nullable in the schema.
type pendingRow struct {
	ID         int64   `json:"id"`
	Recipient  string  `json:"recipient"`
	Body       string  `json:"body"`
	CreatedAt  string  `json:"created_at"`
	CreatedBy  string  `json:"created_by"`
	Status     string  `json:"status"`
	StatusAt   *string `json:"status_at"`
	StatusBy   *string `json:"status_by"`
	StatusNote *string `json:"status_note"`
	SendResult *string `json:"send_result"`
}

func scanPendingRow(scanner interface {
	Scan(dest ...any) error
}) (*pendingRow, error) {
	var r pendingRow
	if err := scanner.Scan(
		&r.ID, &r.Recipient, &r.Body, &r.CreatedAt, &r.CreatedBy,
		&r.Status, &r.StatusAt, &r.StatusBy, &r.StatusNote, &r.SendResult,
	); err != nil {
		return nil, err
	}
	return &r, nil
}

// ─── signal-cli JSON-RPC client ─────────────────────────────────────────────

type signalClient struct {
	url     string
	account string
	hc      *http.Client
}

func newSignalClient(cfg *config) *signalClient {
	return &signalClient{
		url:     cfg.SignalHTTPURL,
		account: cfg.SignalAccount,
		hc:      &http.Client{Timeout: 30 * time.Second},
	}
}

type rpcError struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data,omitempty"`
}

func (e *rpcError) String() string {
	if e == nil {
		return ""
	}
	if len(e.Data) > 0 {
		return fmt.Sprintf("code=%d message=%s data=%s", e.Code, e.Message, string(e.Data))
	}
	return fmt.Sprintf("code=%d message=%s", e.Code, e.Message)
}

type rpcResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      int             `json:"id"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

// rpc calls a signal-cli JSON-RPC method. params is merged with the bot
// account (passed as `account`). Returns the raw `result` JSON or an error.
func (s *signalClient) rpc(ctx context.Context, method string, params map[string]any) (json.RawMessage, error) {
	merged := map[string]any{"account": s.account}
	for k, v := range params {
		merged[k] = v
	}
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  method,
		"params":  merged,
	})
	if err != nil {
		return nil, fmt.Errorf("encode rpc body: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", s.url+"/api/v1/rpc", strings.NewReader(string(body)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("signal-cli RPC %s: %w", method, err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		snippet := string(respBody)
		if len(snippet) > 500 {
			snippet = snippet[:500]
		}
		return nil, fmt.Errorf("signal-cli RPC %s -> HTTP %d: %s", method, resp.StatusCode, snippet)
	}
	var parsed rpcResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("parse signal-cli response: %w", err)
	}
	if parsed.Error != nil {
		return nil, fmt.Errorf("signal-cli RPC %s error: %s", method, parsed.Error.String())
	}
	return parsed.Result, nil
}

// ─── Tool result helpers ────────────────────────────────────────────────────

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

func nowUTC() string {
	return time.Now().UTC().Format(time.RFC3339Nano)
}

// ─── Tool handlers ──────────────────────────────────────────────────────────

// signal_send_message — QUEUE-ONLY. Never calls signal-cli. Inserts a row
// into `pending` and returns the new pending_id.
func handlerSignalSendMessage(db *sql.DB) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		recipient := strings.TrimSpace(req.GetString("recipient", ""))
		body := req.GetString("body", "")
		if recipient == "" || body == "" {
			return toolResultJSON(map[string]string{"error": "recipient and body are required"}), nil
		}
		res, err := db.ExecContext(ctx,
			"INSERT INTO pending (recipient, body, created_at, created_by) VALUES (?, ?, ?, ?)",
			recipient, body, nowUTC(), "agent",
		)
		if err != nil {
			return toolErr(fmt.Errorf("insert pending: %w", err)), nil
		}
		pid, err := res.LastInsertId()
		if err != nil {
			return toolErr(fmt.Errorf("last insert id: %w", err)), nil
		}
		slog.Info("queued pending message", "id", pid, "to", recipient, "len", len(body))
		return toolResultJSON(map[string]any{
			"pending_id": pid,
			"status":     "pending",
			"recipient":  recipient,
			"body":       body,
			"next_step": "Show this pending entry to the operator (a human). After they " +
				"explicitly confirm, call signal_pending_approve(pending_id).",
		}), nil
	}
}

// signal_pending_list — read-only list of rows from `pending`.
func handlerSignalPendingList(db *sql.DB) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		status := req.GetString("status", "pending")
		limit := req.GetInt("limit", 50)

		var rows *sql.Rows
		var err error
		if status == "" || status == "all" {
			rows, err = db.QueryContext(ctx,
				"SELECT id, recipient, body, created_at, created_by, status, status_at, status_by, status_note, send_result "+
					"FROM pending ORDER BY id DESC LIMIT ?", limit)
		} else {
			rows, err = db.QueryContext(ctx,
				"SELECT id, recipient, body, created_at, created_by, status, status_at, status_by, status_note, send_result "+
					"FROM pending WHERE status = ? ORDER BY id DESC LIMIT ?", status, limit)
		}
		if err != nil {
			return toolErr(fmt.Errorf("query pending: %w", err)), nil
		}
		defer rows.Close()

		out := []*pendingRow{}
		for rows.Next() {
			r, err := scanPendingRow(rows)
			if err != nil {
				return toolErr(fmt.Errorf("scan pending: %w", err)), nil
			}
			out = append(out, r)
		}
		if err := rows.Err(); err != nil {
			return toolErr(fmt.Errorf("iterate pending: %w", err)), nil
		}
		return toolResultJSON(out), nil
	}
}

// signal_pending_approve — THE ONLY PATH TO SENDING. Fetches the row,
// verifies it's still in 'pending' state, calls signal-cli's `send` RPC,
// then marks it 'sent' with the JSON result attached.
func handlerSignalPendingApprove(db *sql.DB, sc *signalClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		pendingID, err := req.RequireInt("pending_id")
		if err != nil {
			return toolErr(err), nil
		}

		row, err := scanPendingRow(db.QueryRowContext(ctx,
			"SELECT id, recipient, body, created_at, created_by, status, status_at, status_by, status_note, send_result "+
				"FROM pending WHERE id = ?", pendingID,
		))
		if err == sql.ErrNoRows {
			return toolResultJSON(map[string]any{"error": fmt.Sprintf("pending_id %d not found", pendingID)}), nil
		}
		if err != nil {
			return toolErr(fmt.Errorf("fetch pending: %w", err)), nil
		}
		if row.Status != "pending" {
			return toolResultJSON(map[string]any{
				"error": fmt.Sprintf("pending_id %d is already %s", pendingID, row.Status),
				"row":   row,
			}), nil
		}

		// Hand off to signal-cli. This is the ONLY call site for `send`.
		result, sendErr := sc.rpc(ctx, "send", map[string]any{
			"recipient": []string{row.Recipient},
			"message":   row.Body,
		})
		if sendErr != nil {
			slog.Error("send failed", "pending_id", pendingID, "err", sendErr)
			return toolResultJSON(map[string]any{
				"error":      fmt.Sprintf("signal-cli send failed: %s", sendErr.Error()),
				"pending_id": pendingID,
			}), nil
		}

		now := nowUTC()
		if _, err := db.ExecContext(ctx,
			"UPDATE pending SET status='sent', status_at=?, status_by=?, send_result=? WHERE id = ?",
			now, "operator-approved", string(result), pendingID,
		); err != nil {
			return toolErr(fmt.Errorf("update pending after send: %w", err)), nil
		}
		slog.Info("sent pending message", "pending_id", pendingID, "to", row.Recipient)

		var resultAny any
		if len(result) > 0 {
			_ = json.Unmarshal(result, &resultAny)
		}
		return toolResultJSON(map[string]any{
			"pending_id": pendingID,
			"status":     "sent",
			"recipient":  row.Recipient,
			"sent_at":    now,
			"result":     resultAny,
		}), nil
	}
}

// signal_pending_deny — marks a queued message 'denied' without sending.
func handlerSignalPendingDeny(db *sql.DB) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		pendingID, err := req.RequireInt("pending_id")
		if err != nil {
			return toolErr(err), nil
		}
		reason := req.GetString("reason", "")
		var reasonArg any
		if reason != "" {
			reasonArg = reason
		}

		res, err := db.ExecContext(ctx,
			"UPDATE pending SET status='denied', status_at=?, status_by=?, status_note=? WHERE id = ? AND status = 'pending'",
			nowUTC(), "operator-denied", reasonArg, pendingID,
		)
		if err != nil {
			return toolErr(fmt.Errorf("update pending: %w", err)), nil
		}
		n, err := res.RowsAffected()
		if err != nil {
			return toolErr(fmt.Errorf("rows affected: %w", err)), nil
		}
		if n == 0 {
			return toolResultJSON(map[string]any{
				"error": fmt.Sprintf("pending_id %d not found or not in 'pending' state", pendingID),
			}), nil
		}
		slog.Info("denied pending message", "pending_id", pendingID, "reason", reason)
		return toolResultJSON(map[string]any{
			"pending_id": pendingID,
			"status":     "denied",
			"reason":     reason,
		}), nil
	}
}

// signal_list_contacts — calls signal-cli's `listContacts`. Read-only.
func handlerSignalListContacts(sc *signalClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		result, err := sc.rpc(ctx, "listContacts", map[string]any{})
		if err != nil {
			return toolResultJSON([]map[string]string{{"error": fmt.Sprintf("signal-cli listContacts failed: %s", err.Error())}}), nil
		}
		var parsed any
		if len(result) > 0 {
			_ = json.Unmarshal(result, &parsed)
		}
		// Python always returned a list — coerce non-list results into a single-element list.
		if _, ok := parsed.([]any); ok {
			return toolResultJSON(parsed), nil
		}
		return toolResultJSON([]any{parsed}), nil
	}
}

// signal_account — calls signal-cli's `listIdentities`, wrapped with the
// bot account number for context.
func handlerSignalAccount(cfg *config, sc *signalClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		result, err := sc.rpc(ctx, "listIdentities", map[string]any{})
		if err != nil {
			return toolResultJSON(map[string]any{
				"error": fmt.Sprintf("signal-cli listIdentities failed: %s", err.Error()),
			}), nil
		}
		var parsed any
		if len(result) > 0 {
			_ = json.Unmarshal(result, &parsed)
		}
		return toolResultJSON(map[string]any{
			"account":    cfg.SignalAccount,
			"identities": parsed,
		}), nil
	}
}

// ─── Tool registration ──────────────────────────────────────────────────────

func registerTools(s *server.MCPServer, cfg *config, db *sql.DB, sc *signalClient) {
	s.AddTool(mcp.NewTool("signal_send_message",
		mcp.WithDescription("Queue an outbound Signal message for operator approval. This NEVER sends directly — it returns a pending_id; the operator must review and explicitly call signal_pending_approve(pending_id) before the message reaches signal-cli. Agents should present the queued entry to the human operator and wait for an explicit confirmation before approving. `recipient` is an E.164 number (e.g. \"+15551234567\") or a Signal UUID."),
		mcp.WithString("recipient", mcp.Description("E.164 phone number or Signal UUID."), mcp.Required()),
		mcp.WithString("body", mcp.Description("Message body."), mcp.Required()),
	), handlerSignalSendMessage(db))

	s.AddTool(mcp.NewTool("signal_pending_list",
		mcp.WithDescription("List pending (or sent/denied) outbound messages. `status` filters to one of: pending (default), sent, denied, all. Returns rows sorted most-recent first."),
		mcp.WithString("status", mcp.Description("Filter: 'pending' (default), 'sent', 'denied', or 'all'.")),
		mcp.WithNumber("limit", mcp.Description("Maximum rows to return (default 50).")),
	), handlerSignalPendingList(db))

	s.AddTool(mcp.NewTool("signal_pending_approve",
		mcp.WithDescription("Approve and actually send a queued outbound message. THIS IS THE ONLY PATH TO SENDING. Call only after the operator has explicitly confirmed the recipient and body for this pending_id."),
		mcp.WithNumber("pending_id", mcp.Description("Pending row id to approve."), mcp.Required()),
	), handlerSignalPendingApprove(db, sc))

	s.AddTool(mcp.NewTool("signal_pending_deny",
		mcp.WithDescription("Mark a queued message as denied. Drops it; nothing is sent."),
		mcp.WithNumber("pending_id", mcp.Description("Pending row id to deny."), mcp.Required()),
		mcp.WithString("reason", mcp.Description("Optional reason recorded in status_note.")),
	), handlerSignalPendingDeny(db))

	s.AddTool(mcp.NewTool("signal_list_contacts",
		mcp.WithDescription("List the bot account's known Signal contacts (numbers and names). Read-only — does not send anything. Useful for resolving a recipient by name and confirming the E.164."),
	), handlerSignalListContacts(sc))

	s.AddTool(mcp.NewTool("signal_account",
		mcp.WithDescription("Return the bot's own Signal account info (number, UUID, listed identities)."),
	), handlerSignalAccount(cfg, sc))
}

// ─── HTTP endpoints (non-MCP) ───────────────────────────────────────────────

func healthHandler(cfg *config, db *sql.DB, sc *signalClient) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		dbOK := false
		signalOK := false
		errs := map[string]string{}

		if err := db.PingContext(r.Context()); err != nil {
			errs["db"] = err.Error()
		} else if _, err := db.ExecContext(r.Context(), "SELECT 1"); err != nil {
			errs["db"] = err.Error()
		} else {
			dbOK = true
		}

		// Cheap reachability probe — listAccounts is unauth'd on the daemon
		// in our deployment and returns quickly.
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		body, _ := json.Marshal(map[string]any{
			"jsonrpc": "2.0", "id": 1, "method": "listAccounts", "params": map[string]any{},
		})
		req, _ := http.NewRequestWithContext(ctx, "POST", sc.url+"/api/v1/rpc", strings.NewReader(string(body)))
		req.Header.Set("Content-Type", "application/json")
		resp, err := sc.hc.Do(req)
		if err != nil {
			errs["signal"] = err.Error()
		} else {
			_ = resp.Body.Close()
			if resp.StatusCode == 200 {
				signalOK = true
			} else {
				errs["signal"] = fmt.Sprintf("HTTP %d", resp.StatusCode)
			}
		}

		status := "ok"
		if !dbOK || !signalOK {
			status = "degraded"
		}
		out := map[string]any{
			"status":    status,
			"db_ok":     dbOK,
			"signal_ok": signalOK,
			"account":   cfg.SignalAccount,
		}
		if len(errs) > 0 {
			out["errors"] = errs
		}
		writeJSON(w, http.StatusOK, out)
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
	if v := os.Getenv("SIGNAL_MCP_LOG_LEVEL"); strings.EqualFold(v, "debug") {
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

	db, err := openDB(cfg.DBPath)
	if err != nil {
		slog.Error("db", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	sc := newSignalClient(cfg)

	mcpServer := server.NewMCPServer(name, version,
		server.WithToolCapabilities(false),
	)
	registerTools(mcpServer, cfg, db, sc)

	streamable := server.NewStreamableHTTPServer(mcpServer)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler(cfg, db, sc))
	mux.HandleFunc("/version", versionHandler())
	mux.Handle("/mcp", streamable)
	mux.Handle("/mcp/", streamable)

	authed := bearerAuthMiddleware(tokens, mux)

	addr := fmt.Sprintf("%s:%d", bindIP, cfg.Port)
	slog.Info("starting",
		"name", name, "version", version,
		"addr", addr,
		"account", cfg.SignalAccount,
		"db", cfg.DBPath,
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
