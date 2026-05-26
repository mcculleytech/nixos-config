// vault-mcp — MCP server fronting an on-disk Obsidian vault.
//
// Behavioral parity with the previous Python implementation:
//   - Streamable-HTTP MCP transport at /mcp
//   - Bearer-token auth (tokens loaded from a sops-rendered JSON file)
//   - /health (unauthenticated) verifies vault root reachability
//   - /version (bearer-required) returns name + version
//   - 7 tools: vault_read, vault_write, vault_append, vault_list,
//     vault_search, vault_metadata, vault_query_frontmatter
//   - Path safety: refuses anything resolving outside the vault root or
//     touching protected directories (.obsidian, .trash, .git)
//   - YAML frontmatter parsing with malformed-input resilience
//   - Inline #tag extraction (code-fence stripped first)
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
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
	"gopkg.in/yaml.v3"
)

const (
	name    = "vault-mcp"
	version = "0.2.0"
)

// Files/dirs the server never touches even if asked. .obsidian holds the
// vault's app config + sync state; we deliberately don't let agents poke it.
var skipPrefixes = []string{".obsidian", ".trash", ".git"}

var textExtensions = map[string]struct{}{
	".md":     {},
	".canvas": {},
	".txt":    {},
}

var (
	frontmatterRE = regexp.MustCompile(`(?s)\A---\n(.*?)\n---\n`)
	// Inline-tag scanner. Obsidian tags allow slashes (#area/project) and
	// hyphens. Go's regexp doesn't support lookbehind; we filter manually
	// after matching to reject `#` that immediately follows a word char.
	tagRE       = regexp.MustCompile(`#([\w/-]+)`)
	codeFenceRE = regexp.MustCompile("(?s)```.*?```")
)

// ─── Configuration ──────────────────────────────────────────────────────────

type config struct {
	BindIP       string
	Port         int
	TokensFile   string
	VaultRoot    string
	MaxReadBytes int
}

func loadConfig() (*config, error) {
	bindIP := getenvOr("VAULT_MCP_BIND_IP", "auto")
	portStr := getenvOr("VAULT_MCP_PORT", "4281")
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("VAULT_MCP_PORT=%q: %w", portStr, err)
	}
	tokensFile := os.Getenv("VAULT_MCP_TOKENS_FILE")
	if tokensFile == "" {
		return nil, errors.New("VAULT_MCP_TOKENS_FILE is required")
	}
	rawRoot := os.Getenv("VAULT_MCP_ROOT")
	if rawRoot == "" {
		return nil, errors.New("VAULT_MCP_ROOT is required")
	}
	vaultRoot, err := filepath.Abs(rawRoot)
	if err != nil {
		return nil, fmt.Errorf("resolve VAULT_MCP_ROOT: %w", err)
	}
	resolved, err := filepath.EvalSymlinks(vaultRoot)
	if err == nil {
		vaultRoot = resolved
	}
	info, err := os.Stat(vaultRoot)
	if err != nil || !info.IsDir() {
		return nil, fmt.Errorf("VAULT_MCP_ROOT=%s is not a directory", vaultRoot)
	}
	maxRead, err := strconv.Atoi(getenvOr("VAULT_MCP_MAX_READ_BYTES", "5242880"))
	if err != nil {
		return nil, fmt.Errorf("VAULT_MCP_MAX_READ_BYTES: %w", err)
	}
	return &config{
		BindIP:       bindIP,
		Port:         port,
		TokensFile:   tokensFile,
		VaultRoot:    vaultRoot,
		MaxReadBytes: maxRead,
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

// ─── Vault filesystem helpers ───────────────────────────────────────────────

// safeJoin resolves rel under the vault root, refusing anything that escapes.
// Rejects: absolute paths that leave the vault, paths whose resolved form
// leaves the vault (incl. symlinks), .obsidian/.trash/.git locations.
func safeJoin(root, rel string) (string, error) {
	rel = strings.TrimLeft(rel, "/")
	candidate := filepath.Join(root, rel)
	// Resolve symlinks if present; otherwise use the cleaned join.
	resolved, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		// File may not exist yet (write/append); fall back to lexical clean.
		resolved = filepath.Clean(candidate)
	}
	// Ensure resolved is under root. Use a trailing separator on root for
	// proper prefix checking.
	rootClean := filepath.Clean(root)
	rel2, err := filepath.Rel(rootClean, resolved)
	if err != nil || strings.HasPrefix(rel2, "..") || rel2 == ".." {
		return "", fmt.Errorf("path '%s' escapes the vault root", rel)
	}
	if rel2 != "." {
		first := strings.SplitN(rel2, string(filepath.Separator), 2)[0]
		for _, sp := range skipPrefixes {
			if first == sp {
				return "", fmt.Errorf("path '%s' targets a protected directory (%s)", rel, sp)
			}
		}
	}
	return resolved, nil
}

// iterNotes walks the vault (or a subfolder) and invokes fn for every text
// note, skipping protected prefixes and any dotfiles. Returns the first
// error from fn, or any walk error.
func iterNotes(root, base string, fn func(path string, info os.FileInfo) error) error {
	return filepath.Walk(base, func(p string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(root, p)
		if err != nil {
			return nil
		}
		parts := strings.Split(rel, string(filepath.Separator))
		for _, part := range parts {
			if strings.HasPrefix(part, ".") {
				return nil
			}
		}
		if len(parts) > 0 {
			for _, sp := range skipPrefixes {
				if parts[0] == sp {
					return nil
				}
			}
		}
		ext := strings.ToLower(filepath.Ext(p))
		if _, ok := textExtensions[ext]; !ok {
			return nil
		}
		return fn(p, info)
	})
}

// parseFrontmatter parses a YAML frontmatter block. Returns (metadata, body).
// Malformed YAML degrades to an empty map rather than raising, keeping tools
// resilient on hand-written notes.
func parseFrontmatter(content string) (map[string]any, string) {
	loc := frontmatterRE.FindStringIndex(content)
	if loc == nil {
		return map[string]any{}, content
	}
	match := frontmatterRE.FindStringSubmatch(content)
	if len(match) < 2 {
		return map[string]any{}, content
	}
	var meta map[string]any
	if err := yaml.Unmarshal([]byte(match[1]), &meta); err != nil || meta == nil {
		meta = map[string]any{}
	}
	return meta, content[loc[1]:]
}

// extractTags collects tags from both frontmatter `tags:` and inline `#tag`
// refs in the body. Strips fenced code blocks first so code samples don't
// pollute the tag set.
func extractTags(meta map[string]any, body string) map[string]struct{} {
	tags := map[string]struct{}{}
	if raw, ok := meta["tags"]; ok {
		switch v := raw.(type) {
		case []any:
			for _, t := range v {
				if t == nil {
					continue
				}
				s := strings.TrimPrefix(fmt.Sprintf("%v", t), "#")
				if s != "" {
					tags[s] = struct{}{}
				}
			}
		case string:
			// Obsidian allows comma- or space-separated strings here.
			for _, t := range regexp.MustCompile(`[,\s]+`).Split(v, -1) {
				if t != "" {
					tags[strings.TrimPrefix(t, "#")] = struct{}{}
				}
			}
		}
	}
	bodyClean := codeFenceRE.ReplaceAllString(body, "")
	for _, m := range tagRE.FindAllStringSubmatchIndex(bodyClean, -1) {
		// Reject when preceded by a word char (`colors#fff` is not a tag).
		start := m[0]
		if start > 0 {
			c := bodyClean[start-1]
			if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
				(c >= '0' && c <= '9') || c == '_' {
				continue
			}
		}
		tag := bodyClean[m[2]:m[3]]
		tags[tag] = struct{}{}
	}
	return tags
}

// coerceDate parses ISO-8601 dates (YYYY-MM-DD), full RFC3339 timestamps, or
// YAML date/time values that yaml.v3 already converted to time.Time. Returns
// the date portion (year/month/day) as a time.Time at 00:00 UTC, or zero on
// failure.
func coerceDate(value any) (time.Time, bool) {
	if value == nil {
		return time.Time{}, false
	}
	switch v := value.(type) {
	case time.Time:
		y, m, d := v.Date()
		return time.Date(y, m, d, 0, 0, 0, 0, time.UTC), true
	case string:
		// Try ISO date first, then RFC3339.
		if t, err := time.Parse("2006-01-02", v); err == nil {
			return t, true
		}
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			y, m, d := t.Date()
			return time.Date(y, m, d, 0, 0, 0, 0, time.UTC), true
		}
	}
	return time.Time{}, false
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

func handlerVaultRead(cfg *config) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		path, err := req.RequireString("path")
		if err != nil {
			return toolErr(err), nil
		}
		target, err := safeJoin(cfg.VaultRoot, path)
		if err != nil {
			return toolErr(err), nil
		}
		info, err := os.Stat(target)
		if errors.Is(err, os.ErrNotExist) {
			return toolResultJSON(map[string]string{"error": "not found: " + path}), nil
		}
		if err != nil {
			return toolErr(err), nil
		}
		if info.IsDir() {
			return toolResultJSON(map[string]string{"error": "not a file: " + path}), nil
		}
		raw, err := os.ReadFile(target)
		if err != nil {
			return toolErr(err), nil
		}
		size := int64(len(raw))
		truncated := false
		if len(raw) > cfg.MaxReadBytes {
			raw = raw[:cfg.MaxReadBytes]
			truncated = true
		}
		content := string(raw)
		fm, body := parseFrontmatter(content)
		rel, _ := filepath.Rel(cfg.VaultRoot, target)
		return toolResultJSON(map[string]any{
			"path":         rel,
			"content":      content,
			"body":         body,
			"frontmatter":  fm,
			"size":         info.Size(),
			"mtime":        float64(info.ModTime().UnixNano()) / 1e9,
			"truncated":    truncated,
			"reported_len": size,
		}), nil
	}
}

func handlerVaultWrite(cfg *config) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		path, err := req.RequireString("path")
		if err != nil {
			return toolErr(err), nil
		}
		content, err := req.RequireString("content")
		if err != nil {
			return toolErr(err), nil
		}
		overwrite := req.GetBool("overwrite", false)
		target, err := safeJoin(cfg.VaultRoot, path)
		if err != nil {
			return toolErr(err), nil
		}
		_, statErr := os.Stat(target)
		existed := statErr == nil
		if existed && !overwrite {
			return toolResultJSON(map[string]string{
				"error": "file exists; pass overwrite=true to replace: " + path,
			}), nil
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return toolErr(err), nil
		}
		data := []byte(content)
		if err := os.WriteFile(target, data, 0o644); err != nil {
			return toolErr(err), nil
		}
		rel, _ := filepath.Rel(cfg.VaultRoot, target)
		return toolResultJSON(map[string]any{
			"path":          rel,
			"bytes_written": len(data),
			"created":       !existed,
		}), nil
	}
}

func handlerVaultAppend(cfg *config) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		path, err := req.RequireString("path")
		if err != nil {
			return toolErr(err), nil
		}
		content, err := req.RequireString("content")
		if err != nil {
			return toolErr(err), nil
		}
		separator := req.GetString("separator", "\n")
		target, err := safeJoin(cfg.VaultRoot, path)
		if err != nil {
			return toolErr(err), nil
		}
		_, statErr := os.Stat(target)
		existed := statErr == nil
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return toolErr(err), nil
		}
		var prefix []byte
		if existed {
			// Read current to decide whether to inject the separator.
			cur, err := os.ReadFile(target)
			if err != nil {
				return toolErr(err), nil
			}
			if !strings.HasSuffix(string(cur), separator) {
				prefix = []byte(separator)
			}
		}
		f, err := os.OpenFile(target, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
		if err != nil {
			return toolErr(err), nil
		}
		defer f.Close()
		if len(prefix) > 0 {
			if _, err := f.Write(prefix); err != nil {
				return toolErr(err), nil
			}
		}
		n, err := f.Write([]byte(content))
		if err != nil {
			return toolErr(err), nil
		}
		rel, _ := filepath.Rel(cfg.VaultRoot, target)
		return toolResultJSON(map[string]any{
			"path":           rel,
			"bytes_appended": n,
			"created":        !existed,
		}), nil
	}
}

type listEntry struct {
	Path  string  `json:"path"`
	Size  int64   `json:"size"`
	Mtime float64 `json:"mtime"`
}

func handlerVaultList(cfg *config) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		folder := strings.TrimSpace(req.GetString("folder", ""))
		limit := req.GetInt("limit", 200)
		base := cfg.VaultRoot
		if folder != "" {
			b, err := safeJoin(cfg.VaultRoot, folder)
			if err != nil {
				return toolErr(err), nil
			}
			base = b
		}
		out := []listEntry{}
		err := iterNotes(cfg.VaultRoot, base, func(p string, info os.FileInfo) error {
			rel, _ := filepath.Rel(cfg.VaultRoot, p)
			out = append(out, listEntry{
				Path:  rel,
				Size:  info.Size(),
				Mtime: float64(info.ModTime().UnixNano()) / 1e9,
			})
			if len(out) >= limit {
				return filepath.SkipAll
			}
			return nil
		})
		if err != nil && !errors.Is(err, filepath.SkipAll) {
			return toolErr(err), nil
		}
		sort.Slice(out, func(i, j int) bool { return out[i].Mtime > out[j].Mtime })
		return toolResultJSON(out), nil
	}
}

func handlerVaultSearch(cfg *config) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		query, err := req.RequireString("query")
		if err != nil {
			return toolErr(err), nil
		}
		folder := strings.TrimSpace(req.GetString("folder", ""))
		caseInsensitive := req.GetBool("case_insensitive", true)
		limit := req.GetInt("limit", 50)
		snippetChars := req.GetInt("snippet_chars", 160)

		base := cfg.VaultRoot
		if folder != "" {
			b, err := safeJoin(cfg.VaultRoot, folder)
			if err != nil {
				return toolErr(err), nil
			}
			base = b
		}
		pattern := regexp.QuoteMeta(query)
		if caseInsensitive {
			pattern = "(?i)" + pattern
		}
		pat, err := regexp.Compile(pattern)
		if err != nil {
			return toolErr(err), nil
		}
		hits := []map[string]any{}
		walkErr := iterNotes(cfg.VaultRoot, base, func(p string, info os.FileInfo) error {
			raw, err := os.ReadFile(p)
			if err != nil {
				return nil // skip unreadable
			}
			rel, _ := filepath.Rel(cfg.VaultRoot, p)
			lines := strings.Split(string(raw), "\n")
			for i, line := range lines {
				loc := pat.FindStringIndex(line)
				if loc == nil {
					continue
				}
				start := loc[0] - snippetChars/2
				if start < 0 {
					start = 0
				}
				end := loc[1] + snippetChars/2
				if end > len(line) {
					end = len(line)
				}
				snippet := line[start:end]
				// Byte-window slicing can split a multibyte rune; ensure valid
				// UTF-8 so json.Marshal in toolResultJSON does not choke.
				snippet = strings.ToValidUTF8(snippet, "")
				hits = append(hits, map[string]any{
					"path":    rel,
					"line":    i + 1,
					"snippet": snippet,
				})
				if len(hits) >= limit {
					return filepath.SkipAll
				}
			}
			return nil
		})
		if walkErr != nil && !errors.Is(walkErr, filepath.SkipAll) {
			return toolErr(walkErr), nil
		}
		return toolResultJSON(hits), nil
	}
}

func handlerVaultMetadata(cfg *config) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		path, err := req.RequireString("path")
		if err != nil {
			return toolErr(err), nil
		}
		target, err := safeJoin(cfg.VaultRoot, path)
		if err != nil {
			return toolErr(err), nil
		}
		info, err := os.Stat(target)
		if err != nil || info.IsDir() {
			return toolResultJSON(map[string]string{"error": "not a file: " + path}), nil
		}
		f, err := os.Open(target)
		if err != nil {
			return toolErr(err), nil
		}
		defer f.Close()
		buf := make([]byte, 8192)
		n, _ := f.Read(buf)
		fm, _ := parseFrontmatter(string(buf[:n]))
		rel, _ := filepath.Rel(cfg.VaultRoot, target)
		return toolResultJSON(map[string]any{
			"path":        rel,
			"size":        info.Size(),
			"mtime":       float64(info.ModTime().UnixNano()) / 1e9,
			"frontmatter": fm,
		}), nil
	}
}

// fnmatch performs a shell-style glob match (case-sensitive).
func fnmatch(name, pattern string) bool {
	matched, err := filepath.Match(pattern, name)
	if err != nil {
		return false
	}
	return matched
}

func handlerVaultQueryFrontmatter(cfg *config) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args := req.GetArguments()
		folder := strings.TrimSpace(req.GetString("folder", ""))
		var where map[string]any
		if w, ok := args["where"].(map[string]any); ok {
			where = w
		}
		hasTag := strings.TrimPrefix(strings.TrimSpace(req.GetString("has_tag", "")), "#")
		var hasAnyTag []string
		if v, ok := args["has_any_tag"].([]any); ok {
			for _, t := range v {
				if s, ok := t.(string); ok {
					hasAnyTag = append(hasAnyTag, strings.TrimPrefix(strings.TrimSpace(s), "#"))
				}
			}
		}
		afterRaw := req.GetString("after", "")
		beforeRaw := req.GetString("before", "")
		nameGlob := req.GetString("name_glob", "")
		sortBy := req.GetString("sort_by", "mtime")
		sortDesc := req.GetBool("sort_desc", true)
		limit := req.GetInt("limit", 50)
		var fields []string
		if v, ok := args["fields"].([]any); ok {
			for _, f := range v {
				if s, ok := f.(string); ok {
					fields = append(fields, s)
				}
			}
		}

		base := cfg.VaultRoot
		if folder != "" {
			b, err := safeJoin(cfg.VaultRoot, folder)
			if err != nil {
				return toolErr(err), nil
			}
			base = b
		}

		var afterD, beforeD time.Time
		var afterOK, beforeOK bool
		if afterRaw != "" {
			afterD, afterOK = coerceDate(afterRaw)
		}
		if beforeRaw != "" {
			beforeD, beforeOK = coerceDate(beforeRaw)
		}

		type row struct {
			Path  string         `json:"path"`
			Mtime float64        `json:"mtime"`
			FM    map[string]any `json:"frontmatter"`
		}
		var rows []row

		walkErr := iterNotes(cfg.VaultRoot, base, func(p string, info os.FileInfo) error {
			// Cheap filters first.
			if nameGlob != "" && !fnmatch(filepath.Base(p), nameGlob) {
				return nil
			}
			mt := info.ModTime()
			mtimeD := time.Date(mt.Year(), mt.Month(), mt.Day(), 0, 0, 0, 0, time.UTC)
			if afterOK && mtimeD.Before(afterD) {
				return nil
			}
			if beforeOK && mtimeD.After(beforeD) {
				return nil
			}
			raw, err := os.ReadFile(p)
			if err != nil {
				return nil
			}
			meta, body := parseFrontmatter(string(raw))
			for k, v := range where {
				if !valuesEqual(meta[k], v) {
					return nil
				}
			}
			if hasTag != "" || len(hasAnyTag) > 0 {
				noteTags := extractTags(meta, body)
				if hasTag != "" {
					if _, ok := noteTags[hasTag]; !ok {
						return nil
					}
				}
				if len(hasAnyTag) > 0 {
					any := false
					for _, t := range hasAnyTag {
						if _, ok := noteTags[t]; ok {
							any = true
							break
						}
					}
					if !any {
						return nil
					}
				}
			}
			var fmOut map[string]any
			if len(fields) > 0 {
				fmOut = map[string]any{}
				for _, k := range fields {
					fmOut[k] = meta[k]
				}
			} else {
				fmOut = meta
			}
			rel, _ := filepath.Rel(cfg.VaultRoot, p)
			rows = append(rows, row{
				Path:  rel,
				Mtime: float64(info.ModTime().UnixNano()) / 1e9,
				FM:    fmOut,
			})
			return nil
		})
		if walkErr != nil {
			return toolErr(walkErr), nil
		}

		sort.SliceStable(rows, func(i, j int) bool {
			a, b := rows[i], rows[j]
			// nilLast tracks whether the i-th value should sort after the j-th
			// because its key is nil (only relevant for frontmatter-field sorts).
			var cmp int
			switch sortBy {
			case "mtime":
				switch {
				case a.Mtime < b.Mtime:
					cmp = -1
				case a.Mtime > b.Mtime:
					cmp = 1
				default:
					cmp = 0
				}
			case "name":
				ai := strings.ToLower(a.Path)
				bj := strings.ToLower(b.Path)
				switch {
				case ai < bj:
					cmp = -1
				case ai > bj:
					cmp = 1
				default:
					cmp = 0
				}
			default:
				av, bv := a.FM[sortBy], b.FM[sortBy]
				// None sorts last regardless of direction (mirrors Python's
				// (val is None, val) sort key trick).
				aNil := av == nil
				bNil := bv == nil
				if aNil && !bNil {
					// 'a' goes after 'b' regardless of sort_desc
					return false
				}
				if !aNil && bNil {
					return true
				}
				cmp = compareAny(av, bv)
			}
			if sortDesc {
				return cmp > 0
			}
			return cmp < 0
		})

		if limit > 0 && len(rows) > limit {
			rows = rows[:limit]
		}
		return toolResultJSON(rows), nil
	}
}

// valuesEqual compares meta[k] (any) to a literal `where` value (any) for
// equality, matching Python's `!=` semantics for ints/floats/strings/bools.
func valuesEqual(a, b any) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	// Normalize numeric types: JSON decodes numbers as float64 from the
	// MCP request; yaml.v3 decodes ints as int. Compare via fmt.Sprint as
	// a safety net for mixed types.
	if af, aok := toFloat(a); aok {
		if bf, bok := toFloat(b); bok {
			return af == bf
		}
	}
	return fmt.Sprintf("%v", a) == fmt.Sprintf("%v", b)
}

func toFloat(v any) (float64, bool) {
	switch n := v.(type) {
	case int:
		return float64(n), true
	case int32:
		return float64(n), true
	case int64:
		return float64(n), true
	case float32:
		return float64(n), true
	case float64:
		return n, true
	}
	return 0, false
}

func compareAny(a, b any) int {
	if a == nil && b == nil {
		return 0
	}
	if a == nil {
		return 1
	}
	if b == nil {
		return -1
	}
	if af, ok := toFloat(a); ok {
		if bf, ok := toFloat(b); ok {
			switch {
			case af < bf:
				return -1
			case af > bf:
				return 1
			default:
				return 0
			}
		}
	}
	as := fmt.Sprintf("%v", a)
	bs := fmt.Sprintf("%v", b)
	if as < bs {
		return -1
	}
	if as > bs {
		return 1
	}
	return 0
}

// ─── Tool registration ──────────────────────────────────────────────────────

func registerTools(s *server.MCPServer, cfg *config) {
	s.AddTool(mcp.NewTool("vault_read",
		mcp.WithDescription("Read a note from the vault. Path is relative to the vault root. Returns {path, content, body, frontmatter, size, mtime, truncated}. Content is truncated if the file exceeds the server's max-read-bytes limit (default 5 MiB)."),
		mcp.WithString("path", mcp.Description("Path relative to the vault root."), mcp.Required()),
	), handlerVaultRead(cfg))

	s.AddTool(mcp.NewTool("vault_write",
		mcp.WithDescription("Create or overwrite a note. Refuses to overwrite an existing file unless overwrite=true. Auto-creates parent directories. Returns {path, bytes_written, created}."),
		mcp.WithString("path", mcp.Description("Path relative to the vault root."), mcp.Required()),
		mcp.WithString("content", mcp.Description("UTF-8 file contents."), mcp.Required()),
		mcp.WithBoolean("overwrite", mcp.Description("Allow overwriting an existing file. Default false.")),
	), handlerVaultWrite(cfg))

	s.AddTool(mcp.NewTool("vault_append",
		mcp.WithDescription("Append content to a note. If the file doesn't exist, creates it (no separator on first write). Useful for journal/log-style notes. Returns {path, bytes_appended, created}."),
		mcp.WithString("path", mcp.Description("Path relative to the vault root."), mcp.Required()),
		mcp.WithString("content", mcp.Description("Content to append."), mcp.Required()),
		mcp.WithString("separator", mcp.Description("Separator written between existing content and the new content when both are present. Default '\\n'.")),
	), handlerVaultAppend(cfg))

	s.AddTool(mcp.NewTool("vault_list",
		mcp.WithDescription("List notes in the vault (or under a subfolder). Returns up to `limit` entries with {path, size, mtime}, sorted by mtime descending. Excludes .obsidian/.trash/.git and other dotfiles."),
		mcp.WithString("folder", mcp.Description("Restrict to this subfolder of the vault. Omit for whole vault.")),
		mcp.WithNumber("limit", mcp.Description("Max results to return. Default 200.")),
	), handlerVaultList(cfg))

	s.AddTool(mcp.NewTool("vault_search",
		mcp.WithDescription("Substring search across vault notes. Returns up to `limit` hits with {path, line, snippet}. For semantic search, see the agent-memory MCP (separate service)."),
		mcp.WithString("query", mcp.Description("Substring to search for."), mcp.Required()),
		mcp.WithString("folder", mcp.Description("Restrict to this subfolder. Omit for whole vault.")),
		mcp.WithBoolean("case_insensitive", mcp.Description("Case-insensitive match. Default true.")),
		mcp.WithNumber("limit", mcp.Description("Max hits to return. Default 50.")),
		mcp.WithNumber("snippet_chars", mcp.Description("Window of characters returned around each hit. Default 160.")),
	), handlerVaultSearch(cfg))

	s.AddTool(mcp.NewTool("vault_metadata",
		mcp.WithDescription("Read a note's frontmatter and stats without returning the body. Useful for quick lookups."),
		mcp.WithString("path", mcp.Description("Path relative to the vault root."), mcp.Required()),
	), handlerVaultMetadata(cfg))

	s.AddTool(mcp.NewTool("vault_query_frontmatter",
		mcp.WithDescription("Dataview-style query over the vault's frontmatter + tags. Filters notes by folder, frontmatter equality, tags (frontmatter `tags:` AND inline `#tag` refs), date range (against file mtime), and filename glob. Sorts and returns up to `limit` records with {path, mtime, frontmatter}. Use this when the user wants a list of notes matching some structured criteria — i.e. anything you'd write as a Dataview LIST/TABLE in Obsidian."),
		mcp.WithString("folder", mcp.Description("Restrict to a subfolder of the vault. Omit for whole vault.")),
		mcp.WithObject("where", mcp.Description("Object of frontmatter key=value equality matches (all must match).")),
		mcp.WithString("has_tag", mcp.Description("Require this tag (leading '#' optional). Matches frontmatter tags: list/string AND inline #tag refs in the body.")),
		mcp.WithArray("has_any_tag", mcp.Description("List of tags; require at least one to match. Combine with has_tag for AND-of-OR semantics.")),
		mcp.WithString("after", mcp.Description("ISO date (YYYY-MM-DD); keep notes with mtime >= this date.")),
		mcp.WithString("before", mcp.Description("ISO date (YYYY-MM-DD); keep notes with mtime <= this date.")),
		mcp.WithString("name_glob", mcp.Description("Filename glob match (e.g. 'Journal-*.md').")),
		mcp.WithString("sort_by", mcp.Description("'mtime' | 'name' | <frontmatter-field-name>. Default 'mtime'.")),
		mcp.WithBoolean("sort_desc", mcp.Description("Descending sort. Default true (most recent first).")),
		mcp.WithNumber("limit", mcp.Description("Max records returned. Default 50.")),
		mcp.WithArray("fields", mcp.Description("Subset of frontmatter keys to return. Default: all.")),
	), handlerVaultQueryFrontmatter(cfg))
}

// ─── HTTP endpoints (non-MCP) ───────────────────────────────────────────────

func healthHandler(cfg *config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		info, statErr := os.Stat(cfg.VaultRoot)
		vaultOK := statErr == nil && info.IsDir()
		noteCount := 0
		var walkErr error
		if vaultOK {
			walkErr = iterNotes(cfg.VaultRoot, cfg.VaultRoot, func(p string, info os.FileInfo) error {
				noteCount++
				if noteCount >= 1000 {
					return filepath.SkipAll
				}
				return nil
			})
			if walkErr != nil && !errors.Is(walkErr, filepath.SkipAll) {
				writeJSON(w, http.StatusOK, map[string]any{
					"status":   "degraded",
					"vault_ok": false,
					"error":    walkErr.Error(),
				})
				return
			}
		}
		var countOut any = noteCount
		if noteCount >= 1000 {
			countOut = "1000+"
		}
		status := "ok"
		if !vaultOK {
			status = "degraded"
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"status":             status,
			"vault_ok":           vaultOK,
			"vault_root":         cfg.VaultRoot,
			"approx_note_count":  countOut,
		})
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
	if v := os.Getenv("VAULT_MCP_LOG_LEVEL"); strings.EqualFold(v, "debug") {
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
		"addr", addr, "vault_root", cfg.VaultRoot,
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

