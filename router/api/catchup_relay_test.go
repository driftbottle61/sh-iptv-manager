package api

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRelayHLSUnauthorizedIsRetryable(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "expired", http.StatusUnauthorized)
	}))
	defer server.Close()

	var output bytes.Buffer
	written, err := relayHLS(context.Background(), server.URL, &output)
	if err == nil {
		t.Fatal("expected an unauthorized error")
	}
	if written != 0 || output.Len() != 0 {
		t.Fatalf("unauthorized response wrote media: written=%d buffer=%d", written, output.Len())
	}
	if !retryableRelayError(err) {
		t.Fatalf("unauthorized response should be retryable: %v", err)
	}
}

func TestRelayHLSWritesMediaSegment(t *testing.T) {
	const media = "test MPEG-TS payload"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/segment.ts") {
			_, _ = w.Write([]byte(media))
			return
		}
		_, _ = w.Write([]byte("#EXTM3U\n#EXTINF:1,\nsegment.ts\n#EXT-X-ENDLIST\n"))
	}))
	defer server.Close()

	var output bytes.Buffer
	written, err := relayHLS(context.Background(), server.URL+"/index.m3u8", &output)
	if err != nil {
		t.Fatalf("relay failed: %v", err)
	}
	if written != int64(len(media)) || output.String() != media {
		t.Fatalf("unexpected media: written=%d output=%q", written, output.String())
	}
}
