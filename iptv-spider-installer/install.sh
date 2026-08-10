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

yaml_value() {
  local key=$1 file=$2
  sed -n "s/^[[:space:]]*${key}:[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$file" | tail -n 1
}

collect_stb_manual() {
  STB_UID=$(ask 'IPTV account UID')
  STB_MAC=$(ask 'STB MAC address')
  STB_SN=$(ask 'STB serial number')
  STB_TYPE=$(ask 'STB model')
  AUTH_HOST=$(ask 'IPTV authentication host' '222.68.208.73:7001')
  STB_PLANE_A_IP=$(ask 'STB plane-A/LAN IP (optional)')
  STB_IP=$(ask 'STB plane-B IPTV-network IP')
  STB_PLANE_B_GATEWAY=$(ask 'STB plane-B gateway (optional)')
}

collect_stb_capture() {
  local probe output capture_ok answer
  probe="$SCRIPT_DIR/bin/stb-probe-linux-amd64"
  if [ "$(uname -m)" != 'x86_64' ] || [ ! -x "$probe" ]; then
    echo 'This installer does not contain a compatible stb-probe binary for this CPU.'
    echo 'Choose manual entry or use an amd64 Debian/Ubuntu host for capture.'
    return 1
  fi
  if ! command -v ssh >/dev/null 2>&1 || ! command -v scp >/dev/null 2>&1; then
    echo 'Installing the SSH client required by the capture module...'
    apt-get update
    apt-get install -y --no-install-recommends openssh-client ca-certificates
  fi

  ROUTER_HOST=$(ask 'RouterOS address' '192.168.100.1')
  ROUTER_PORT=$(ask 'RouterOS SSH port' '1314')
  ROUTER_USER=$(ask 'RouterOS SSH user' 'david_ni')
  ROUTER_KEY=$(ask 'SSH private key path' '/root/.ssh/id_ed25519_sbx_github')
  ROUTER_IFACE=$(ask 'Physical RouterOS port connected to the STB' 'ether3_lan')
  CAPTURE_SECONDS=$(ask 'Capture duration in seconds' '120')
  require_value 'RouterOS address' "$ROUTER_HOST"
  require_value 'RouterOS SSH user' "$ROUTER_USER"
  require_value 'SSH private key path' "$ROUTER_KEY"
  require_value 'RouterOS interface' "$ROUTER_IFACE"
  if [ ! -r "$ROUTER_KEY" ]; then
    echo "SSH private key is not readable: $ROUTER_KEY"
    return 1
  fi

  while :; do
    echo
    echo 'The capture will run on the RouterOS physical IPTV port.'
    echo 'After you press Enter and the capture-start message appears, immediately power-cycle the physical STB.'
    echo 'Wait until the STB reaches its home screen. Do not interrupt this installer during capture.'
    read -r -p 'Press Enter when you are beside the STB and ready to reboot it... ' answer
    output=$(mktemp /tmp/stb-probe-result.XXXXXX)
    capture_ok=0
    echo
    echo 'Capture has started. Reboot the physical STB now.'
    "$probe" \
      -router "$ROUTER_HOST" -router-port "$ROUTER_PORT" \
      -router-user "$ROUTER_USER" -router-key "$ROUTER_KEY" \
      -interface "$ROUTER_IFACE" -duration "$CAPTURE_SECONDS" >"$output" 2>&1 || capture_ok=$?

    echo
    echo 'Detected STB data:'
    echo '------------------------------------------------------------'
    cat "$output"
    echo '------------------------------------------------------------'
    if [ "$capture_ok" -eq 0 ]; then
      STB_UID=$(yaml_value uid "$output")
      STB_MAC=$(yaml_value mac "$output")
      STB_SN=$(yaml_value sn "$output")
      STB_TYPE=$(yaml_value type "$output")
      AUTH_HOST=$(yaml_value auth_host "$output")
      STB_PLANE_A_IP=$(yaml_value plane_a_ip "$output")
      STB_IP=$(yaml_value plane_b_ip "$output")
      STB_PLANE_B_GATEWAY=$(yaml_value plane_b_gateway "$output")
    fi
    rm -f "$output"

    if [ "$capture_ok" -eq 0 ] && [ -n "$STB_UID" ] && [ -n "$STB_MAC" ] && [ -n "$STB_SN" ] && [ -n "$STB_IP" ] && [ -n "$AUTH_HOST" ]; then
      echo 'Capture is complete. These values will be written to config.yaml automatically.'
      return 0
    fi
    echo 'The capture did not contain all required authentication fields.'
    answer=$(ask 'Enter R to retry capture or M for manual entry' 'R')
    case "$answer" in
      [Mm]*) return 1 ;;
    esac
  done
}

echo 'Shanghai Telecom IPTV Spider installer'
echo 'The generated config contains IPTV credentials and is never uploaded by this installer.'

APP_DIR=$(ask 'Install directory' "$DEFAULT_DIR")
PORT=$(ask 'Service port' '8888')
LAN_IP=$(ask 'Server LAN IP for EPG and logo URLs')
require_value 'Server LAN IP' "$LAN_IP"

echo
echo 'Crawler / STB configuration'
echo '  1) Enter STB information manually'
echo '  2) Capture STB authentication through RouterOS'
STB_MODE=$(ask 'Select STB setup mode' '2')
case "$STB_MODE" in
  2|[Cc]*) collect_stb_capture || collect_stb_manual ;;
  *) collect_stb_manual ;;
esac
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
apt-get install -y --no-install-recommends ca-certificates curl openssh-client mariadb-client mariadb-server

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
  printf "stb:\n  uid: '%s'\n  mac: '%s'\n  sn: '%s'\n  ip: '%s'\n  type: '%s'\n  auth_host: '%s'\n  plane_a_ip: '%s'\n  plane_b_gateway: '%s'\n\n" \
    "$(yaml_escape "$STB_UID")" "$(yaml_escape "$STB_MAC")" "$(yaml_escape "$STB_SN")" \
    "$(yaml_escape "$STB_IP")" "$(yaml_escape "$STB_TYPE")" "$(yaml_escape "$AUTH_HOST")" \
    "$(yaml_escape "$STB_PLANE_A_IP")" "$(yaml_escape "$STB_PLANE_B_GATEWAY")"
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
