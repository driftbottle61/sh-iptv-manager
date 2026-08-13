package auth

import "testing"

func TestValidateEpgAuthInfo(t *testing.T) {
	tests := []struct {
		name    string
		info    map[string]string
		wantErr bool
	}{
		{
			name: "complete",
			info: map[string]string{
				"SessionID": "session",
				"IpPort":    "218.83.188.231:8084",
				"framecode": "frame1002",
			},
		},
		{
			name:    "missing session",
			info:    map[string]string{"IpPort": "218.83.188.231:8084", "framecode": "frame1002"},
			wantErr: true,
		},
		{
			name:    "missing host",
			info:    map[string]string{"SessionID": "session", "framecode": "frame1002"},
			wantErr: true,
		},
		{
			name:    "missing frame",
			info:    map[string]string{"SessionID": "session", "IpPort": "218.83.188.231:8084"},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, _, _, err := validateEpgAuthInfo(tt.info)
			if (err != nil) != tt.wantErr {
				t.Fatalf("validateEpgAuthInfo() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
