package main

import (
	"bytes"
	"strings"
	"testing"
	"time"

	"github.com/emersion/go-ical"
)

func TestLoadIANALocation_RejectsLocal(t *testing.T) {
	if _, err := loadIANALocation("Local"); err == nil {
		t.Fatal("loadIANALocation(\"Local\") should error, got nil")
	}
}

func TestLoadIANALocation_AcceptsIANA(t *testing.T) {
	for _, name := range []string{"UTC", "America/Chicago", "Europe/London"} {
		z, err := loadIANALocation(name)
		if err != nil {
			t.Fatalf("loadIANALocation(%q) errored: %v", name, err)
		}
		if z == time.Local {
			t.Fatalf("loadIANALocation(%q) returned time.Local", name)
		}
	}
}

func TestLoadIANALocation_RejectsUnknown(t *testing.T) {
	if _, err := loadIANALocation("Not/A/Zone"); err == nil {
		t.Fatal("loadIANALocation should reject unknown zone")
	}
}

func TestParseDT_RejectsTZLocal(t *testing.T) {
	def, _ := time.LoadLocation("America/Chicago")
	_, err := parseDT("2026-05-29T20:00:00", "Local", def)
	if err == nil {
		t.Fatal("parseDT with tz=\"Local\" should error")
	}
	if !strings.Contains(err.Error(), "non-IANA") {
		t.Fatalf("expected non-IANA error, got: %v", err)
	}
}

// Regression for the "Drinks at Woodgrain" bug: hermes passed tz="Local"
// and the resulting time would have serialized as TZID=Local. Now it
// errors instead.
func TestParseDT_NaiveWithIANA(t *testing.T) {
	def, _ := time.LoadLocation("UTC")
	chicago, _ := time.LoadLocation("America/Chicago")
	got, err := parseDT("2026-05-29T20:00:00", "America/Chicago", def)
	if err != nil {
		t.Fatalf("parseDT errored: %v", err)
	}
	if got.Location().String() != "America/Chicago" {
		t.Fatalf("expected America/Chicago, got %v", got.Location())
	}
	want := time.Date(2026, 5, 29, 20, 0, 0, 0, chicago)
	if !got.Equal(want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

func TestParseDT_NaiveUsesDefaultWhenTZEmpty(t *testing.T) {
	def, _ := time.LoadLocation("America/Chicago")
	got, err := parseDT("2026-05-29T20:00:00", "", def)
	if err != nil {
		t.Fatalf("parseDT errored: %v", err)
	}
	if got.Location().String() != "America/Chicago" {
		t.Fatalf("expected default America/Chicago, got %v", got.Location())
	}
}

func TestParseDT_ExplicitZIgnoresTZ(t *testing.T) {
	def, _ := time.LoadLocation("America/Chicago")
	got, err := parseDT("2026-05-30T01:00:00Z", "", def)
	if err != nil {
		t.Fatalf("parseDT errored: %v", err)
	}
	want := time.Date(2026, 5, 30, 1, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("expected %v, got %v", want, got)
	}
}

// Round-trip: build a VCALENDAR via newVEvent + ensureVTimezones, encode
// it, and assert the serialized output contains both the TZID reference
// and the VTIMEZONE block with the expected DST rules.
func TestEnsureVTimezones_RoundtripAmericaChicago(t *testing.T) {
	chicago, _ := time.LoadLocation("America/Chicago")
	start := time.Date(2026, 5, 29, 20, 0, 0, 0, chicago)
	end := time.Date(2026, 5, 29, 21, 0, 0, 0, chicago)
	cal := newVEvent("test-uid-123", start, end, "Drinks at Woodgrain", "", "Woodgrain")
	ensureVTimezones(cal.Component)

	var buf bytes.Buffer
	if err := ical.NewEncoder(&buf).Encode(cal); err != nil {
		t.Fatalf("encode failed: %v", err)
	}
	out := buf.String()

	for _, want := range []string{
		"BEGIN:VTIMEZONE",
		"TZID:America/Chicago",
		"BEGIN:STANDARD",
		"TZNAME:CST",
		"BEGIN:DAYLIGHT",
		"TZNAME:CDT",
		"DTSTART;TZID=America/Chicago:20260529T200000",
		"DTEND;TZID=America/Chicago:20260529T210000",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q\n---\n%s\n---", want, out)
		}
	}
	// Negative: should not emit TZID=Local or fall back to Z form.
	for _, bad := range []string{"TZID=Local", "DTSTART:20260530T010000Z"} {
		if strings.Contains(out, bad) {
			t.Errorf("output unexpectedly contains %q", bad)
		}
	}
}

func TestEnsureVTimezones_NoOpForUTC(t *testing.T) {
	start := time.Date(2026, 5, 30, 1, 0, 0, 0, time.UTC)
	end := time.Date(2026, 5, 30, 2, 0, 0, 0, time.UTC)
	cal := newVEvent("test-uid-utc", start, end, "UTC event", "", "")
	ensureVTimezones(cal.Component)
	for _, child := range cal.Children {
		if child.Name == ical.CompTimezone {
			t.Fatalf("UTC-only event should have no VTIMEZONE, got one")
		}
	}
}

func TestEnsureVTimezones_NoDuplicateForKnownTZ(t *testing.T) {
	chicago, _ := time.LoadLocation("America/Chicago")
	start := time.Date(2026, 5, 29, 20, 0, 0, 0, chicago)
	end := time.Date(2026, 5, 29, 21, 0, 0, 0, chicago)
	cal := newVEvent("u", start, end, "s", "", "")
	ensureVTimezones(cal.Component)
	ensureVTimezones(cal.Component) // idempotent
	count := 0
	for _, child := range cal.Children {
		if child.Name == ical.CompTimezone {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("expected exactly 1 VTIMEZONE, got %d", count)
	}
}
