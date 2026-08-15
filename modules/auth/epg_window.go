package auth

func epgDisplayTitle(name string, startTime, playableBoundary int64) string {
	if startTime < playableBoundary {
		return name + "【已过期】"
	}
	return name
}
