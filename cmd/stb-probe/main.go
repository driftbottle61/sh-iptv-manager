package main

import (
	"context"
	"flag"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

type field struct {
	name string
	re   *regexp.Regexp
}

func main() {
	iface := flag.String("interface", "eth1", "IPTV network interface")
	duration := flag.Duration("duration", 90*time.Second, "capture duration")
	flag.Parse()

	ctx, cancel := context.WithTimeout(context.Background(), *duration)
	defer cancel()
	// Authentication is plain HTTP on Shanghai Telecom IPTV deployments.
	cmd := exec.CommandContext(ctx, "tcpdump", "-i", *iface, "-nn", "-s", "0", "-A", "tcp and (port 80 or port 7001)")
	out, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		err = nil
	}
	if err != nil && len(out) == 0 {
		fmt.Printf("capture failed: %v\n", err)
		return
	}

	text := string(out)
	values := map[string]string{}
	for _, item := range []field{
		{"uid", regexp.MustCompile(`(?i)(?:UserID|userID)[=:\\"]+([^&\\"[:space:]]+)`)},
		{"sn", regexp.MustCompile(`(?i)(?:SN|sn)[=:\\"]+(000[34][0-9A-Za-z]{20})`)},
		{"mac", regexp.MustCompile(`(?i)(?:MAC|mac|MacAddr)[=:\\"]+([0-9A-F]{2}(?::|-)[0-9A-F]{2}(?::|-)[0-9A-F]{2}(?::|-)[0-9A-F]{2}(?::|-)[0-9A-F]{2}(?::|-)[0-9A-F]{2})`)},
		{"type", regexp.MustCompile(`(?i)(?:STBType|Model|stbType)[=:\\"]+([A-Za-z0-9._-]+)`)},
	} {
		if match := item.re.FindStringSubmatch(text); len(match) == 2 {
			values[item.name] = strings.ReplaceAll(match[1], "-", ":")
		}
	}
	// tcpdump's connection header exposes the private STB source and auth host.
	flow := regexp.MustCompile(`IP ([0-9.]+)\\.[0-9]+ > ([0-9.]+)\\.(7001|80)`).FindStringSubmatch(text)
	if len(flow) == 4 {
		values["ip"] = flow[1]
		values["auth_host"] = flow[2] + ":" + flow[3]
	}
	if values["type"] == "" {
		values["type"] = "B860A" // Project default; verify against the captured User-Agent if absent.
	}

	fmt.Println("stb:")
	for _, key := range []string{"uid", "mac", "sn", "ip", "type", "auth_host"} {
		fmt.Printf("  %s: %q\n", key, values[key])
	}
	missing := []string{}
	for _, key := range []string{"uid", "mac", "sn", "ip", "auth_host"} {
		if values[key] == "" {
			missing = append(missing, key)
		}
	}
	if len(missing) > 0 {
		fmt.Printf("# Missing: %s. Reboot the STB and run again.\n", strings.Join(missing, ", "))
	}
}
