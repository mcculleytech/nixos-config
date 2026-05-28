package main

import (
	"strings"
	"testing"
	"time"
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
