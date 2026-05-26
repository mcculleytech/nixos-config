// agent-memory-mcp — MCP server fronting a pgvector-backed shared agent memory
// store. Memories are embedded via a local Ollama instance and persisted in
// PostgreSQL with an HNSW cosine-distance index for fast semantic search.
//
// Behavioral parity with the previous Python implementation:
//   - Streamable-HTTP MCP transport at /mcp
//   - Bearer-token auth (tokens loaded from a sops-rendered JSON file)
//   - /health (unauthenticated) verifies postgres + Ollama reachability
//   - /version (bearer-required) returns name + version
//   - 8 tools mirroring the Python tool surface 1:1
//
// Env vars (preserved from the Python implementation so the NixOS module
// continues to work without modification):
//   - AGENT_MEMORY_BIND_IP        bind address; "auto" → tailnet IPv4
//   - AGENT_MEMORY_PORT           TCP port (default 4280)
//   - AGENT_MEMORY_DB_DSN         postgres connection string (peer-auth via socket)
//   - AGENT_MEMORY_TOKENS_FILE    path to sops-rendered JSON token map
//   - OLLAMA_URL                  Ollama base URL (default http://127.0.0.1:11434)
//   - OLLAMA_EMBED_MODEL          embedding model (default nomic-embed-text)
//   - AGENT_MEMORY_LOG_LEVEL      debug|info (default info)
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
	"github.com/pgvector/pgvector-go"
)

const (
	name     = "agent-memory-mcp"
	version  = "0.2.0"
	embedDim = 768 // nomic-embed-text dimension; matches schema.sql vector(768)
)

// ─── Configuration ──────────────────────────────────────────────────────────

type config struct {
	BindIP       string
	Port         int
	TokensFile   string
	DBDSN        string
	OllamaURL    string
	EmbedModel   string
}

func loadConfig() (*config, error) {
	bindIP := getenvOr("AGENT_MEMORY_BIND_IP", "auto")
	portStr := getenvOr("AGENT_MEMORY_PORT", "4280")
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("AGENT_MEMORY_PORT=%q: %w", portStr, err)
	}
	tokensFile := os.Getenv("AGENT_MEMORY_TOKENS_FILE")
	if tokensFile == "" {
		return nil, errors.New("AGENT_MEMORY_TOKENS_FILE is required")
	}
	dsn := getenvOr("AGENT_MEMORY_DB_DSN", "postgresql:///agent_memory?host=/run/postgresql")
	ollamaURL := strings.TrimRight(getenvOr("OLLAMA_URL", "http://127.0.0.1:11434"), "/")
	embedModel := getenvOr("OLLAMA_EMBED_MODEL", "nomic-embed-text")
	return &config{
		BindIP:     bindIP,
		Port:       port,
		TokensFile: tokensFile,
		DBDSN:      dsn,
		OllamaURL:  ollamaURL,
		EmbedModel: embedModel,
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

// ─── Embedding client ───────────────────────────────────────────────────────

type embedClient struct {
	url   string
	model string
	hc    *http.Client
}

func newEmbedClient(cfg *config) *embedClient {
	return &embedClient{
		url:   cfg.OllamaURL,
		model: cfg.EmbedModel,
		hc:    &http.Client{Timeout: 30 * time.Second},
	}
}

// embed POSTs text to Ollama's /api/embeddings endpoint and returns the
// embedding vector. Validates that the returned dimension matches embedDim;
// a mismatch indicates the wrong model is loaded and would corrupt the table.
func (e *embedClient) embed(ctx context.Context, text string) ([]float32, error) {
	body, err := json.Marshal(map[string]string{"model": e.model, "prompt": text})
	if err != nil {
		return nil, fmt.Errorf("encode embed body: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", e.url+"/api/embeddings", strings.NewReader(string(body)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := e.hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("ollama embed: %w", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		snippet := string(respBody)
		if len(snippet) > 500 {
			snippet = snippet[:500]
		}
		return nil, fmt.Errorf("ollama embed -> %d: %s (try: `ollama pull %s`)", resp.StatusCode, snippet, e.model)
	}
	var parsed struct {
		Embedding []float32 `json:"embedding"`
	}
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("parse ollama response: %w", err)
	}
	if len(parsed.Embedding) != embedDim {
		return nil, fmt.Errorf("ollama returned embedding dim=%d, expected %d (wrong model?)", len(parsed.Embedding), embedDim)
	}
	return parsed.Embedding, nil
}

// pingOllama hits a cheap Ollama endpoint to verify reachability for /health.
func (e *embedClient) ping(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, "GET", e.url+"/api/tags", nil)
	if err != nil {
		return err
	}
	hc := &http.Client{Timeout: 2 * time.Second}
	resp, err := hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("ollama /api/tags -> %d", resp.StatusCode)
	}
	return nil
}

// ─── Project resolution ─────────────────────────────────────────────────────

// resolveProjectID returns the UUID of the named project, creating it if
// absent. Matches Python's resolve_project_id behavior — auto-creation
// keeps memory_insert ergonomic.
func resolveProjectID(ctx context.Context, pool *pgxpool.Pool, name string) (*string, error) {
	if name == "" {
		return nil, nil
	}
	var id string
	err := pool.QueryRow(ctx, "SELECT id::text FROM projects WHERE name = $1", name).Scan(&id)
	if err == nil {
		return &id, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}
	if err := pool.QueryRow(ctx, "INSERT INTO projects (name) VALUES ($1) RETURNING id::text", name).Scan(&id); err != nil {
		return nil, err
	}
	return &id, nil
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

// stringArrayArg extracts a list-of-strings tool argument. Returns nil when
// absent so callers can distinguish "not provided" (keep current value on
// updates, no filter on searches) from "empty list" (clear, no match).
func stringArrayArg(req mcp.CallToolRequest, key string) ([]string, bool) {
	raw, ok := req.GetArguments()[key]
	if !ok {
		return nil, false
	}
	arr, ok := raw.([]any)
	if !ok {
		return nil, false
	}
	out := make([]string, 0, len(arr))
	for _, v := range arr {
		if s, ok := v.(string); ok {
			out = append(out, s)
		}
	}
	return out, true
}

// objectArg extracts a map-of-string-to-anything tool argument. Returns nil
// when absent so callers can distinguish "not provided" from "empty object".
func objectArg(req mcp.CallToolRequest, key string) (map[string]any, bool) {
	raw, ok := req.GetArguments()[key]
	if !ok {
		return nil, false
	}
	m, ok := raw.(map[string]any)
	if !ok {
		return nil, false
	}
	return m, true
}

// ─── Tool handlers ──────────────────────────────────────────────────────────

func handlerMemorySearch(pool *pgxpool.Pool, emb *embedClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		query, err := req.RequireString("query")
		if err != nil {
			return toolErr(err), nil
		}
		project := strings.TrimSpace(req.GetString("project", ""))
		tags, _ := stringArrayArg(req, "tags")
		limit := req.GetInt("limit", 10)

		vec, err := emb.embed(ctx, query)
		if err != nil {
			return toolErr(err), nil
		}
		v := pgvector.NewVector(vec)

		// Dynamic WHERE built from optional filters. Casts on the vector
		// parameter are required because the `<=>` operator can't infer the
		// pgvector type from a bare $N.
		where := []string{}
		params := []any{v}
		if project != "" {
			where = append(where, fmt.Sprintf("p.name = $%d", len(params)+1))
			params = append(params, project)
		}
		if len(tags) > 0 {
			where = append(where, fmt.Sprintf("m.tags && $%d", len(params)+1))
			params = append(params, tags)
		}
		params = append(params, v)
		orderIdx := len(params)
		params = append(params, limit)
		limitIdx := len(params)
		whereSQL := ""
		if len(where) > 0 {
			whereSQL = "WHERE " + strings.Join(where, " AND ")
		}
		sql := fmt.Sprintf(`
			SELECT m.id::text, m.content, m.source, m.tags, m.metadata, m.created_at,
			       p.name AS project,
			       1 - (m.embedding <=> $1::vector) AS similarity
			FROM memories m
			LEFT JOIN projects p ON p.id = m.project_id
			%s
			ORDER BY m.embedding <=> $%d::vector
			LIMIT $%d
		`, whereSQL, orderIdx, limitIdx)

		rows, err := pool.Query(ctx, sql, params...)
		if err != nil {
			return toolErr(fmt.Errorf("search: %w", err)), nil
		}
		defer rows.Close()

		out := []map[string]any{}
		for rows.Next() {
			var id, content string
			var source *string
			var tagsRow []string
			var metadata map[string]any
			var createdAt time.Time
			var projectName *string
			var similarity float64
			if err := rows.Scan(&id, &content, &source, &tagsRow, &metadata, &createdAt, &projectName, &similarity); err != nil {
				return toolErr(fmt.Errorf("scan: %w", err)), nil
			}
			out = append(out, map[string]any{
				"id":         id,
				"content":    content,
				"project":    projectName,
				"source":     source,
				"tags":       tagsRow,
				"metadata":   metadata,
				"similarity": similarity,
				"created_at": createdAt.Format(time.RFC3339Nano),
			})
		}
		if err := rows.Err(); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerMemoryListBySource(pool *pgxpool.Pool) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		prefix, err := req.RequireString("source_prefix")
		if err != nil {
			return toolErr(err), nil
		}
		// `limit` is explicitly required (default 10000). An earlier silent
		// default caused a vault-indexer duplication incident; expose it so
		// callers think about pagination.
		limit := req.GetInt("limit", 10000)
		rows, err := pool.Query(ctx, `
			SELECT m.id::text, m.source, m.tags, m.metadata, m.created_at, m.updated_at,
			       p.name AS project
			FROM memories m
			LEFT JOIN projects p ON p.id = m.project_id
			WHERE m.source LIKE $1
			ORDER BY m.source
			LIMIT $2
		`, prefix+"%", limit)
		if err != nil {
			return toolErr(fmt.Errorf("list_by_source: %w", err)), nil
		}
		defer rows.Close()

		out := []map[string]any{}
		for rows.Next() {
			var id string
			var source *string
			var tagsRow []string
			var metadata map[string]any
			var createdAt, updatedAt time.Time
			var projectName *string
			if err := rows.Scan(&id, &source, &tagsRow, &metadata, &createdAt, &updatedAt, &projectName); err != nil {
				return toolErr(fmt.Errorf("scan: %w", err)), nil
			}
			out = append(out, map[string]any{
				"id":         id,
				"source":     source,
				"project":    projectName,
				"tags":       tagsRow,
				"metadata":   metadata,
				"created_at": createdAt.Format(time.RFC3339Nano),
				"updated_at": updatedAt.Format(time.RFC3339Nano),
			})
		}
		if err := rows.Err(); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerMemoryInsert(pool *pgxpool.Pool, emb *embedClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		content, err := req.RequireString("content")
		if err != nil {
			return toolErr(err), nil
		}
		project := strings.TrimSpace(req.GetString("project", ""))
		var source *string
		if s := req.GetString("source", ""); s != "" {
			source = &s
		}
		tags, _ := stringArrayArg(req, "tags")
		if tags == nil {
			tags = []string{}
		}
		metadata, _ := objectArg(req, "metadata")
		if metadata == nil {
			metadata = map[string]any{}
		}

		vec, err := emb.embed(ctx, content)
		if err != nil {
			return toolErr(err), nil
		}

		projectID, err := resolveProjectID(ctx, pool, project)
		if err != nil {
			return toolErr(fmt.Errorf("resolve project: %w", err)), nil
		}

		var id string
		var createdAt time.Time
		err = pool.QueryRow(ctx, `
			INSERT INTO memories (content, embedding, source, project_id, tags, metadata)
			VALUES ($1, $2, $3, $4::uuid, $5, $6)
			RETURNING id::text, created_at
		`, content, pgvector.NewVector(vec), source, projectID, tags, metadata).Scan(&id, &createdAt)
		if err != nil {
			return toolErr(fmt.Errorf("insert: %w", err)), nil
		}
		return toolResultJSON(map[string]any{
			"id":         id,
			"created_at": createdAt.Format(time.RFC3339Nano),
		}), nil
	}
}

func handlerMemoryUpdate(pool *pgxpool.Pool, emb *embedClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		id, err := req.RequireString("id")
		if err != nil {
			return toolErr(err), nil
		}
		// content/tags/metadata are optional — presence vs. absence is what
		// distinguishes "update this field" from "leave it alone".
		_, hasContent := req.GetArguments()["content"]
		content := req.GetString("content", "")
		tags, hasTags := stringArrayArg(req, "tags")
		metadata, hasMetadata := objectArg(req, "metadata")

		sets := []string{}
		params := []any{}
		if hasContent {
			vec, err := emb.embed(ctx, content)
			if err != nil {
				return toolErr(err), nil
			}
			params = append(params, content)
			sets = append(sets, fmt.Sprintf("content = $%d", len(params)))
			params = append(params, pgvector.NewVector(vec))
			sets = append(sets, fmt.Sprintf("embedding = $%d", len(params)))
		}
		if hasTags {
			if tags == nil {
				tags = []string{}
			}
			params = append(params, tags)
			sets = append(sets, fmt.Sprintf("tags = $%d", len(params)))
		}
		if hasMetadata {
			if metadata == nil {
				metadata = map[string]any{}
			}
			params = append(params, metadata)
			sets = append(sets, fmt.Sprintf("metadata = $%d", len(params)))
		}
		if len(sets) == 0 {
			return toolResultJSON(false), nil
		}
		sets = append(sets, "updated_at = now()")
		params = append(params, id)
		sql := fmt.Sprintf("UPDATE memories SET %s WHERE id = $%d::uuid", strings.Join(sets, ", "), len(params))
		tag, err := pool.Exec(ctx, sql, params...)
		if err != nil {
			return toolErr(fmt.Errorf("update: %w", err)), nil
		}
		return toolResultJSON(tag.RowsAffected() > 0), nil
	}
}

func handlerMemoryDelete(pool *pgxpool.Pool) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		id, err := req.RequireString("id")
		if err != nil {
			return toolErr(err), nil
		}
		tag, err := pool.Exec(ctx, "DELETE FROM memories WHERE id = $1::uuid", id)
		if err != nil {
			return toolErr(fmt.Errorf("delete: %w", err)), nil
		}
		return toolResultJSON(tag.RowsAffected() > 0), nil
	}
}

func handlerProjectList(pool *pgxpool.Pool) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		rows, err := pool.Query(ctx, "SELECT id::text, name, description, created_at FROM projects ORDER BY name")
		if err != nil {
			return toolErr(fmt.Errorf("project_list: %w", err)), nil
		}
		defer rows.Close()
		out := []map[string]any{}
		for rows.Next() {
			var id, name string
			var description *string
			var createdAt time.Time
			if err := rows.Scan(&id, &name, &description, &createdAt); err != nil {
				return toolErr(fmt.Errorf("scan: %w", err)), nil
			}
			out = append(out, map[string]any{
				"id":          id,
				"name":        name,
				"description": description,
				"created_at":  createdAt.Format(time.RFC3339Nano),
			})
		}
		if err := rows.Err(); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerProjectCreate(pool *pgxpool.Pool) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		pname, err := req.RequireString("name")
		if err != nil {
			return toolErr(err), nil
		}
		var description *string
		if s := req.GetString("description", ""); s != "" {
			description = &s
		}
		// Idempotent on name. COALESCE keeps any existing description when
		// the caller passes nothing rather than overwriting with NULL.
		var id, retName string
		var retDesc *string
		var createdAt time.Time
		err = pool.QueryRow(ctx, `
			INSERT INTO projects (name, description) VALUES ($1, $2)
			ON CONFLICT (name) DO UPDATE SET description = COALESCE(EXCLUDED.description, projects.description)
			RETURNING id::text, name, description, created_at
		`, pname, description).Scan(&id, &retName, &retDesc, &createdAt)
		if err != nil {
			return toolErr(fmt.Errorf("project_create: %w", err)), nil
		}
		return toolResultJSON(map[string]any{
			"id":          id,
			"name":        retName,
			"description": retDesc,
			"created_at":  createdAt.Format(time.RFC3339Nano),
		}), nil
	}
}

func handlerProjectDelete(pool *pgxpool.Pool) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		pname, err := req.RequireString("name")
		if err != nil {
			return toolErr(err), nil
		}
		var orphaned int64
		err = pool.QueryRow(ctx,
			"SELECT count(*) FROM memories WHERE project_id = (SELECT id FROM projects WHERE name = $1)",
			pname,
		).Scan(&orphaned)
		if err != nil {
			return toolErr(fmt.Errorf("project_delete count: %w", err)), nil
		}
		tag, err := pool.Exec(ctx, "DELETE FROM projects WHERE name = $1", pname)
		if err != nil {
			return toolErr(fmt.Errorf("project_delete: %w", err)), nil
		}
		return toolResultJSON(map[string]any{
			"deleted":           tag.RowsAffected() > 0,
			"orphaned_memories": orphaned,
		}), nil
	}
}

// ─── Tool registration ──────────────────────────────────────────────────────

func registerTools(s *server.MCPServer, pool *pgxpool.Pool, emb *embedClient) {
	s.AddTool(mcp.NewTool("memory_search",
		mcp.WithDescription("Semantic search across memories. Embeds the query, returns up to `limit` rows sorted by cosine similarity (largest first). Optional project + tags filters narrow the search."),
		mcp.WithString("query", mcp.Description("Natural-language query text."), mcp.Required()),
		mcp.WithString("project", mcp.Description("Restrict to memories under this project name.")),
		mcp.WithArray("tags", mcp.Description("Restrict to memories sharing at least one of these tags.")),
		mcp.WithNumber("limit", mcp.Description("Max rows (default 10).")),
	), handlerMemorySearch(pool, emb))

	s.AddTool(mcp.NewTool("memory_list_by_source",
		mcp.WithDescription("List memories whose `source` field starts with `source_prefix`. Used by indexer-style clients (vault-indexer) to enumerate existing rows. Returns id, source, tags, metadata, timestamps — no content, no embedding. `limit` is explicit (default 10000) to force callers to consider pagination; pass a higher number for full enumeration."),
		mcp.WithString("source_prefix", mcp.Description("Prefix to match against memories.source (LIKE 'prefix%')."), mcp.Required()),
		mcp.WithNumber("limit", mcp.Description("Max rows (default 10000).")),
	), handlerMemoryListBySource(pool))

	s.AddTool(mcp.NewTool("memory_insert",
		mcp.WithDescription("Embed `content` via Ollama and insert as a new memory. Returns the new row's id + created_at. If `project` is set and the project doesn't exist, it's auto-created."),
		mcp.WithString("content", mcp.Description("Text body to embed and store."), mcp.Required()),
		mcp.WithString("project", mcp.Description("Project name. Auto-created if new.")),
		mcp.WithString("source", mcp.Description("Free-form source identifier (e.g., vault path, conversation id).")),
		mcp.WithArray("tags", mcp.Description("List of tag strings.")),
		mcp.WithObject("metadata", mcp.Description("Arbitrary JSON metadata.")),
	), handlerMemoryInsert(pool, emb))

	s.AddTool(mcp.NewTool("memory_update",
		mcp.WithDescription("Update one or more fields on an existing memory. If `content` is supplied, the embedding is re-computed. Omitted fields are left untouched. Returns true iff a row was modified."),
		mcp.WithString("id", mcp.Description("UUID of the memory to update."), mcp.Required()),
		mcp.WithString("content", mcp.Description("Replacement text. Triggers a re-embed.")),
		mcp.WithArray("tags", mcp.Description("Replacement tag list.")),
		mcp.WithObject("metadata", mcp.Description("Replacement metadata object.")),
	), handlerMemoryUpdate(pool, emb))

	s.AddTool(mcp.NewTool("memory_delete",
		mcp.WithDescription("Delete a memory by id. Returns true iff a row was removed."),
		mcp.WithString("id", mcp.Description("UUID of the memory to delete."), mcp.Required()),
	), handlerMemoryDelete(pool))

	s.AddTool(mcp.NewTool("project_list",
		mcp.WithDescription("List all projects with id, name, description, created_at."),
	), handlerProjectList(pool))

	s.AddTool(mcp.NewTool("project_create",
		mcp.WithDescription("Create a project. Idempotent on name — returns the existing row if one already exists, optionally updating its description."),
		mcp.WithString("name", mcp.Description("Project name (unique)."), mcp.Required()),
		mcp.WithString("description", mcp.Description("Optional human description.")),
	), handlerProjectCreate(pool))

	s.AddTool(mcp.NewTool("project_delete",
		mcp.WithDescription("Delete a project by name. Memories referencing it have their project_id set to NULL (FK ON DELETE SET NULL). Returns {deleted, orphaned_memories}."),
		mcp.WithString("name", mcp.Description("Project name to delete."), mcp.Required()),
	), handlerProjectDelete(pool))
}

// ─── HTTP endpoints (non-MCP) ───────────────────────────────────────────────

func healthHandler(pool *pgxpool.Pool, emb *embedClient) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		dbOK := pool.Ping(r.Context()) == nil
		ollamaErr := emb.ping(r.Context())
		ollamaOK := ollamaErr == nil
		body := map[string]any{
			"status":    "ok",
			"db_ok":     dbOK,
			"ollama_ok": ollamaOK,
		}
		if !dbOK || !ollamaOK {
			body["status"] = "degraded"
			errs := map[string]string{}
			if !dbOK {
				errs["db"] = "ping failed"
			}
			if ollamaErr != nil {
				errs["ollama"] = ollamaErr.Error()
			}
			body["errors"] = errs
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
	if v := os.Getenv("AGENT_MEMORY_LOG_LEVEL"); strings.EqualFold(v, "debug") {
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

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, cfg.DBDSN)
	if err != nil {
		slog.Error("pgxpool", "err", err)
		os.Exit(1)
	}
	defer pool.Close()
	// Fail fast if postgres is unreachable rather than emitting errors on every
	// tool call. The systemd unit will restart on failure.
	if err := pool.Ping(ctx); err != nil {
		slog.Error("postgres ping", "err", err)
		os.Exit(1)
	}

	emb := newEmbedClient(cfg)

	mcpServer := server.NewMCPServer(name, version,
		server.WithToolCapabilities(false),
	)
	registerTools(mcpServer, pool, emb)

	streamable := server.NewStreamableHTTPServer(mcpServer)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler(pool, emb))
	mux.HandleFunc("/version", versionHandler())
	mux.Handle("/mcp", streamable)
	mux.Handle("/mcp/", streamable)

	authed := bearerAuthMiddleware(tokens, mux)

	addr := fmt.Sprintf("%s:%d", bindIP, cfg.Port)
	slog.Info("starting",
		"name", name, "version", version,
		"addr", addr, "db_dsn", cfg.DBDSN,
		"ollama_url", cfg.OllamaURL, "embed_model", cfg.EmbedModel,
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
