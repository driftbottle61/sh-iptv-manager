#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

bash -n "$ROOT/install.sh"
bash -n "$ROOT/uninstall.sh"
bash -n "$ROOT/status.sh"
bash -n "$ROOT/manage.sh"
bash -n "$ROOT/install-oneclick.sh"

grep -q 'INSTALL_DIR="${WORK_DIR}/iptv-spider-installer"' "$ROOT/install-oneclick.sh"
grep -q 'if \[ ! -f "${INSTALL_DIR}/install.sh" \]' "$ROOT/install-oneclick.sh"
grep -q 'for mysql_account_host in localhost 127.0.0.1 %' "$ROOT/install.sh"
grep -q '检测到现有安装' "$ROOT/install.sh"
grep -q 'upgrade-backup' "$ROOT/install.sh"
grep -q 'iptv-spider-uninstall' "$ROOT/install.sh"
grep -q 'iptv-spider-status' "$ROOT/install.sh"
grep -q 'APP_DIR/manage.sh' "$ROOT/install.sh"
grep -q '手动抓取' "$ROOT/manage.sh"
grep -q '服务保持运行' "$ROOT/manage.sh"
grep -q '频道信息列表更新完成' "$ROOT/manage.sh"
grep -q '更新节目信息列表完成' "$ROOT/manage.sh"
grep -q 'tail -c' "$ROOT/manage.sh"
grep -q 'stat -Lc %s' "$ROOT/manage.sh"
grep -q 'default-character-set=utf8mb4' "$ROOT/status.sh"
grep -q 'LC_ALL=C.UTF-8' "$ROOT/status.sh"
grep -q '"/tv.m3u"' "$ROOT/router/router.go"
grep -q '"/tv-direct.m3u"' "$ROOT/router/router.go"

test -x "$ROOT/install.sh"
test -x "$ROOT/uninstall.sh"
test -x "$ROOT/status.sh"
test -x "$ROOT/manage.sh"
test -x "$ROOT/bin/iptv-spider-linux-amd64"
test -x "$ROOT/bin/stb-probe-linux-amd64"
test -f "$ROOT/assets/channel-reference.m3u"
test -f "$ROOT/assets/logos/CGTN.png"

echo 'installer static checks passed'
