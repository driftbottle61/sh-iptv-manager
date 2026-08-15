package api

import (
	"testing"
	"time"
)

func TestCatchupStartAllowsPastEPGProgramme(t *testing.T) {
	now := time.Date(2026, 8, 15, 1, 0, 0, 0, time.UTC)
	if err := validateCatchupStart(now.AddDate(0, 0, -30), now); err != nil {
		t.Fatalf("past EPG programme was rejected: %v", err)
	}
}

func TestCatchupStartRejectsFutureStart(t *testing.T) {
	now := time.Date(2026, 8, 15, 1, 0, 0, 0, time.UTC)
	if err := validateCatchupStart(now.Add(6*time.Minute), now); err == nil {
		t.Fatal("future programme was accepted")
	}
}
