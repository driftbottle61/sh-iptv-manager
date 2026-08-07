#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_DIR=/opt/sh-iptv-spider

ask() {
  local prompt=$1 default=${2-} value
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " value
    printf '%s' "${value:-$default}"
  else
    read -r -p "$prompt: " value
    printf '%s' "$value"
  fi
}

ask_secret() {
  local prompt=$1 value
  read -r -s -p "$prompt: " value
  printf '\n' >&2
  printf '%s' "$value"
}

yaml_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

require_value() {
  if [ -z "$2" ]; then
    echo "$1 cannot be empty."
    exit 1
  fi
}

echo 'Shanghai Telecom IPTV Spider installer'
echo 'The generated config contains IPTV credentials and is never uploaded by this installer.'

APP_DIR=$(ask 'Install directory' "$DEFAULT_DIR")
PORT=$(ask 'Service port' '8888')
LAN_IP=$(ask 'Server LAN IP for EPG and logo URLs')
require_value 'Server LAN IP' "$LAN_IP"

echo
echo 'Crawler / STB configuration'
STB_UID=$(ask 'IPTV account UID')
STB_MAC=$(ask 'STB MAC address')
STB_SN=$(ask 'STB serial number')
STB_IP=$(ask 'STB IPTV-network IP')
STB_TYPE=$(ask 'STB model')
AUTH_HOST=$(ask 'IPTV authentication host' '222.68.208.73:7001')
require_value 'IPTV account UID' "$STB_UID"
require_value 'STB MAC address' "$STB_MAC"
require_value 'STB serial number' "$STB_SN"
require_value 'STB IPTV-network IP' "$STB_IP"

echo
echo 'Catch-up and live-list configuration'
SOURCE_M3U=$(ask 'Existing live M3U source URL (optional)')
UDPXY=$(ask 'udpxy/msd_lite address for direct playlist (optional, host:port)')
CATCHUP_DAYS=$(ask 'Catch-up days' '5')
RELAY_CLIENTS=$(ask 'Relay client IPs, comma-separated (optional)')

echo
echo 'MySQL / MariaDB configuration'
MYSQL_HOST=$(ask 'MySQL host' '127.0.0.1')
MYSQL_DB=$(ask 'Database name' 'iptv')
MYSQL_USER=$(ask 'Database user' 'iptv')
MYSQL_PASSWORD=$(ask_secret 'Database password')
require_value 'Database password' "$MYSQL_PASSWORD"

if [ -d "$APP_DIR" ] && [ -f "$APP_DIR/config.yaml" ]; then
  echo "$APP_DIR already contains config.yaml; installation stopped to protect it."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl mariadb-client mariadb-server

if [ "$MYSQL_HOST" = '127.0.0.1' ] || [ "$MYSQL_HOST" = 'localhost' ]; then
  mariadb -e "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  mariadb -e "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'127.0.0.1' IDENTIFIED BY '$MYSQL_PASSWORD';"
  mariadb -e "ALTER USER '$MYSQL_USER'@'127.0.0.1' IDENTIFIED BY '$MYSQL_PASSWORD';"
  mariadb -e "GRANT ALL PRIVILEGES ON \`$MYSQL_DB\`.* TO '$MYSQL_USER'@'127.0.0.1'; FLUSH PRIVILEGES;"
fi

install -d -m 0755 "$APP_DIR"
tar -C "$SCRIPT_DIR" --exclude='./config.yaml' --exclude='./.git' -cf - . | tar -C "$APP_DIR" -xf -

if [ -x "$APP_DIR/bin/iptv-spider-linux-amd64" ] && [ "$(uname -m)" = 'x86_64' ]; then
  install -m 0755 "$APP_DIR/bin/iptv-spider-linux-amd64" "$APP_DIR/iptv-spider"
elif command -v go >/dev/null 2>&1; then
  (cd "$APP_DIR" && go build -o iptv-spider .)
else
  echo 'No compatible bundled binary and Go is not installed.'
  exit 1
fi

relay_yaml='[]'
if [ -n "$RELAY_CLIENTS" ]; then
  relay_yaml='['
  IFS=',' read -r -a relay_items <<< "$RELAY_CLIENTS"
  for relay in "${relay_items[@]}"; do
    relay=$(printf '%s' "$relay" | xargs)
    [ -n "$relay" ] && relay_yaml+="'$(yaml_escape "$relay")',"
  done
  relay_yaml=${relay_yaml%,}']'
fi

{
  printf "system:\n  env: 'release'\n  addr: '0.0.0.0:%s'\n  db-type: 'mysql'\n  oss-type: ''\n\n" "$PORT"
  printf "stb:\n  uid: '%s'\n  mac: '%s'\n  sn: '%s'\n  ip: '%s'\n  type: '%s'\n  auth_host: '%s'\n\n" \
    "$(yaml_escape "$STB_UID")" "$(yaml_escape "$STB_MAC")" "$(yaml_escape "$STB_SN")" \
    "$(yaml_escape "$STB_IP")" "$(yaml_escape "$STB_TYPE")" "$(yaml_escape "$AUTH_HOST")"
  printf "epg:\n  generator: 'sh-iptv-spider'\n  source: 'Shanghai Telecom IPTV'\n  xml_url: 'http://%s:%s/api/epg?daysAgo=%s'\n  fetch_cron: '0 0 8,16,23 * * *'\n\n" "$LAN_IP" "$PORT" "$CATCHUP_DAYS"
  printf "catchup:\n  source_m3u: '%s'\n  udpxy: '%s'\n  days: %s\n  relay_clients: %s\n\n" \
    "$(yaml_escape "$SOURCE_M3U")" "$(yaml_escape "$UDPXY")" "$CATCHUP_DAYS" "$relay_yaml"
  printf "mysql:\n  path: '%s'\n  config: 'parseTime=True&charset=utf8mb4'\n  db-name: '%s'\n  username: '%s'\n  password: '%s'\n  max-idle-conns: 10\n  max-open-conns: 50\n  log-mode: 'error'\n  log-zap: false\n\n" \
    "$(yaml_escape "$MYSQL_HOST")" "$(yaml_escape "$MYSQL_DB")" "$(yaml_escape "$MYSQL_USER")" "$(yaml_escape "$MYSQL_PASSWORD")"
  printf "cache:\n  type: 'memory'\n  prefix: 'iptv'\n  memory_interval: 60\n  default_timeout: 10\n\n"
  printf "redis:\n  db: 0\n  addr: '127.0.0.1:6379'\n  password: ''\n\n"
  printf "oss:\n  enable: false\n  upload_cron: ''\n  endpoint: ''\n  use-ssl: true\n  bucket: ''\n  access-key: ''\n  secret-key: ''\n\n"
  printf "zap:\n  level: 'info'\n  format: 'console'\n  prefix: '[sh-iptv-spider]'\n  director: 'log'\n  link-name: 'latest_log'\n  show-line: false\n  encode-level: 'LowercaseLevelEncoder'\n  stacktrace-key: 'stacktrace'\n  log-in-console: false\n"
} > "$APP_DIR/config.yaml"
chmod 600 "$APP_DIR/config.yaml"

sed "s|__INSTALL_DIR__|$APP_DIR|g" "$APP_DIR/systemd/iptv-spider.service" > /etc/systemd/system/iptv-spider.service
systemctl daemon-reload
systemctl enable --now iptv-spider

echo
echo 'Installation complete.'
echo "M3U: http://$LAN_IP:$PORT/tv-direct.m3u"
echo "EPG: http://$LAN_IP:$PORT/api/epg?daysAgo=$CATCHUP_DAYS"
echo "Logos: http://$LAN_IP:$PORT/iptvlogos/CGTN.png"
