package auth

import (
	"testing"
	"time"
)

func TestEPGHistoryBoundaryUsesShanghaiCalendarDay(t *testing.T) {
	now := time.Date(2026, 8, 15, 3, 30, 0, 0, time.UTC)
	want := time.Date(2026, 8, 8, 0, 0, 0, 0, shanghaiTime).UnixMilli()
	if got := epgHistoryBoundary(now, 7); got != want {
		t.Fatalf("epgHistoryBoundary() = %d, want %d", got, want)
	}
}

func TestEPGDisplayTitleMarksExpiredProgramme(t *testing.T) {
	boundary := int64(1000)
	if got := epgDisplayTitle("节目", 999, boundary); got != "节目【已过期】" {
		t.Fatalf("expired title = %q", got)
	}
	if got := epgDisplayTitle("节目", 1000, boundary); got != "节目" {
		t.Fatalf("playable title = %q", got)
	}
}
