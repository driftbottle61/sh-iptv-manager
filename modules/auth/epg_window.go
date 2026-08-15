package auth

import "time"

var shanghaiTime = time.FixedZone("Asia/Shanghai", 8*60*60)

// epgHistoryBoundary returns midnight in Shanghai for the oldest EPG day.
func epgHistoryBoundary(now time.Time, daysAgo int) int64 {
	local := now.In(shanghaiTime)
	today := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, shanghaiTime)
	return today.AddDate(0, 0, -daysAgo).UnixMilli()
}
