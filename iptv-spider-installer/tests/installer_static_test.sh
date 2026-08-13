#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

bash -n "$ROOT/install.sh"
bash -n "$ROOT/uninstall.sh"
bash -n "$ROOT/install-oneclick.sh"

grep -q 'INSTALL_DIR="${WORK_DIR}/iptv-spider-installer"' "$ROOT/install-oneclick.sh"
grep -q 'if \[ ! -f "${INSTALL_DIR}/install.sh" \]' "$ROOT/install-oneclick.sh"
grep -q 'for mysql_account_host in localhost 127.0.0.1 %' "$ROOT/install.sh"
grep -q '检测到现有安装' "$ROOT/install.sh"
grep -q 'upgrade-backup' "$ROOT/install.sh"
grep -q 'iptv-spider-uninstall' "$ROOT/install.sh"
grep -q '"/tv.m3u"' "$ROOT/router/router.go"
grep -q '"/tv-direct.m3u"' "$ROOT/router/router.go"

test -x "$ROOT/install.sh"
test -x "$ROOT/uninstall.sh"
test -x "$ROOT/bin/iptv-spider-linux-amd64"
test -x "$ROOT/bin/stb-probe-linux-amd64"
test -f "$ROOT/assets/channel-reference.m3u"
test -f "$ROOT/assets/logos/CGTN.png"

echo 'installer static checks passed'
