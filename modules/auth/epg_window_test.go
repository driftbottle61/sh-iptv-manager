package auth

import (
	"testing"
	"time"
)

func TestEPGHistoryBoundaryUsesShanghaiMidnight(t *testing.T) {
	now := time.Date(2026, 8, 15, 2, 7, 0, 0, time.UTC)
	got := epgHistoryBoundary(now, 7)
	want := time.Date(2026, 8, 8, 0, 0, 0, 0, shanghaiTime).UnixMilli()
	if got != want {
		t.Fatalf("boundary=%d (%s), want=%d (%s)", got, time.UnixMilli(got), want, time.UnixMilli(want))
	}
}
