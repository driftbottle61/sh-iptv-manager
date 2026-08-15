package api

import (
	"testing"
	"time"
)

func TestCatchupWindowUsesProgrammeEnd(t *testing.T) {
	now := time.Date(2026, 8, 15, 1, 0, 0, 0, time.UTC)
	start := now.AddDate(0, 0, -catchupMaxDays).Add(-10 * time.Minute)

	if err := validateCatchupWindow(start, 15*time.Minute, now); err != nil {
		t.Fatalf("programme ending inside the window was rejected: %v", err)
	}
	if err := validateCatchupWindow(start, 5*time.Minute, now); err == nil {
		t.Fatal("programme ending before the window was accepted")
	}
}

func TestCatchupWindowRejectsFutureStart(t *testing.T) {
	now := time.Date(2026, 8, 15, 1, 0, 0, 0, time.UTC)
	if err := validateCatchupWindow(now.Add(6*time.Minute), time.Hour, now); err == nil {
		t.Fatal("future programme was accepted")
	}
}
