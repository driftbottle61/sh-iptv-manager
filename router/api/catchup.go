package api

import (
	"bufio"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/textproto"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/kataras/iris/v12"
	"iptv-spider-sh/global"
	"iptv-spider-sh/model"
	"iptv-spider-sh/modules/auth"
)

const (
	catchupMaxDays     = 7
	catchupMaxDuration = 8 * time.Hour
	catchupUserAgent   = "IPTVSpiderCatchup/1.0"
	tiviMateSourceURL  = "http://192.168.100.51:34400/m3u/xteve.m3u"
)

var tvgIDPattern = regexp.MustCompile(`tvg-id="([^"]+)"`)
var tvgNamePattern = regexp.MustCompile(`tvg-name="([^"]+)"`)

type rtspResponse struct {
	status  int
	headers textproto.MIMEHeader
	body    []byte
}

type rtspClient struct {
	conn net.Conn
	read *bufio.Reader
	cseq int
	session string
}

func generateCatchupM3u(ctx iris.Context) {
	generateCatchupM3uWithDefaults(ctx, "", catchupMaxDays)
}

func GenerateTiviMateM3u(ctx iris.Context) {
	generateCatchupM3uWithDefaults(ctx, tiviMateSourceURL, 5)
}

func generateCatchupM3uWithDefaults(ctx iris.Context, defaultSource string, defaultDays int) {
	playlist, err := loadSourcePlaylist(ctx, defaultSource)
	if err != nil {
		stopRequest(ctx, iris.StatusBadGateway, err)
		return
	}

	var channelInfos []model.ChannelInfo
	if err := global.DB.Find(&channelInfos).Error; err != nil {
		stopRequest(ctx, iris.StatusInternalServerError, err)
		return
	}
	enabled := make(map[string]bool)
	channelsByName := make(map[string]string)
	for _, info := range model.RemoveDuplicateChannelInfo(channelInfos) {
		if !info.IsShow {
			continue
		}
		var channel model.Channel
		result := global.DB.Where("user_channel_id = ? AND time_shift = ? AND time_shift_url <> ?", info.MixNo, "1", "").Order("updated_at DESC").First(&channel)
		if result.Error != nil {
			continue
		}
		enabled[info.MixNo] = true
		channelsByName[normalizeChannelName(info.Name)] = info.MixNo
		channelsByName[normalizeChannelName(info.CommName)] = info.MixNo
	}

	days := defaultDays
	if value, err := strconv.Atoi(ctx.URLParamDefault("days", strconv.Itoa(defaultDays))); err == nil && value >= 1 && value <= catchupMaxDays {
		days = value
	}
	scheme := ctx.GetHeader("X-Forwarded-Proto")
	if scheme == "" {
		scheme = "http"
	}
	baseURL := fmt.Sprintf("%s://%s/api/catchup/stream", scheme, ctx.Request().Host)
	result := injectCatchupAttributes(string(playlist), enabled, channelsByName, baseURL, days)

	ctx.Header("Content-Disposition", "attachment; filename=iptv-catchup.m3u")
	ctx.ContentType("audio/x-mpegurl")
	_, _ = ctx.WriteString(result)
}

func loadSourcePlaylist(ctx iris.Context, defaultSource string) ([]byte, error) {
	source := strings.TrimSpace(ctx.URLParam("source"))
	if source == "" {
		source = defaultSource
	}
	if source == "" {
		return auth.GenerateM3u8("", "", "true", ""), nil
	}
	parsed, err := url.Parse(source)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return nil, errors.New("source must be an HTTP or HTTPS URL")
	}
	request, err := http.NewRequestWithContext(ctx.Request().Context(), http.MethodGet, source, nil)
	if err != nil {
		return nil, err
	}
	client := &http.Client{Timeout: 20 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("load source playlist: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("source playlist returned %s", response.Status)
	}
	return io.ReadAll(io.LimitReader(response.Body, 16<<20))
}

func injectCatchupAttributes(playlist string, enabled map[string]bool, channelsByName map[string]string, baseURL string, days int) string {
	lines := strings.Split(strings.ReplaceAll(playlist, "\r\n", "\n"), "\n")
	for index, line := range lines {
		if !strings.HasPrefix(line, "#EXTINF:") || strings.Contains(line, "catchup=") {
			continue
		}
		channelID := ""
		if match := tvgIDPattern.FindStringSubmatch(line); len(match) == 2 && enabled[match[1]] {
			channelID = match[1]
		}
		if channelID == "" {
			if match := tvgNamePattern.FindStringSubmatch(line); len(match) == 2 {
				channelID = channelsByName[normalizeChannelName(match[1])]
			}
		}
		if channelID == "" {
			comma := strings.LastIndex(line, ",")
			if comma >= 0 {
				channelID = channelsByName[normalizeChannelName(line[comma+1:])]
			}
		}
		if channelID == "" {
			continue
		}
		comma := strings.LastIndex(line, ",")
		if comma < 0 {
			continue
		}
		streamURL := fmt.Sprintf("%s/%s/{utc}/{duration}.ts", baseURL, url.PathEscape(channelID))
		attributes := fmt.Sprintf(` catchup="default" catchup-days="%d" catchup-source="%s"`, days, streamURL)
		lines[index] = line[:comma] + attributes + line[comma:]
	}
	return strings.Join(lines, "\n")
}

func normalizeChannelName(name string) string {
	name = strings.ToUpper(strings.TrimSpace(name))
	name = strings.ReplaceAll(name, "(高清)", "")
	name = strings.ReplaceAll(name, "（高清）", "")
	name = strings.TrimSpace(name)
	if strings.HasSuffix(name, "HD") {
		name = strings.TrimSpace(strings.TrimSuffix(name, "HD"))
	}
	if strings.HasSuffix(name, "4K") {
		name = strings.TrimSpace(strings.TrimSuffix(name, "4K"))
	}
	return strings.ReplaceAll(name, " ", "")
}

func streamCatchup(ctx iris.Context) {
	channelID := ctx.Params().Get("channel")
	start, duration, err := parseCatchupRange(ctx)
	if err != nil {
		stopRequest(ctx, iris.StatusBadRequest, err)
		return
	}
	global.LOG.Info(fmt.Sprintf("catchup request channel=%s start=%s duration=%s remote=%s", channelID, start.Format(time.RFC3339), duration, ctx.RemoteAddr()))

	playURL, err := getTvodPlayURL(ctx.Request().Context(), channelID, start, duration)
	if err != nil {
		stopRequest(ctx, iris.StatusNotFound, errors.New("catchup channel not found"))
		return
	}
	ctx.Redirect(playURL, iris.StatusFound)
}

func getTvodPlayURL(ctx context.Context, mixNo string, start time.Time, duration time.Duration) (string, error) {
	var info model.ChannelInfo
	if err := global.DB.Where("mix_no = ?", mixNo).First(&info).Error; err != nil { return "", err }
	var program model.EPGDetails
	ms := start.UnixMilli()
	if err := global.DB.Where("comm_name = ? AND start_time <= ? AND end_time > ?", info.CommName, ms, ms).Order("start_time DESC").First(&program).Error; err != nil { return "", err }
	var authInfo model.AuthInfo
	if err := global.DB.Order("updated_at DESC").First(&authInfo).Error; err != nil { return "", err }
	endpoint := strings.TrimRight(authInfo.EPGHostUrl, "/") + "/function/ajax/epg7getChannelByAjax.jsp"
	endTime := program.EndTime / 1000
	// The current EPG item has a future end time. Ask TVOD only for the part
	// that has already aired; submitting a future end makes the provider reject
	// the request even though historical programmes work normally.
	nowSeconds := time.Now().Unix()
	if endTime > nowSeconds {
		endTime = nowSeconds
	}
	form := url.Values{"action":{"getTvodPlayUrl"}, "channelID":{info.ChID}, "playbillID":{program.ID}, "startTime":{strconv.FormatInt(program.StartTime/1000,10)}, "endTime":{strconv.FormatInt(endTime,10)}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode())); if err != nil { return "", err }
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.AddCookie(&http.Cookie{Name:"JSESSIONID", Value:authInfo.JSESSIONID})
	resp, err := (&http.Client{Timeout:15*time.Second}).Do(req); if err != nil { return "", err }; defer resp.Body.Close()
	var out struct { Status string `json:"status"`; Data struct { PlayURL string `json:"playURL"` } `json:"data"` }
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&out); err != nil { return "", err }
	if out.Status != "1" || out.Data.PlayURL == "" { return "", errors.New("TVOD URL not issued") }
	return out.Data.PlayURL, nil
}

func stopRequest(ctx iris.Context, status int, err error) {
	ctx.StatusCode(status)
	if err != nil {
		if global.LOG != nil {
			global.LOG.Warn(fmt.Sprintf("catchup request rejected status=%d path=%s error=%s", status, ctx.Path(), err.Error()))
		}
		_, _ = ctx.WriteString(err.Error())
	}
	ctx.StopExecution()
}

func parseCatchupRange(ctx iris.Context) (time.Time, time.Duration, error) {
	rawStart := ctx.URLParam("start")
	if rawStart == "" {
		rawStart = ctx.Params().Get("start")
	}
	if rawStart == "" {
		rawStart = ctx.URLParam("utc")
	}
	if rawStart == "" {
		rawStart = ctx.URLParam("lutc")
	}
	seconds, err := strconv.ParseInt(rawStart, 10, 64)
	if err != nil {
		return time.Time{}, 0, errors.New("start must be a Unix timestamp")
	}
	if seconds > 1_000_000_000_000 {
		seconds /= 1000
	}
	start := time.Unix(seconds, 0).UTC()
	now := time.Now().UTC()
	if start.Before(now.AddDate(0, 0, -catchupMaxDays)) || start.After(now.Add(5*time.Minute)) {
		return time.Time{}, 0, errors.New("start is outside the seven-day catchup window")
	}

	rawDuration := ctx.URLParam("duration")
	if rawDuration == "" {
		rawDuration = ctx.Params().Get("duration")
	}
	if rawDuration == "" {
		rawDuration = "3600"
	}
	rawDuration = strings.TrimSuffix(rawDuration, ".ts")
	durationSeconds, err := strconv.ParseInt(rawDuration, 10, 64)
	var duration time.Duration
	if err == nil {
		duration = time.Duration(durationSeconds) * time.Second
	} else if parsed, parseErr := time.ParseDuration(rawDuration); parseErr == nil {
		duration = parsed
	} else {
		return time.Time{}, 0, errors.New("duration must be seconds or a Go duration")
	}
	if duration <= 0 {
		return time.Time{}, 0, errors.New("duration must be positive")
	}
	if duration > catchupMaxDuration {
		return time.Time{}, 0, errors.New("duration exceeds eight hours")
	}
	return start, duration, nil
}

func openCatchupSession(ctx context.Context, source string, start time.Time, duration time.Duration) (*rtspClient, error) {
	target, err := resolveRTSP(ctx, source, start, duration)
	if err != nil {
		return nil, err
	}
	client, err := dialRTSP(ctx, target)
	if err != nil {
		return nil, err
	}
	setup, err := client.request("SETUP", target, map[string]string{
		"Transport": "RTP/AVP/TCP;unicast;interleaved=0-1",
	})
	if err != nil {
		client.close()
		return nil, fmt.Errorf("RTSP SETUP failed: %w", err)
	}
	if setup.status != 200 {
		client.close()
		return nil, fmt.Errorf("RTSP SETUP returned status %d", setup.status)
	}
	session := strings.Split(setup.headers.Get("Session"), ";")[0]
	if session == "" {
		client.close()
		return nil, errors.New("RTSP SETUP did not return a session")
	}
	client.session = session
	end := start.Add(duration)
	play, err := client.request("PLAY", target, map[string]string{
		"Session": session,
		"Range":   "clock=" + start.Format("20060102T150405Z") + "-" + end.Format("20060102T150405Z"),
	})
	if err != nil {
		client.close()
		return nil, fmt.Errorf("RTSP PLAY failed: %w", err)
	}
	if play.status != 200 {
		client.close()
		return nil, fmt.Errorf("RTSP PLAY returned status %d", play.status)
	}
	return client, nil
}

func resolveRTSP(ctx context.Context, source string, start time.Time, duration time.Duration) (string, error) {
	target, err := setTimeShiftDuration(source, start, duration)
	if err != nil {
		return "", err
	}
	for redirects := 0; redirects < 8; redirects++ {
		client, err := dialRTSP(ctx, target)
		if err != nil {
			return "", err
		}
		response, err := client.request("DESCRIBE", target, map[string]string{"Accept": "application/sdp"})
		client.close()
		if err != nil {
			return "", err
		}
		if response.status == 200 {
			return target, nil
		}
		if response.status != 301 && response.status != 302 && response.status != 307 && response.status != 308 {
			return "", fmt.Errorf("RTSP DESCRIBE returned status %d", response.status)
		}
		location := response.headers.Get("Location")
		if location == "" {
			return "", errors.New("RTSP redirect did not include Location")
		}
		target, err = setTimeShiftDuration(location, start, duration)
		if err != nil {
			return "", err
		}
	}
	return "", errors.New("too many RTSP redirects")
}

func setTimeShiftDuration(target string, start time.Time, duration time.Duration) (string, error) {
	parsed, err := url.Parse(target)
	if err != nil {
		return "", fmt.Errorf("parse RTSP redirect: %w", err)
	}
	query := parsed.Query()
	end := start.Add(duration)
	query.Set("DURATION", start.Format("20060102T150405Z")+"-"+end.Format("20060102T150405Z"))
	parsed.RawQuery = query.Encode()
	return parsed.String(), nil
}

func dialRTSP(ctx context.Context, target string) (*rtspClient, error) {
	parsed, err := url.Parse(target)
	if err != nil || parsed.Scheme != "rtsp" || parsed.Hostname() == "" {
		return nil, errors.New("invalid RTSP URL")
	}
	port := parsed.Port()
	if port == "" {
		port = "554"
	}
	dialer := net.Dialer{Timeout: 8 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(parsed.Hostname(), port))
	if err != nil {
		return nil, err
	}
	return &rtspClient{conn: conn, read: bufio.NewReader(conn)}, nil
}

func (client *rtspClient) request(method, target string, headers map[string]string) (*rtspResponse, error) {
	client.cseq++
	_ = client.conn.SetDeadline(time.Now().Add(12 * time.Second))
	if _, err := fmt.Fprintf(client.conn, "%s %s RTSP/1.0\r\nCSeq: %d\r\nUser-Agent: %s\r\n", method, target, client.cseq, catchupUserAgent); err != nil {
		return nil, err
	}
	for key, value := range headers {
		if _, err := fmt.Fprintf(client.conn, "%s: %s\r\n", key, value); err != nil {
			return nil, err
		}
	}
	if _, err := io.WriteString(client.conn, "\r\n"); err != nil {
		return nil, err
	}

	statusLine, err := client.read.ReadString('\n')
	if err != nil {
		return nil, err
	}
	parts := strings.Fields(statusLine)
	if len(parts) < 2 {
		return nil, errors.New("invalid RTSP status line")
	}
	status, err := strconv.Atoi(parts[1])
	if err != nil {
		return nil, err
	}
	mimeHeaders, err := textproto.NewReader(client.read).ReadMIMEHeader()
	if err != nil {
		return nil, err
	}
	response := &rtspResponse{status: status, headers: mimeHeaders}
	if length, _ := strconv.Atoi(mimeHeaders.Get("Content-Length")); length > 0 {
		response.body = make([]byte, length)
		if _, err := io.ReadFull(client.read, response.body); err != nil {
			return nil, err
		}
	}
	_ = client.conn.SetDeadline(time.Time{})
	return response, nil
}

func (client *rtspClient) stream(ctx context.Context, writer io.Writer) error {
	flusher, _ := writer.(interface{ Flush() })
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		_ = client.conn.SetReadDeadline(time.Now().Add(15 * time.Second))
		marker, err := client.read.ReadByte()
		if err != nil {
			return err
		}
		if marker != '$' {
			if _, err := client.read.ReadString('\n'); err != nil {
				return err
			}
			continue
		}
		channel, err := client.read.ReadByte()
		if err != nil {
			return err
		}
		lengthBytes := make([]byte, 2)
		if _, err := io.ReadFull(client.read, lengthBytes); err != nil {
			return err
		}
		packet := make([]byte, int(binary.BigEndian.Uint16(lengthBytes)))
		if _, err := io.ReadFull(client.read, packet); err != nil {
			return err
		}
		if channel%2 != 0 {
			continue
		}
		payload, err := rtpPayload(packet)
		if err != nil {
			continue
		}
		if _, err := writer.Write(payload); err != nil {
			return err
		}
		if flusher != nil {
			flusher.Flush()
		}
	}
}

func rtpPayload(packet []byte) ([]byte, error) {
	if len(packet) < 12 || packet[0]>>6 != 2 {
		return nil, errors.New("invalid RTP packet")
	}
	offset := 12 + int(packet[0]&0x0f)*4
	if len(packet) < offset {
		return nil, errors.New("short RTP CSRC header")
	}
	if packet[0]&0x10 != 0 {
		if len(packet) < offset+4 {
			return nil, errors.New("short RTP extension")
		}
		extensionLength := int(binary.BigEndian.Uint16(packet[offset+2:offset+4])) * 4
		offset += 4 + extensionLength
	}
	end := len(packet)
	if packet[0]&0x20 != 0 {
		padding := int(packet[len(packet)-1])
		end -= padding
	}
	if offset >= end {
		return nil, errors.New("empty RTP payload")
	}
	return packet[offset:end], nil
}

func (client *rtspClient) close() {
	if client == nil || client.conn == nil {
		return
	}
	if client.session != "" {
		_, _ = client.request("TEARDOWN", "*", map[string]string{"Session": client.session})
	}
	_ = client.conn.Close()
}
