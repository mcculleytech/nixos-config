// radicale-mcp — MCP server fronting a Radicale CalDAV/CardDAV instance.
//
// Behavioral parity with the previous Python implementation:
//   - Streamable-HTTP MCP transport at /mcp
//   - Bearer-token auth (tokens loaded from a sops-rendered JSON file)
//   - /health (unauthenticated) verifies upstream Radicale reachability
//   - /version (bearer-required) returns name + version
//   - Tools: calendar_list, addressbook_list,
//     event_create, event_list, event_update, event_delete,
//     task_create, task_list, task_complete, task_delete,
//     contact_create, contact_list, contact_search,
//     contact_update, contact_delete
//
// CalDAV/CardDAV is talked over `github.com/emersion/go-webdav`, and
// vCalendar/vCard objects are parsed with `go-ical` and `go-vcard`.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/emersion/go-ical"
	"github.com/emersion/go-vcard"
	"github.com/emersion/go-webdav"
	"github.com/emersion/go-webdav/caldav"
	"github.com/emersion/go-webdav/carddav"
	"github.com/google/uuid"
	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
)

const (
	name    = "radicale-mcp"
	version = "0.2.0"
)

// ─── Configuration ──────────────────────────────────────────────────────────

type config struct {
	BindIP        string
	Port          int
	TokensFile    string
	RadicaleURL   string
	RadicaleUser  string
	RadicalePass  string
	DefaultTZName string
	DefaultTZ     *time.Location
}

func loadConfig() (*config, error) {
	bindIP := getenvOr("RADICALE_MCP_BIND_IP", "auto")
	portStr := getenvOr("RADICALE_MCP_PORT", "4283")
	port, err := strconv.Atoi(portStr)
	if err != nil {
		return nil, fmt.Errorf("RADICALE_MCP_PORT=%q: %w", portStr, err)
	}
	tokensFile := os.Getenv("RADICALE_MCP_TOKENS_FILE")
	if tokensFile == "" {
		return nil, errors.New("RADICALE_MCP_TOKENS_FILE is required")
	}
	rURL := strings.TrimRight(os.Getenv("RADICALE_MCP_RADICALE_URL"), "/")
	if rURL == "" {
		return nil, errors.New("RADICALE_MCP_RADICALE_URL is required")
	}
	// Username env var honors both _USER (existing NixOS module / sops template)
	// and _USERNAME for parity with the planning doc — first non-empty wins.
	user := os.Getenv("RADICALE_MCP_RADICALE_USER")
	if user == "" {
		user = os.Getenv("RADICALE_MCP_RADICALE_USERNAME")
	}
	if user == "" {
		return nil, errors.New("RADICALE_MCP_RADICALE_USER is required")
	}
	pass := os.Getenv("RADICALE_MCP_RADICALE_PASSWORD")
	if pass == "" {
		return nil, errors.New("RADICALE_MCP_RADICALE_PASSWORD is required")
	}
	tzName := getenvOr("RADICALE_MCP_DEFAULT_TZ", "UTC")
	loc, err := time.LoadLocation(tzName)
	if err != nil {
		return nil, fmt.Errorf("RADICALE_MCP_DEFAULT_TZ=%q: %w", tzName, err)
	}
	return &config{
		BindIP:        bindIP,
		Port:          port,
		TokensFile:    tokensFile,
		RadicaleURL:   rURL,
		RadicaleUser:  user,
		RadicalePass:  pass,
		DefaultTZName: tzName,
		DefaultTZ:     loc,
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

// ─── Radicale client wrapper ────────────────────────────────────────────────

// radicaleClient bundles caldav + carddav clients sharing one basic-auth
// HTTP client. We cache the discovered principal + home-set paths so we
// don't redo PROPFIND on every tool call.
type radicaleClient struct {
	cfg *config

	cal  *caldav.Client
	card *carddav.Client

	// Discovery cache. populated lazily on first call.
	calHomeSet  string
	cardHomeSet string
	principal   string
}

func newRadicaleClient(cfg *config) (*radicaleClient, error) {
	hc := webdav.HTTPClientWithBasicAuth(
		&http.Client{Timeout: 30 * time.Second},
		cfg.RadicaleUser, cfg.RadicalePass,
	)
	cal, err := caldav.NewClient(hc, cfg.RadicaleURL)
	if err != nil {
		return nil, fmt.Errorf("caldav client: %w", err)
	}
	card, err := carddav.NewClient(hc, cfg.RadicaleURL)
	if err != nil {
		return nil, fmt.Errorf("carddav client: %w", err)
	}
	return &radicaleClient{cfg: cfg, cal: cal, card: card}, nil
}

// ensurePrincipal looks up the current-user principal path once and caches
// it. Radicale serves a discoverable principal at the URL root.
func (r *radicaleClient) ensurePrincipal(ctx context.Context) (string, error) {
	if r.principal != "" {
		return r.principal, nil
	}
	// caldav.Client doesn't expose the underlying webdav.Client, so we open
	// a parallel webdav.Client over the same auth-injecting HTTP client.
	hc := webdav.HTTPClientWithBasicAuth(
		&http.Client{Timeout: 30 * time.Second},
		r.cfg.RadicaleUser, r.cfg.RadicalePass,
	)
	wd, err := webdav.NewClient(hc, r.cfg.RadicaleURL)
	if err != nil {
		return "", fmt.Errorf("webdav client: %w", err)
	}
	p, err := wd.FindCurrentUserPrincipal(ctx)
	if err != nil {
		return "", fmt.Errorf("find principal: %w", err)
	}
	r.principal = p
	return p, nil
}

func (r *radicaleClient) ensureCalHomeSet(ctx context.Context) (string, error) {
	if r.calHomeSet != "" {
		return r.calHomeSet, nil
	}
	p, err := r.ensurePrincipal(ctx)
	if err != nil {
		return "", err
	}
	hs, err := r.cal.FindCalendarHomeSet(ctx, p)
	if err != nil {
		return "", fmt.Errorf("find calendar home set: %w", err)
	}
	r.calHomeSet = hs
	return hs, nil
}

func (r *radicaleClient) ensureCardHomeSet(ctx context.Context) (string, error) {
	if r.cardHomeSet != "" {
		return r.cardHomeSet, nil
	}
	p, err := r.ensurePrincipal(ctx)
	if err != nil {
		return "", err
	}
	hs, err := r.card.FindAddressBookHomeSet(ctx, p)
	if err != nil {
		return "", fmt.Errorf("find addressbook home set: %w", err)
	}
	r.cardHomeSet = hs
	return hs, nil
}

func (r *radicaleClient) listCalendars(ctx context.Context) ([]caldav.Calendar, error) {
	hs, err := r.ensureCalHomeSet(ctx)
	if err != nil {
		return nil, err
	}
	return r.cal.FindCalendars(ctx, hs)
}

func (r *radicaleClient) listAddressBooks(ctx context.Context) ([]carddav.AddressBook, error) {
	hs, err := r.ensureCardHomeSet(ctx)
	if err != nil {
		return nil, err
	}
	return r.card.FindAddressBooks(ctx, hs)
}

// findCalendar resolves a calendar by display-name or by URL tail. If
// nameOrEmpty is empty, returns the first calendar (raises if none).
func (r *radicaleClient) findCalendar(ctx context.Context, nameOrEmpty string) (*caldav.Calendar, error) {
	cals, err := r.listCalendars(ctx)
	if err != nil {
		return nil, err
	}
	if len(cals) == 0 {
		return nil, errors.New("no calendars found for the configured Radicale user")
	}
	if nameOrEmpty == "" {
		return &cals[0], nil
	}
	available := make([]string, 0, len(cals))
	for i := range cals {
		c := &cals[i]
		available = append(available, c.Name)
		if c.Name == nameOrEmpty {
			return c, nil
		}
		// Match URL tail (e.g. ".../<user>/<calendar-id>/").
		tail := strings.TrimRight(c.Path, "/")
		if strings.HasSuffix(tail, "/"+nameOrEmpty) {
			return c, nil
		}
	}
	return nil, fmt.Errorf("calendar %q not found; available: %v", nameOrEmpty, available)
}

func (r *radicaleClient) findAddressBook(ctx context.Context, nameOrEmpty string) (*carddav.AddressBook, error) {
	abs, err := r.listAddressBooks(ctx)
	if err != nil {
		return nil, err
	}
	if len(abs) == 0 {
		return nil, errors.New("no addressbooks found for the configured Radicale user")
	}
	if nameOrEmpty == "" {
		return &abs[0], nil
	}
	available := make([]string, 0, len(abs))
	for i := range abs {
		a := &abs[i]
		available = append(available, a.Name)
		if a.Name == nameOrEmpty {
			return a, nil
		}
		tail := strings.TrimRight(a.Path, "/")
		if strings.HasSuffix(tail, "/"+nameOrEmpty) {
			return a, nil
		}
	}
	return nil, fmt.Errorf("addressbook %q not found; available: %v", nameOrEmpty, available)
}

// allCalendarObjects fetches every VEVENT/VTODO in a calendar via a
// REPORT query with no time bound. compName is "VEVENT" or "VTODO".
func (r *radicaleClient) allCalendarObjects(
	ctx context.Context, calPath, compName string,
	start, end time.Time,
) ([]caldav.CalendarObject, error) {
	q := &caldav.CalendarQuery{
		CompRequest: caldav.CalendarCompRequest{
			Name:     ical.CompCalendar,
			AllProps: true,
			AllComps: true,
		},
		CompFilter: caldav.CompFilter{
			Name: ical.CompCalendar,
			Comps: []caldav.CompFilter{
				{
					Name:  compName,
					Start: start,
					End:   end,
				},
			},
		},
	}
	return r.cal.QueryCalendar(ctx, calPath, q)
}

// findEventByUID walks the calendar and returns the matching object + its
// inner *ical.Component (the VEVENT). Returns (nil, nil, nil) when missing.
func (r *radicaleClient) findEventByUID(
	ctx context.Context, calPath, uid string,
) (*caldav.CalendarObject, *ical.Component, error) {
	objs, err := r.allCalendarObjects(ctx, calPath, ical.CompEvent, time.Time{}, time.Time{})
	if err != nil {
		return nil, nil, err
	}
	for i := range objs {
		obj := &objs[i]
		if obj.Data == nil {
			continue
		}
		for _, c := range obj.Data.Children {
			if c.Name != ical.CompEvent {
				continue
			}
			if v, _ := c.Props.Text(ical.PropUID); v == uid {
				return obj, c, nil
			}
		}
	}
	return nil, nil, fmt.Errorf("event uid %q not found", uid)
}

func (r *radicaleClient) findTodoByUID(
	ctx context.Context, calPath, uid string,
) (*caldav.CalendarObject, *ical.Component, error) {
	objs, err := r.allCalendarObjects(ctx, calPath, ical.CompToDo, time.Time{}, time.Time{})
	if err != nil {
		return nil, nil, err
	}
	for i := range objs {
		obj := &objs[i]
		if obj.Data == nil {
			continue
		}
		for _, c := range obj.Data.Children {
			if c.Name != ical.CompToDo {
				continue
			}
			if v, _ := c.Props.Text(ical.PropUID); v == uid {
				return obj, c, nil
			}
		}
	}
	return nil, nil, fmt.Errorf("task uid %q not found", uid)
}

// findContactByUID walks an addressbook looking for the VCARD whose UID matches.
func (r *radicaleClient) findContactByUID(
	ctx context.Context, abPath, uid string,
) (*carddav.AddressObject, error) {
	q := &carddav.AddressBookQuery{
		DataRequest: carddav.AddressDataRequest{AllProp: true},
	}
	objs, err := r.card.QueryAddressBook(ctx, abPath, q)
	if err != nil {
		return nil, err
	}
	for i := range objs {
		o := &objs[i]
		if v := o.Card.Value(vcard.FieldUID); v == uid {
			return o, nil
		}
	}
	return nil, fmt.Errorf("contact uid %q not found", uid)
}

// ─── ical / vcard helpers ───────────────────────────────────────────────────

// parseDT parses an ISO-8601 datetime. Naive strings get attached to
// `tzName` (or the configured default zone if tzName is empty).
//
// Accepted forms:
//   2026-05-12T15:00:00Z         -> explicit UTC
//   2026-05-12T15:00:00-05:00    -> explicit offset
//   2026-05-12T15:00:00          -> naive, attach default zone
func parseDT(s, tzName string, defaultTZ *time.Location) (time.Time, error) {
	if s == "" {
		return time.Time{}, errors.New("empty datetime")
	}
	// Layouts we try in order. RFC3339 covers offset/Z forms; the bare
	// 2006-01-02T15:04:05 layout catches naive datetimes.
	layouts := []struct {
		layout string
		naive  bool
	}{
		{time.RFC3339Nano, false},
		{time.RFC3339, false},
		{"2006-01-02T15:04:05", true},
		{"2006-01-02T15:04", true},
		{"2006-01-02", true},
	}
	for _, l := range layouts {
		if l.naive {
			loc := defaultTZ
			if tzName != "" {
				z, err := time.LoadLocation(tzName)
				if err != nil {
					return time.Time{}, fmt.Errorf("unknown timezone %q: %w", tzName, err)
				}
				loc = z
			}
			if t, err := time.ParseInLocation(l.layout, s, loc); err == nil {
				return t, nil
			}
		} else if t, err := time.Parse(l.layout, s); err == nil {
			return t, nil
		}
	}
	return time.Time{}, fmt.Errorf("bad ISO datetime %q", s)
}

// objectPath builds a target href under a collection path, appending the
// given filename (typically "<uid>.ics" or "<uid>.vcf").
func objectPath(collectionPath, filename string) string {
	return path.Join(strings.TrimRight(collectionPath, "/"), filename)
}

// vEventSummary builds the JSON-friendly dict returned for VEVENTs. Matches
// the Python implementation field-for-field (uid, summary, url, dtstart,
// dtend, description, location when present).
func vEventSummary(obj *caldav.CalendarObject, ve *ical.Component) map[string]any {
	out := map[string]any{
		"url": obj.Path,
	}
	if v, _ := ve.Props.Text(ical.PropUID); v != "" {
		out["uid"] = v
	}
	if v, _ := ve.Props.Text(ical.PropSummary); v != "" {
		out["summary"] = v
	} else {
		out["summary"] = ""
	}
	if t, err := ve.Props.DateTime(ical.PropDateTimeStart, time.UTC); err == nil && !t.IsZero() {
		out["dtstart"] = t.Format(time.RFC3339)
	}
	if t, err := ve.Props.DateTime(ical.PropDateTimeEnd, time.UTC); err == nil && !t.IsZero() {
		out["dtend"] = t.Format(time.RFC3339)
	}
	if v, _ := ve.Props.Text(ical.PropDescription); v != "" {
		out["description"] = v
	}
	if v, _ := ve.Props.Text(ical.PropLocation); v != "" {
		out["location"] = v
	}
	if rrule := ve.Props.Get(ical.PropRecurrenceRule); rrule != nil {
		out["rrule"] = rrule.Value
	}
	return out
}

func vTodoSummary(obj *caldav.CalendarObject, vt *ical.Component) map[string]any {
	out := map[string]any{
		"url": obj.Path,
	}
	if v, _ := vt.Props.Text(ical.PropUID); v != "" {
		out["uid"] = v
	}
	if v, _ := vt.Props.Text(ical.PropSummary); v != "" {
		out["summary"] = v
	} else {
		out["summary"] = ""
	}
	if t, err := vt.Props.DateTime(ical.PropDue, time.UTC); err == nil && !t.IsZero() {
		out["due"] = t.Format(time.RFC3339)
	}
	if v, _ := vt.Props.Text(ical.PropDescription); v != "" {
		out["description"] = v
	}
	if v, _ := vt.Props.Text(ical.PropStatus); v != "" {
		out["status"] = v
	}
	if v, _ := vt.Props.Text(ical.PropPriority); v != "" {
		out["priority"] = v
	}
	if t, err := vt.Props.DateTime(ical.PropCompleted, time.UTC); err == nil && !t.IsZero() {
		out["completed"] = t.Format(time.RFC3339)
	}
	return out
}

// vCardSummary mirrors Python's _vcard_summary: uid, url, fn + optional
// email[], tel[], org, note.
func vCardSummary(obj *carddav.AddressObject) map[string]any {
	out := map[string]any{
		"url": obj.Path,
		"uid": obj.Card.Value(vcard.FieldUID),
		"fn":  obj.Card.Value(vcard.FieldFormattedName),
	}
	if emails := obj.Card.Values(vcard.FieldEmail); len(emails) > 0 {
		out["email"] = emails
	}
	if tels := obj.Card.Values(vcard.FieldTelephone); len(tels) > 0 {
		out["tel"] = tels
	}
	if org := obj.Card.Value(vcard.FieldOrganization); org != "" {
		out["org"] = org
	}
	if note := obj.Card.Value(vcard.FieldNote); note != "" {
		out["note"] = note
	}
	return out
}

// ─── RRULE normalization ────────────────────────────────────────────────────

var rruleListKeys = map[string]bool{
	"BYDAY": true, "BYMONTHDAY": true, "BYYEARDAY": true, "BYWEEKNO": true,
	"BYMONTH": true, "BYSETPOS": true, "BYHOUR": true, "BYMINUTE": true,
	"BYSECOND": true,
}

// normalizeRRule accepts either:
//   * a string in RFC-5545 form ("FREQ=WEEKLY;BYDAY=MO,WE")
//   * a map with FREQ + companion keys (lists allowed for BY* keys)
// Returns the canonical RFC-5545 string or "" when input is nil/empty.
func normalizeRRule(rruleArg any) (string, error) {
	if rruleArg == nil {
		return "", nil
	}
	switch v := rruleArg.(type) {
	case string:
		s := strings.TrimSpace(v)
		if s == "" {
			return "", nil
		}
		if strings.HasPrefix(strings.ToUpper(s), "RRULE:") {
			s = s[6:]
		}
		if !strings.Contains(strings.ToUpper(s), "FREQ=") {
			return "", fmt.Errorf("RRULE string must contain FREQ=… (got %q)", s)
		}
		return s, nil
	case map[string]any:
		if len(v) == 0 {
			return "", nil
		}
		// Uppercase keys (Python uppercases for consistency).
		upper := make(map[string]any, len(v))
		for k, val := range v {
			upper[strings.ToUpper(k)] = val
		}
		freq, ok := upper["FREQ"]
		if !ok {
			return "", errors.New("RRULE map must contain FREQ (e.g. DAILY/WEEKLY/MONTHLY/YEARLY)")
		}
		parts := []string{fmt.Sprintf("FREQ=%s", strings.ToUpper(fmt.Sprint(freq)))}
		for key, val := range upper {
			if key == "FREQ" {
				continue
			}
			switch {
			case rruleListKeys[key]:
				switch vv := val.(type) {
				case []any:
					parts = append(parts, fmt.Sprintf("%s=%s", key, joinAny(vv, ",")))
				default:
					parts = append(parts, fmt.Sprintf("%s=%v", key, val))
				}
			case key == "UNTIL":
				s := strings.ReplaceAll(strings.ReplaceAll(fmt.Sprint(val), "-", ""), ":", "")
				if !strings.Contains(s, "T") {
					s = s + "T000000Z"
				} else if !strings.HasSuffix(s, "Z") {
					s = s + "Z"
				}
				parts = append(parts, fmt.Sprintf("UNTIL=%s", s))
			default:
				parts = append(parts, fmt.Sprintf("%s=%v", key, val))
			}
		}
		return strings.Join(parts, ";"), nil
	default:
		return "", fmt.Errorf("rrule must be string, map, or null (got %T)", rruleArg)
	}
}

func joinAny(items []any, sep string) string {
	out := make([]string, len(items))
	for i, it := range items {
		out[i] = strings.ToUpper(fmt.Sprint(it))
	}
	return strings.Join(out, sep)
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

// ─── Calendar / addressbook discovery tools ─────────────────────────────────

func handlerCalendarList(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		cals, err := rc.listCalendars(ctx)
		if err != nil {
			return toolErr(err), nil
		}
		out := make([]map[string]any, 0, len(cals))
		for _, c := range cals {
			out = append(out, map[string]any{"name": c.Name, "url": c.Path})
		}
		return toolResultJSON(out), nil
	}
}

func handlerAddressBookList(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		abs, err := rc.listAddressBooks(ctx)
		if err != nil {
			return toolErr(err), nil
		}
		out := make([]map[string]any, 0, len(abs))
		for _, a := range abs {
			out = append(out, map[string]any{"name": a.Name, "url": a.Path})
		}
		return toolResultJSON(out), nil
	}
}

// ─── Event tools ────────────────────────────────────────────────────────────

func newVEvent(uid string, dtstart, dtend time.Time, summary, description, location string) *ical.Calendar {
	cal := ical.NewCalendar()
	cal.Props.SetText(ical.PropProductID, "-//mcculleytech//radicale-mcp//EN")
	cal.Props.SetText(ical.PropVersion, "2.0")

	ev := ical.NewEvent()
	ev.Props.SetText(ical.PropUID, uid)
	ev.Props.SetDateTime(ical.PropDateTimeStamp, time.Now().UTC())
	ev.Props.SetDateTime(ical.PropDateTimeStart, dtstart)
	ev.Props.SetDateTime(ical.PropDateTimeEnd, dtend)
	ev.Props.SetText(ical.PropSummary, summary)
	if description != "" {
		ev.Props.SetText(ical.PropDescription, description)
	}
	if location != "" {
		ev.Props.SetText(ical.PropLocation, location)
	}
	cal.Children = append(cal.Children, ev.Component)
	return cal
}

func handlerEventCreate(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		summary, err := req.RequireString("summary")
		if err != nil {
			return toolErr(err), nil
		}
		startS, err := req.RequireString("start")
		if err != nil {
			return toolErr(err), nil
		}
		endS, err := req.RequireString("end")
		if err != nil {
			return toolErr(err), nil
		}
		calName := req.GetString("calendar", "")
		desc := req.GetString("description", "")
		loc := req.GetString("location", "")
		tz := req.GetString("tz", "")

		c, err := rc.findCalendar(ctx, calName)
		if err != nil {
			return toolErr(err), nil
		}
		dts, err := parseDT(startS, tz, rc.cfg.DefaultTZ)
		if err != nil {
			return toolErr(err), nil
		}
		dte, err := parseDT(endS, tz, rc.cfg.DefaultTZ)
		if err != nil {
			return toolErr(err), nil
		}
		rruleStr, err := normalizeRRule(req.GetArguments()["rrule"])
		if err != nil {
			return toolErr(err), nil
		}
		uid := uuid.NewString()
		calObj := newVEvent(uid, dts, dte, summary, desc, loc)
		if rruleStr != "" {
			// Set RRULE as a raw string prop. The ical encoder will emit it
			// verbatim; Radicale parses it on save.
			p := ical.NewProp(ical.PropRecurrenceRule)
			p.Value = rruleStr
			calObj.Children[0].Props.Set(p)
		}

		target := objectPath(c.Path, uid+".ics")
		if _, err := rc.cal.PutCalendarObject(ctx, target, calObj); err != nil {
			return toolErr(fmt.Errorf("put event: %w", err)), nil
		}
		out := map[string]any{
			"uid":      uid,
			"calendar": c.Name,
			"summary":  summary,
			"start":    dts.Format(time.RFC3339),
			"end":      dte.Format(time.RFC3339),
		}
		if rruleStr != "" {
			out["rrule"] = rruleStr
		} else {
			out["rrule"] = nil
		}
		return toolResultJSON(out), nil
	}
}

func handlerEventList(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		calName := req.GetString("calendar", "")
		startS := req.GetString("start", "")
		endS := req.GetString("end", "")
		limit := req.GetInt("limit", 50)
		tz := req.GetString("tz", "")
		c, err := rc.findCalendar(ctx, calName)
		if err != nil {
			return toolErr(err), nil
		}
		var startT, endT time.Time
		if startS != "" {
			startT, err = parseDT(startS, tz, rc.cfg.DefaultTZ)
			if err != nil {
				return toolErr(err), nil
			}
		}
		if endS != "" {
			endT, err = parseDT(endS, tz, rc.cfg.DefaultTZ)
			if err != nil {
				return toolErr(err), nil
			}
		}
		objs, err := rc.allCalendarObjects(ctx, c.Path, ical.CompEvent, startT, endT)
		if err != nil {
			return toolErr(err), nil
		}
		out := make([]map[string]any, 0, len(objs))
		for i := range objs {
			obj := &objs[i]
			if obj.Data == nil {
				continue
			}
			for _, child := range obj.Data.Children {
				if child.Name != ical.CompEvent {
					continue
				}
				out = append(out, vEventSummary(obj, child))
				if len(out) >= limit {
					break
				}
			}
			if len(out) >= limit {
				break
			}
		}
		return toolResultJSON(out), nil
	}
}

func handlerEventUpdate(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		uid, err := req.RequireString("uid")
		if err != nil {
			return toolErr(err), nil
		}
		calName := req.GetString("calendar", "")
		clearRRule := req.GetBool("clear_rrule", false)
		_, hasRRule := req.GetArguments()["rrule"]
		if hasRRule && clearRRule {
			return toolErr(errors.New("pass either rrule or clear_rrule, not both")), nil
		}
		c, err := rc.findCalendar(ctx, calName)
		if err != nil {
			return toolErr(err), nil
		}
		obj, ve, err := rc.findEventByUID(ctx, c.Path, uid)
		if err != nil {
			return toolErr(err), nil
		}
		tz := req.GetString("tz", "")
		if v := req.GetString("summary", ""); v != "" {
			ve.Props.SetText(ical.PropSummary, v)
		}
		if v := req.GetString("start", ""); v != "" {
			t, err := parseDT(v, tz, rc.cfg.DefaultTZ)
			if err != nil {
				return toolErr(err), nil
			}
			ve.Props.SetDateTime(ical.PropDateTimeStart, t)
		}
		if v := req.GetString("end", ""); v != "" {
			t, err := parseDT(v, tz, rc.cfg.DefaultTZ)
			if err != nil {
				return toolErr(err), nil
			}
			ve.Props.SetDateTime(ical.PropDateTimeEnd, t)
		}
		if v := req.GetString("description", ""); v != "" {
			ve.Props.SetText(ical.PropDescription, v)
		}
		if v := req.GetString("location", ""); v != "" {
			ve.Props.SetText(ical.PropLocation, v)
		}
		ve.Props.SetDateTime(ical.PropLastModified, time.Now().UTC())
		if clearRRule {
			ve.Props.Del(ical.PropRecurrenceRule)
		} else if hasRRule {
			rruleStr, err := normalizeRRule(req.GetArguments()["rrule"])
			if err != nil {
				return toolErr(err), nil
			}
			if rruleStr == "" {
				ve.Props.Del(ical.PropRecurrenceRule)
			} else {
				p := ical.NewProp(ical.PropRecurrenceRule)
				p.Value = rruleStr
				ve.Props.Set(p)
			}
		}
		if _, err := rc.cal.PutCalendarObject(ctx, obj.Path, obj.Data); err != nil {
			return toolErr(fmt.Errorf("put event: %w", err)), nil
		}
		return toolResultJSON(vEventSummary(obj, ve)), nil
	}
}

func handlerEventDelete(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		uid, err := req.RequireString("uid")
		if err != nil {
			return toolErr(err), nil
		}
		calName := req.GetString("calendar", "")
		c, err := rc.findCalendar(ctx, calName)
		if err != nil {
			return toolErr(err), nil
		}
		obj, _, err := rc.findEventByUID(ctx, c.Path, uid)
		if err != nil {
			return toolErr(err), nil
		}
		if err := davDelete(ctx, rc.cfg, obj.Path); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(map[string]any{"deleted": true, "uid": uid}), nil
	}
}

// davDelete issues a raw HTTP DELETE to a Radicale resource path. The go-webdav
// caldav/carddav clients don't expose Delete on the resource directly; rather
// than route through the lower-level internal client, we just do a plain HTTP
// DELETE with the same basic-auth credentials.
func davDelete(ctx context.Context, cfg *config, resourcePath string) error {
	u := cfg.RadicaleURL
	// caldav.Path values come back as the server-absolute path (e.g.
	// "/dav/<user>/<cal>/<uid>.ics"). Combine with the URL's scheme+host only.
	target, err := joinURLPath(u, resourcePath)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, target, nil)
	if err != nil {
		return err
	}
	req.SetBasicAuth(cfg.RadicaleUser, cfg.RadicalePass)
	hc := &http.Client{Timeout: 30 * time.Second}
	resp, err := hc.Do(req)
	if err != nil {
		return fmt.Errorf("dav delete: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return fmt.Errorf("dav delete %s -> %d", target, resp.StatusCode)
	}
	return nil
}

// joinURLPath replaces the path component of base with the given absolute
// resource path (or appends it if base has its own path prefix). When the
// resource path is already absolute (starts with /), it wins over base's path.
func joinURLPath(base, resourcePath string) (string, error) {
	// Strip any trailing slash from base.
	b := strings.TrimRight(base, "/")
	// Resource paths from the caldav client are server-absolute.
	if strings.HasPrefix(resourcePath, "/") {
		// Slice off any path component of base; keep scheme://host[:port].
		idx := strings.Index(b, "://")
		if idx < 0 {
			return "", fmt.Errorf("malformed base url: %s", base)
		}
		rest := b[idx+3:]
		if slash := strings.Index(rest, "/"); slash >= 0 {
			return b[:idx+3] + rest[:slash] + resourcePath, nil
		}
		return b + resourcePath, nil
	}
	return b + "/" + resourcePath, nil
}

// ─── Task (VTODO) tools ─────────────────────────────────────────────────────

func newVTodo(uid, summary, description string, due time.Time, priority int) *ical.Calendar {
	cal := ical.NewCalendar()
	cal.Props.SetText(ical.PropProductID, "-//mcculleytech//radicale-mcp//EN")
	cal.Props.SetText(ical.PropVersion, "2.0")

	t := ical.NewComponent(ical.CompToDo)
	t.Props.SetText(ical.PropUID, uid)
	t.Props.SetDateTime(ical.PropDateTimeStamp, time.Now().UTC())
	t.Props.SetText(ical.PropSummary, summary)
	if !due.IsZero() {
		t.Props.SetDateTime(ical.PropDue, due)
	}
	if description != "" {
		t.Props.SetText(ical.PropDescription, description)
	}
	if priority != 0 {
		p := ical.NewProp(ical.PropPriority)
		p.Value = strconv.Itoa(priority)
		t.Props.Set(p)
	}
	cal.Children = append(cal.Children, t)
	return cal
}

func handlerTaskCreate(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		summary, err := req.RequireString("summary")
		if err != nil {
			return toolErr(err), nil
		}
		calName := req.GetString("calendar", "")
		dueS := req.GetString("due", "")
		desc := req.GetString("description", "")
		tz := req.GetString("tz", "")
		priority := req.GetInt("priority", 0)

		c, err := rc.findCalendar(ctx, calName)
		if err != nil {
			return toolErr(err), nil
		}
		var dueT time.Time
		if dueS != "" {
			dueT, err = parseDT(dueS, tz, rc.cfg.DefaultTZ)
			if err != nil {
				return toolErr(err), nil
			}
		}
		uid := uuid.NewString()
		todo := newVTodo(uid, summary, desc, dueT, priority)
		target := objectPath(c.Path, uid+".ics")
		if _, err := rc.cal.PutCalendarObject(ctx, target, todo); err != nil {
			return toolErr(fmt.Errorf("put todo: %w", err)), nil
		}
		return toolResultJSON(map[string]any{
			"uid":      uid,
			"calendar": c.Name,
			"summary":  summary,
		}), nil
	}
}

func handlerTaskList(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		calName := req.GetString("calendar", "")
		includeCompleted := req.GetBool("include_completed", false)
		limit := req.GetInt("limit", 50)
		c, err := rc.findCalendar(ctx, calName)
		if err != nil {
			return toolErr(err), nil
		}
		objs, err := rc.allCalendarObjects(ctx, c.Path, ical.CompToDo, time.Time{}, time.Time{})
		if err != nil {
			return toolErr(err), nil
		}
		out := make([]map[string]any, 0, len(objs))
		for i := range objs {
			obj := &objs[i]
			if obj.Data == nil {
				continue
			}
			for _, child := range obj.Data.Children {
				if child.Name != ical.CompToDo {
					continue
				}
				if !includeCompleted {
					if status, _ := child.Props.Text(ical.PropStatus); strings.EqualFold(status, "COMPLETED") {
						continue
					}
				}
				out = append(out, vTodoSummary(obj, child))
				if len(out) >= limit {
					break
				}
			}
			if len(out) >= limit {
				break
			}
		}
		return toolResultJSON(out), nil
	}
}

func handlerTaskComplete(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		uid, err := req.RequireString("uid")
		if err != nil {
			return toolErr(err), nil
		}
		calName := req.GetString("calendar", "")
		c, err := rc.findCalendar(ctx, calName)
		if err != nil {
			return toolErr(err), nil
		}
		obj, vt, err := rc.findTodoByUID(ctx, c.Path, uid)
		if err != nil {
			return toolErr(err), nil
		}
		now := time.Now().UTC()
		vt.Props.SetText(ical.PropStatus, "COMPLETED")
		vt.Props.SetDateTime(ical.PropCompleted, now)
		vt.Props.SetDateTime(ical.PropLastModified, now)
		pc := ical.NewProp("PERCENT-COMPLETE")
		pc.Value = "100"
		vt.Props.Set(pc)
		if _, err := rc.cal.PutCalendarObject(ctx, obj.Path, obj.Data); err != nil {
			return toolErr(fmt.Errorf("put todo: %w", err)), nil
		}
		return toolResultJSON(vTodoSummary(obj, vt)), nil
	}
}

func handlerTaskDelete(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		uid, err := req.RequireString("uid")
		if err != nil {
			return toolErr(err), nil
		}
		calName := req.GetString("calendar", "")
		c, err := rc.findCalendar(ctx, calName)
		if err != nil {
			return toolErr(err), nil
		}
		obj, _, err := rc.findTodoByUID(ctx, c.Path, uid)
		if err != nil {
			return toolErr(err), nil
		}
		if err := davDelete(ctx, rc.cfg, obj.Path); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(map[string]any{"deleted": true, "uid": uid}), nil
	}
}

// ─── Contact (VCARD) tools ──────────────────────────────────────────────────

func newVCard(uid, fn, email, tel, org, note string) vcard.Card {
	card := vcard.Card{}
	card.SetValue(vcard.FieldVersion, "3.0")
	card.SetValue(vcard.FieldFormattedName, fn)
	// N field: family;given;additional;prefix;suffix
	var family, given string
	parts := strings.Fields(fn)
	switch len(parts) {
	case 0:
		// leave empty
	case 1:
		family = parts[0]
		given = parts[0]
	default:
		family = parts[len(parts)-1]
		given = strings.Join(parts[:len(parts)-1], " ")
	}
	n := &vcard.Name{
		FamilyName: family,
		GivenName:  given,
	}
	card.SetName(n)
	card.SetValue(vcard.FieldUID, uid)
	if email != "" {
		f := &vcard.Field{Value: email, Params: vcard.Params{vcard.ParamType: []string{"INTERNET"}}}
		card.Add(vcard.FieldEmail, f)
	}
	if tel != "" {
		f := &vcard.Field{Value: tel, Params: vcard.Params{vcard.ParamType: []string{"CELL"}}}
		card.Add(vcard.FieldTelephone, f)
	}
	if org != "" {
		card.SetValue(vcard.FieldOrganization, org)
	}
	if note != "" {
		card.SetValue(vcard.FieldNote, note)
	}
	return card
}

func handlerContactCreate(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		fn, err := req.RequireString("fn")
		if err != nil {
			return toolErr(err), nil
		}
		abName := req.GetString("addressbook", "")
		email := req.GetString("email", "")
		tel := req.GetString("tel", "")
		org := req.GetString("org", "")
		note := req.GetString("note", "")
		ab, err := rc.findAddressBook(ctx, abName)
		if err != nil {
			return toolErr(err), nil
		}
		uid := uuid.NewString()
		card := newVCard(uid, fn, email, tel, org, note)
		target := objectPath(ab.Path, uid+".vcf")
		if _, err := rc.card.PutAddressObject(ctx, target, card); err != nil {
			return toolErr(fmt.Errorf("put vcard: %w", err)), nil
		}
		return toolResultJSON(map[string]any{
			"uid":         uid,
			"addressbook": ab.Name,
			"fn":          fn,
		}), nil
	}
}

func handlerContactList(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		abName := req.GetString("addressbook", "")
		limit := req.GetInt("limit", 200)
		ab, err := rc.findAddressBook(ctx, abName)
		if err != nil {
			return toolErr(err), nil
		}
		q := &carddav.AddressBookQuery{
			DataRequest: carddav.AddressDataRequest{AllProp: true},
		}
		objs, err := rc.card.QueryAddressBook(ctx, ab.Path, q)
		if err != nil {
			return toolErr(err), nil
		}
		out := make([]map[string]any, 0, len(objs))
		for i := range objs {
			out = append(out, vCardSummary(&objs[i]))
			if len(out) >= limit {
				break
			}
		}
		return toolResultJSON(out), nil
	}
}

func handlerContactSearch(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		query, err := req.RequireString("query")
		if err != nil {
			return toolErr(err), nil
		}
		abName := req.GetString("addressbook", "")
		limit := req.GetInt("limit", 50)
		ab, err := rc.findAddressBook(ctx, abName)
		if err != nil {
			return toolErr(err), nil
		}
		q := &carddav.AddressBookQuery{
			DataRequest: carddav.AddressDataRequest{AllProp: true},
		}
		objs, err := rc.card.QueryAddressBook(ctx, ab.Path, q)
		if err != nil {
			return toolErr(err), nil
		}
		needle := strings.ToLower(query)
		out := make([]map[string]any, 0)
		for i := range objs {
			s := vCardSummary(&objs[i])
			blob := strings.Builder{}
			blob.WriteString(strings.ToLower(fmt.Sprint(s["fn"])))
			blob.WriteByte(' ')
			if emails, ok := s["email"].([]string); ok {
				for _, e := range emails {
					blob.WriteString(strings.ToLower(e))
					blob.WriteByte(' ')
				}
			}
			if tels, ok := s["tel"].([]string); ok {
				for _, t := range tels {
					blob.WriteString(strings.ToLower(t))
					blob.WriteByte(' ')
				}
			}
			if v, ok := s["org"].(string); ok {
				blob.WriteString(strings.ToLower(v))
				blob.WriteByte(' ')
			}
			if v, ok := s["note"].(string); ok {
				blob.WriteString(strings.ToLower(v))
			}
			if strings.Contains(blob.String(), needle) {
				out = append(out, s)
				if len(out) >= limit {
					break
				}
			}
		}
		return toolResultJSON(out), nil
	}
}

func handlerContactUpdate(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		uid, err := req.RequireString("uid")
		if err != nil {
			return toolErr(err), nil
		}
		abName := req.GetString("addressbook", "")
		ab, err := rc.findAddressBook(ctx, abName)
		if err != nil {
			return toolErr(err), nil
		}
		obj, err := rc.findContactByUID(ctx, ab.Path, uid)
		if err != nil {
			return toolResultJSON(map[string]any{"error": err.Error()}), nil
		}
		args := req.GetArguments()
		if v, ok := args["fn"].(string); ok && v != "" {
			obj.Card.SetValue(vcard.FieldFormattedName, v)
		}
		if v, ok := args["email"].(string); ok && v != "" {
			if existing := obj.Card.Get(vcard.FieldEmail); existing != nil {
				existing.Value = v
			} else {
				obj.Card.Add(vcard.FieldEmail, &vcard.Field{
					Value: v, Params: vcard.Params{vcard.ParamType: []string{"INTERNET"}},
				})
			}
		}
		if v, ok := args["tel"].(string); ok && v != "" {
			if existing := obj.Card.Get(vcard.FieldTelephone); existing != nil {
				existing.Value = v
			} else {
				obj.Card.Add(vcard.FieldTelephone, &vcard.Field{
					Value: v, Params: vcard.Params{vcard.ParamType: []string{"CELL"}},
				})
			}
		}
		if v, ok := args["org"].(string); ok && v != "" {
			obj.Card.SetValue(vcard.FieldOrganization, v)
		}
		if v, ok := args["note"].(string); ok && v != "" {
			obj.Card.SetValue(vcard.FieldNote, v)
		}
		obj.Card.SetRevision(time.Now().UTC())
		if _, err := rc.card.PutAddressObject(ctx, obj.Path, obj.Card); err != nil {
			return toolErr(fmt.Errorf("put vcard: %w", err)), nil
		}
		return toolResultJSON(vCardSummary(obj)), nil
	}
}

func handlerContactDelete(rc *radicaleClient) server.ToolHandlerFunc {
	return func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		uid, err := req.RequireString("uid")
		if err != nil {
			return toolErr(err), nil
		}
		abName := req.GetString("addressbook", "")
		ab, err := rc.findAddressBook(ctx, abName)
		if err != nil {
			return toolErr(err), nil
		}
		obj, err := rc.findContactByUID(ctx, ab.Path, uid)
		if err != nil {
			return toolResultJSON(map[string]any{"error": err.Error()}), nil
		}
		if err := davDelete(ctx, rc.cfg, obj.Path); err != nil {
			return toolErr(err), nil
		}
		return toolResultJSON(map[string]any{"deleted": true, "uid": uid}), nil
	}
}

// ─── Tool registration ──────────────────────────────────────────────────────

func registerTools(s *server.MCPServer, rc *radicaleClient) {
	s.AddTool(mcp.NewTool("calendar_list",
		mcp.WithDescription("List all calendars on the configured Radicale account."),
	), handlerCalendarList(rc))

	s.AddTool(mcp.NewTool("addressbook_list",
		mcp.WithDescription("List all address books on the configured Radicale account."),
	), handlerAddressBookList(rc))

	s.AddTool(mcp.NewTool("event_create",
		mcp.WithDescription(`Create a calendar event (VEVENT).

start / end are ISO-8601 datetimes. If they don't include a timezone offset or 'Z' suffix, they're interpreted in the IANA zone tz (e.g. 'America/Chicago'); if tz is also omitted, the server's configured default zone is used.

rrule makes the event recurring. Accepts either:
  RFC-5545 string: 'FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261231T235959Z'
  Object form:    {"FREQ": "WEEKLY", "BYDAY": ["MO","WE","FR"], "UNTIL": "2026-12-31T23:59:59"}
FREQ is required (DAILY/WEEKLY/MONTHLY/YEARLY).`),
		mcp.WithString("summary", mcp.Description("Event title."), mcp.Required()),
		mcp.WithString("start", mcp.Description("ISO-8601 start datetime."), mcp.Required()),
		mcp.WithString("end", mcp.Description("ISO-8601 end datetime."), mcp.Required()),
		mcp.WithString("calendar", mcp.Description("Calendar display name (default: first calendar).")),
		mcp.WithString("description", mcp.Description("Long-form description.")),
		mcp.WithString("location", mcp.Description("Location string.")),
		mcp.WithString("tz", mcp.Description("IANA timezone for naive start/end (e.g. 'America/Chicago').")),
		mcp.WithObject("rrule", mcp.Description("Recurrence rule as object or RFC-5545 string.")),
	), handlerEventCreate(rc))

	s.AddTool(mcp.NewTool("event_list",
		mcp.WithDescription("List events in a calendar within an optional [start, end] window."),
		mcp.WithString("calendar", mcp.Description("Calendar display name.")),
		mcp.WithString("start", mcp.Description("ISO-8601 window start.")),
		mcp.WithString("end", mcp.Description("ISO-8601 window end.")),
		mcp.WithNumber("limit", mcp.Description("Max results (default 50).")),
		mcp.WithString("tz", mcp.Description("IANA timezone for naive start/end.")),
	), handlerEventList(rc))

	s.AddTool(mcp.NewTool("event_update",
		mcp.WithDescription("Update fields on an existing event by UID. Pass rrule to set/replace recurrence, or clear_rrule=true to remove it."),
		mcp.WithString("uid", mcp.Description("Event UID."), mcp.Required()),
		mcp.WithString("calendar", mcp.Description("Calendar display name.")),
		mcp.WithString("summary", mcp.Description("New title.")),
		mcp.WithString("start", mcp.Description("New ISO-8601 start.")),
		mcp.WithString("end", mcp.Description("New ISO-8601 end.")),
		mcp.WithString("description", mcp.Description("New description.")),
		mcp.WithString("location", mcp.Description("New location.")),
		mcp.WithString("tz", mcp.Description("IANA timezone for naive start/end.")),
		mcp.WithObject("rrule", mcp.Description("New recurrence rule (object or string).")),
		mcp.WithBoolean("clear_rrule", mcp.Description("Remove existing RRULE.")),
	), handlerEventUpdate(rc))

	s.AddTool(mcp.NewTool("event_delete",
		mcp.WithDescription("Delete an event by UID."),
		mcp.WithString("uid", mcp.Description("Event UID."), mcp.Required()),
		mcp.WithString("calendar", mcp.Description("Calendar display name.")),
	), handlerEventDelete(rc))

	s.AddTool(mcp.NewTool("task_create",
		mcp.WithDescription("Create a task (VTODO) in the given calendar. due follows the same timezone rules as event_create."),
		mcp.WithString("summary", mcp.Description("Task title."), mcp.Required()),
		mcp.WithString("calendar", mcp.Description("Calendar display name.")),
		mcp.WithString("due", mcp.Description("ISO-8601 due datetime.")),
		mcp.WithString("description", mcp.Description("Long-form description.")),
		mcp.WithNumber("priority", mcp.Description("0–9 priority (lower = higher).")),
		mcp.WithString("tz", mcp.Description("IANA timezone for naive due.")),
	), handlerTaskCreate(rc))

	s.AddTool(mcp.NewTool("task_list",
		mcp.WithDescription("List tasks (VTODO) in a calendar. By default excludes completed."),
		mcp.WithString("calendar", mcp.Description("Calendar display name.")),
		mcp.WithBoolean("include_completed", mcp.Description("Include completed tasks (default false).")),
		mcp.WithNumber("limit", mcp.Description("Max results (default 50).")),
	), handlerTaskList(rc))

	s.AddTool(mcp.NewTool("task_complete",
		mcp.WithDescription("Mark a task as completed."),
		mcp.WithString("uid", mcp.Description("Task UID."), mcp.Required()),
		mcp.WithString("calendar", mcp.Description("Calendar display name.")),
	), handlerTaskComplete(rc))

	s.AddTool(mcp.NewTool("task_delete",
		mcp.WithDescription("Delete a task by UID."),
		mcp.WithString("uid", mcp.Description("Task UID."), mcp.Required()),
		mcp.WithString("calendar", mcp.Description("Calendar display name.")),
	), handlerTaskDelete(rc))

	s.AddTool(mcp.NewTool("contact_create",
		mcp.WithDescription("Create a contact (VCARD) in the given address book. fn is the formatted name."),
		mcp.WithString("fn", mcp.Description("Formatted name (e.g. 'Jane Doe')."), mcp.Required()),
		mcp.WithString("addressbook", mcp.Description("Address book name.")),
		mcp.WithString("email", mcp.Description("Single email address.")),
		mcp.WithString("tel", mcp.Description("Single telephone number.")),
		mcp.WithString("org", mcp.Description("Organization.")),
		mcp.WithString("note", mcp.Description("Free-form note.")),
	), handlerContactCreate(rc))

	s.AddTool(mcp.NewTool("contact_list",
		mcp.WithDescription("List contacts in the given address book."),
		mcp.WithString("addressbook", mcp.Description("Address book name.")),
		mcp.WithNumber("limit", mcp.Description("Max results (default 200).")),
	), handlerContactList(rc))

	s.AddTool(mcp.NewTool("contact_search",
		mcp.WithDescription("Substring search across contact FN / email / tel / org / note. Case-insensitive."),
		mcp.WithString("query", mcp.Description("Substring to match."), mcp.Required()),
		mcp.WithString("addressbook", mcp.Description("Address book name.")),
		mcp.WithNumber("limit", mcp.Description("Max results (default 50).")),
	), handlerContactSearch(rc))

	s.AddTool(mcp.NewTool("contact_update",
		mcp.WithDescription("Update fields on a contact. Single-value semantics — replaces the existing first email / tel / etc. if provided."),
		mcp.WithString("uid", mcp.Description("Contact UID."), mcp.Required()),
		mcp.WithString("addressbook", mcp.Description("Address book name.")),
		mcp.WithString("fn", mcp.Description("New formatted name.")),
		mcp.WithString("email", mcp.Description("Replace first email.")),
		mcp.WithString("tel", mcp.Description("Replace first telephone.")),
		mcp.WithString("org", mcp.Description("Replace organization.")),
		mcp.WithString("note", mcp.Description("Replace note.")),
	), handlerContactUpdate(rc))

	s.AddTool(mcp.NewTool("contact_delete",
		mcp.WithDescription("Delete a contact by UID."),
		mcp.WithString("uid", mcp.Description("Contact UID."), mcp.Required()),
		mcp.WithString("addressbook", mcp.Description("Address book name.")),
	), handlerContactDelete(rc))
}

// ─── HTTP endpoints (non-MCP) ───────────────────────────────────────────────

func healthHandler(rc *radicaleClient) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body := map[string]any{
			"status":        "ok",
			"radicale_url":  rc.cfg.RadicaleURL,
		}
		errs := map[string]string{}
		cals, err := rc.listCalendars(r.Context())
		if err != nil {
			errs["radicale"] = err.Error()
		} else {
			names := make([]string, 0, len(cals))
			for _, c := range cals {
				names = append(names, c.Name)
			}
			body["calendars"] = names
		}
		abs, err := rc.listAddressBooks(r.Context())
		if err != nil {
			errs["radicale_addressbooks"] = err.Error()
		} else {
			names := make([]string, 0, len(abs))
			for _, a := range abs {
				names = append(names, a.Name)
			}
			body["addressbooks"] = names
		}
		if len(errs) > 0 {
			body["status"] = "degraded"
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
	if v := os.Getenv("RADICALE_MCP_LOG_LEVEL"); strings.EqualFold(v, "debug") {
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

	rc, err := newRadicaleClient(cfg)
	if err != nil {
		slog.Error("radicale client", "err", err)
		os.Exit(1)
	}

	mcpServer := server.NewMCPServer(name, version,
		server.WithToolCapabilities(false),
	)
	registerTools(mcpServer, rc)

	streamable := server.NewStreamableHTTPServer(mcpServer)

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler(rc))
	mux.HandleFunc("/version", versionHandler())
	mux.Handle("/mcp", streamable)
	mux.Handle("/mcp/", streamable)

	authed := bearerAuthMiddleware(tokens, mux)

	addr := fmt.Sprintf("%s:%d", bindIP, cfg.Port)
	slog.Info("starting",
		"name", name, "version", version,
		"addr", addr,
		"radicale_url", cfg.RadicaleURL,
		"radicale_user", cfg.RadicaleUser,
		"default_tz", cfg.DefaultTZName,
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
