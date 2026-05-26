// escalator-mcp — Single-tool MCP that one-shots a question against a
// frontier model via OpenRouter and returns the answer.
//
// Behavioral parity with the previous Python implementation:
//   - Streamable-HTTP MCP transport at /mcp
//   - Bearer-token auth (same sops-rendered JSON token map)
//   - /health (unauthenticated) returns expert_model + max_output_tokens
//   - /version (bearer-required) returns name + version
//   - One tool: consult_expert(question, model?, context?)
//   - Model allowlist enforced; out-of-list requests fall back to default
//   - Hard cap on output tokens bounds per-call spend
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

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

const (
	name    = "escalator-mcp"
	version = "0.2.0"
)

const openRouterURL = "https://openrouter.ai/api/v1/chat/completions"

// ─── Configuration ──────────────────────────────────────────────────────────

type config struct {
	BindIP          string
	Port            int
	TokensFile      string
	OpenRouterKey   string
	ExpertModel     string
	AllowedModels   map[string]struct{}
	MaxOutputTokens int
	TimeoutSeconds  float64
}

var defaultAllowed = []string{
	"anthropic/claude-opus-4.7-fast",
	"deepseek/deepseek-v4-pro",
	"google/gemini-3.1-pro-preview",
}

func loadConfig() (*config, error) {
	bindIP := getenvOr("ESCALATOR_MCP_BIND_IP", "auto")
	portStr := getenvOr("ESCALATOR_MCP_PORT", "4285")
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("ESCALATOR_MCP_PORT=%q: %w", portStr, err)
	}
	tokensFile := os.Getenv("ESCALATOR_MCP_TOKENS_FILE")
	if tokensFile == "" {
		return nil, errors.New("ESCALATOR_MCP_TOKENS_FILE is required")
	}
	orKey := os.Getenv("OPENROUTER_API_KEY")
	if orKey == "" {
		return nil, errors.New("OPENROUTER_API_KEY is required")
	}
	expert := getenvOr("ESCALATOR_MCP_EXPERT_MODEL", "anthropic/claude-opus-4.7-fast")
	allowedRaw := os.Getenv("ESCALATOR_MCP_ALLOWED_MODELS")
	if allowedRaw == "" {
		allowedRaw = strings.Join(defaultAllowed, ",")
	}
	allowed := map[string]struct{}{}
	for _, m := range strings.Split(allowedRaw, ",") {
		if m = strings.TrimSpace(m); m != "" {
			allowed[m] = struct{}{}
		}
	}
	maxOut, err := strconv.Atoi(getenvOr("ESCALATOR_MCP_MAX_OUTPUT_TOKENS", "4096"))
	if err != nil {
		return nil, fmt.Errorf("ESCALATOR_MCP_MAX_OUTPUT_TOKENS: %w", err)
	}
	to, err := strconv.ParseFloat(getenvOr("ESCALATOR_MCP_TIMEOUT_SECONDS", "90"), 64)
	if err != nil {
		return nil, fmt.Errorf("ESCALATOR_MCP_TIMEOUT_SECONDS: %w", err)
	}
	return &config{
		BindIP:          bindIP,
		Port:            port,
		TokensFile:      tokensFile,
		OpenRouterKey:   orKey,
		ExpertModel:     expert,
		AllowedModels:   allowed,
		MaxOutputTokens: maxOut,
		TimeoutSeconds:  to,
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

// ─── OpenRouter client ──────────────────────────────────────────────────────

type orResponse struct {
	Model   string `json:"model"`
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
	} `json:"usage"`
}

type openRouterClient struct {
	apiKey string
	hc     *http.Client
	maxTok int
}

func newOpenRouterClient(cfg *config) *openRouterClient {
	return &openRouterClient{
		apiKey: cfg.OpenRouterKey,
		hc:     &http.Client{Timeout: time.Duration(cfg.TimeoutSeconds * float64(time.Second))},
		maxTok: cfg.MaxOutputTokens,
	}
}

func (o *openRouterClient) consult(ctx context.Context, model, userMessage string) (*orResponse, error) {
	body := map[string]any{
		"model":      model,
		"max_tokens": o.maxTok,
		"messages": []map[string]string{
			{"role": "user", "content": userMessage},
		},
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("encode body: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", openRouterURL, strings.NewReader(string(raw)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+o.apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("HTTP-Referer", "https://hermes-agent.local/escalator-mcp")
	req.Header.Set("X-Title", "escalator-mcp consult_expert")
	resp, err := o.hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("openrouter request failed: %w", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		snippet := string(respBody)
		if len(snippet) > 500 {
			snippet = snippet[:500]
		}
		return nil, fmt.Errorf("openrouter HTTP %d: %s", resp.StatusCode, snippet)
	}
	var parsed orResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return nil, fmt.Errorf("parse openrouter response: %w", err)
	}
	if len(parsed.Choices) == 0 {
		return nil, errors.New("malformed openrouter response: no choices")
	}
	return &parsed, nil
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

// ─── consult_expert tool ────────────────────────────────────────────────────

func handlerConsultExpert(cfg *config, or *openRouterClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		question, err := req.RequireString("question")
		if err != nil {
			return toolErr(err), nil
		}
		modelReq := strings.TrimSpace(req.GetString("model", ""))
		contextStr := strings.TrimSpace(req.GetString("context", ""))

		var parts []string
		if contextStr != "" {
			parts = append(parts, contextStr)
		}
		parts = append(parts, strings.TrimSpace(question))
		userMessage := strings.Join(parts, "\n\n")

		chosen := cfg.ExpertModel
		if modelReq != "" {
			if _, ok := cfg.AllowedModels[modelReq]; ok {
				chosen = modelReq
			} else {
				slog.Info("requested model not in allow-list; using default",
					"requested", modelReq, "default", cfg.ExpertModel)
			}
		}

		resp, err := or.consult(ctx, chosen, userMessage)
		if err != nil {
			return toolResultJSON(map[string]string{"error": err.Error()}), nil
		}
		return toolResultJSON(map[string]any{
			"model":  resp.Model,
			"answer": resp.Choices[0].Message.Content,
			"usage": map[string]int{
				"input":  resp.Usage.PromptTokens,
				"output": resp.Usage.CompletionTokens,
			},
		}), nil
	}
}

// ─── HTTP endpoints (non-MCP) ───────────────────────────────────────────────

func healthHandler(cfg *config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":            "ok",
			"expert_model":      cfg.ExpertModel,
			"max_output_tokens": cfg.MaxOutputTokens,
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
	if v := os.Getenv("ESCALATOR_MCP_LOG_LEVEL"); strings.EqualFold(v, "debug") {
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

	or := newOpenRouterClient(cfg)

	mcpServer := server.NewMCPServer(name, version,
		server.WithToolCapabilities(false),
	)
	mcpServer.AddTool(mcp.NewTool("consult_expert",
		mcp.WithDescription("Ask a frontier expert model a hard sub-question. Sends question (plus optional context) as a single-turn chat via OpenRouter and returns the full text response. Each call is stateless. Use when alex asks to escalate ('use Opus', 'what would DeepSeek say') OR you (a cheap orchestrator) genuinely can't handle a subproblem."),
		mcp.WithString("question",
			mcp.Description("The exact question or task to give the expert. Be self-contained."),
			mcp.Required()),
		mcp.WithString("model",
			mcp.Description("Optional model slug. 'anthropic/claude-opus-4.7-fast' for Opus, 'deepseek/deepseek-v4-pro' for DeepSeek, 'google/gemini-3.1-pro-preview' for Gemini Pro. Anything outside the allow-list falls back to the default. Omit for default.")),
		mcp.WithString("context",
			mcp.Description("Optional supporting context (notes, code, constraints). Concatenated before the question.")),
	), handlerConsultExpert(cfg, or))

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
		"addr", addr, "expert_model", cfg.ExpertModel,
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
