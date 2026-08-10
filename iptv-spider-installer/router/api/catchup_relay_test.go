package api

import (
	"net"
	"testing"
)

func TestIsPrivateClient(t *testing.T) {
	tests := map[string]bool{
		"192.168.100.50": true,
		"192.168.88.1":   true,
		"10.0.0.1":       true,
		"172.16.0.1":     true,
		"127.0.0.1":      true,
		"8.8.8.8":        false,
		"1.1.1.1":        false,
	}
	for address, expected := range tests {
		if actual := isPrivateClient(net.ParseIP(address)); actual != expected {
			t.Fatalf("isPrivateClient(%s) = %v, want %v", address, actual, expected)
		}
	}
	if isPrivateClient(nil) {
		t.Fatal("isPrivateClient(nil) = true, want false")
	}
}
