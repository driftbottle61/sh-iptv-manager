package model

import "testing"

func TestChannelInfoNormalizesSportsChannelAlias(t *testing.T) {
	channel := ChannelInfo{Name: "体育频道HD"}
	channel.processData()

	if channel.CommName != "五星体育" {
		t.Fatalf("expected 五星体育, got %q", channel.CommName)
	}
	if !channel.IsHD {
		t.Fatal("expected sports channel alias to remain HD")
	}
}
