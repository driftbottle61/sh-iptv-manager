#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "请使用 root 用户运行安装程序。"
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_DIR=/opt/sh-iptv-spider
FIXED_AUTH_HOST='222.68.208.73:7001'

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
    echo "$1不能为空。"
    exit 1
  fi
}

yaml_value() {
  local key=$1 file=$2
  sed -n "s/^[[:space:]]*${key}:[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$file" | tail -n 1
}

collect_stb_manual() {
  STB_UID=$(ask 'IPTV 账号 UID')
  STB_MAC=$(ask '机顶盒 MAC 地址')
  STB_SN=$(ask '机顶盒 SN 序列号')
  STB_TYPE=$(ask '机顶盒型号')
  AUTH_HOST="$FIXED_AUTH_HOST"
  STB_PLANE_A_IP=$(ask '机顶盒 A 面/LAN 地址（可留空）')
  STB_IP=$(ask '机顶盒 B 面/IPTV 专网地址')
  STB_PLANE_B_GATEWAY=$(ask '机顶盒 B 面网关（可留空）')
}

collect_stb_capture() {
  local probe output capture_ok answer auth_mode
  probe="$SCRIPT_DIR/bin/stb-probe-linux-amd64"
  if [ "$(uname -m)" != 'x86_64' ] || [ ! -x "$probe" ]; then
    echo '安装包中没有适用于当前 CPU 的 stb-probe 程序。'
    echo '请选择手工输入，或在 amd64 Debian/Ubuntu 主机上抓包。'
    return 1
  fi
  if ! command -v ssh >/dev/null 2>&1 || ! command -v scp >/dev/null 2>&1; then
    echo '正在安装抓包模块所需的 SSH 客户端...'
    apt-get update
    apt-get install -y --no-install-recommends openssh-client ca-certificates
  fi

  ROUTER_HOST=$(ask 'RouterOS 地址' '192.168.100.1')
  ROUTER_PORT=$(ask 'RouterOS SSH 端口' '1314')
  ROUTER_USER=$(ask 'RouterOS SSH 用户名' 'david_ni')
  auth_mode=$(ask 'RouterOS 登录方式：1=用户名和密码，2=SSH 私钥' '1')
  ROUTER_KEY=''
  ROUTER_PASSWORD=''
  case "$auth_mode" in
    2)
      ROUTER_KEY=$(ask 'SSH 私钥路径' '/root/.ssh/id_ed25519_routeros')
      if [ ! -r "$ROUTER_KEY" ]; then
        echo "SSH 私钥无法读取：$ROUTER_KEY"
        return 1
      fi
      ;;
    *)
      ROUTER_PASSWORD=$(ask_secret 'RouterOS SSH 密码')
      require_value 'RouterOS SSH 密码' "$ROUTER_PASSWORD"
      if ! command -v sshpass >/dev/null 2>&1; then
        echo '正在安装 RouterOS 密码登录组件...'
        apt-get update
        apt-get install -y --no-install-recommends sshpass
      fi
      export STB_PROBE_ROUTER_PASSWORD="$ROUTER_PASSWORD"
      ;;
  esac
  ROUTER_IFACE=$(ask '连接实体机顶盒的 RouterOS 物理端口' 'ether3_lan')
  CAPTURE_SECONDS=$(ask '抓包时长（秒）' '120')
  require_value 'RouterOS 地址' "$ROUTER_HOST"
  require_value 'RouterOS SSH 用户名' "$ROUTER_USER"
  require_value 'RouterOS 端口' "$ROUTER_IFACE"

  while :; do
    echo
    echo '抓包将在 RouterOS 的 IPTV 物理端口上运行。'
    echo '按回车并看到“抓包已开始”后，请立即重新启动实体机顶盒。'
    echo '等待机顶盒进入首页；抓包期间请勿中断安装程序。'
    read -r -p '确认已经准备好重启机顶盒后，按回车开始抓包... ' answer
    output=$(mktemp /tmp/stb-probe-result.XXXXXX)
    capture_ok=0
    echo
    echo '抓包已开始，请现在立即重启实体机顶盒。'
    if [ -n "$ROUTER_PASSWORD" ]; then
      "$probe" \
        -router "$ROUTER_HOST" -router-port "$ROUTER_PORT" \
        -router-user "$ROUTER_USER" -router-password-env STB_PROBE_ROUTER_PASSWORD \
        -interface "$ROUTER_IFACE" -duration "$CAPTURE_SECONDS" >"$output" 2>&1 || capture_ok=$?
    else
      "$probe" \
        -router "$ROUTER_HOST" -router-port "$ROUTER_PORT" \
        -router-user "$ROUTER_USER" -router-key "$ROUTER_KEY" \
        -interface "$ROUTER_IFACE" -duration "$CAPTURE_SECONDS" >"$output" 2>&1 || capture_ok=$?
    fi

    echo
    echo '检测到的机顶盒数据：'
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
      echo '抓包完成，以上数据将自动写入 config.yaml。'
      unset STB_PROBE_ROUTER_PASSWORD ROUTER_PASSWORD
      return 0
    fi
    echo '本次抓包没有取得全部必需的认证字段。'
    answer=$(ask '输入 R 重新抓包，或输入 M 改为手工填写' 'R')
    case "$answer" in
      [Mm]*) unset STB_PROBE_ROUTER_PASSWORD ROUTER_PASSWORD; return 1 ;;
    esac
  done
}

show_epg_stats() {
  local attempt count stats total_channels epg_channels programmes first_time last_time warnings log_file fetch_complete
  echo
  echo '正在等待首次 EPG 抓取完成（最多 3 分钟）...'
  count=0
  fetch_complete=0
  log_file="$APP_DIR/latest_log"
  for attempt in $(seq 1 36); do
    if ! systemctl is-active --quiet iptv-spider; then
      echo 'IPTV Spider 服务未运行，无法统计 EPG。'
      systemctl status iptv-spider --no-pager --lines=10 || true
      return 1
    fi
    count=$(MYSQL_PWD="$MYSQL_PASSWORD" mysql --batch --skip-column-names \
      -h "$MYSQL_HOST" -u "$MYSQL_USER" "$MYSQL_DB" \
      -e 'SELECT COUNT(*) FROM epg_details;' 2>/dev/null || printf '0')
    if [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ] && [ -f "$log_file" ] && grep -q '更新节目信息列表完成' "$log_file"; then
      fetch_complete=1
      break
    fi
    sleep 5
  done
  if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -eq 0 ]; then
    echo '等待超时：数据库中尚无 EPG 节目，请检查服务日志：'
    echo "  journalctl -u iptv-spider -n 100 --no-pager"
    return 1
  fi
	if [ "$fetch_complete" -eq 0 ]; then
		echo '等待超时：EPG 抓取仍在进行，以下显示当前统计。'
	fi

  total_channels=$(MYSQL_PWD="$MYSQL_PASSWORD" mysql --batch --skip-column-names \
    -h "$MYSQL_HOST" -u "$MYSQL_USER" "$MYSQL_DB" \
    -e 'SELECT COUNT(*) FROM channel_infos;' 2>/dev/null || printf '0')
  stats=$(MYSQL_PWD="$MYSQL_PASSWORD" mysql --batch --skip-column-names \
    -h "$MYSQL_HOST" -u "$MYSQL_USER" "$MYSQL_DB" \
    -e "SELECT COUNT(DISTINCT comm_name), COUNT(*), DATE_FORMAT(FROM_UNIXTIME(MIN(start_time)/1000),'%Y-%m-%d %H:%i'), DATE_FORMAT(FROM_UNIXTIME(MAX(end_time)/1000),'%Y-%m-%d %H:%i') FROM epg_details;" 2>/dev/null || true)
  IFS=$'\t' read -r epg_channels programmes first_time last_time <<< "$stats"
  warnings=0
  if [ -f "$log_file" ]; then
    warnings=$(grep -c 'FetchChannelProg Err' "$log_file" 2>/dev/null || true)
  fi
  echo 'EPG 抓取统计：'
  echo "  频道记录数：${total_channels:-0}"
  echo "  已有节目单频道：${epg_channels:-0}"
  echo "  节目总数：${programmes:-0}"
  echo "  覆盖时间：${first_time:-未知} 至 ${last_time:-未知}"
  echo "  本次日志抓取警告：${warnings:-0}"
}

valid_ipv4() {
  local ip=$1 part
  local -a parts
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r -a parts <<< "$ip"
  for part in "${parts[@]}"; do
    [ "$part" -ge 0 ] && [ "$part" -le 255 ] || return 1
  done
}

configure_iptv_interface() {
  local answer interfaces_file=/etc/network/interfaces tmp backup
  echo
  echo 'IPTV 专网配置'
  echo "即将把抓到的专网地址 $STB_IP/24 配置到 eth1。"
  echo '实体机顶盒和本机不能同时使用同一个专网 IP。'
  while :; do
    answer=$(ask '请关闭实体机顶盒；关闭后输入 YES，输入 SKIP 可暂不配置')
    case "$answer" in
      YES|yes|Yes) break ;;
      SKIP|skip|Skip)
        echo '已跳过 eth1 专网配置。稍后请在关闭机顶盒后手工配置。'
        return 0
        ;;
      *) echo '请输入 YES 确认机顶盒已经关闭，或输入 SKIP 跳过。' ;;
    esac
  done

  if [ ! -e /sys/class/net/eth1 ]; then
    echo '未找到 eth1，无法自动配置 IPTV 专网；安装的其他部分不受影响。'
    return 0
  fi
  if ! valid_ipv4 "$STB_IP"; then
    echo "抓到的 IPTV 专网地址格式无效：$STB_IP"
    return 0
  fi
  if grep -Eq '^[[:space:]]*iface[[:space:]]+eth1[[:space:]]+inet' "$interfaces_file" && \
     ! grep -q '^# BEGIN IPTV-SPIDER ETH1$' "$interfaces_file"; then
    echo '/etc/network/interfaces 中已经存在非本程序创建的 eth1 配置。'
    echo '为避免覆盖用户配置，已跳过自动配置，请手工检查 eth1。'
    return 0
  fi

  backup="${interfaces_file}.iptv-spider.$(date +%Y%m%d%H%M%S).bak"
  cp -a "$interfaces_file" "$backup"
  tmp=$(mktemp /tmp/interfaces.XXXXXX)
  awk '
    $0 == "# BEGIN IPTV-SPIDER ETH1" {skip=1; next}
    $0 == "# END IPTV-SPIDER ETH1" {skip=0; next}
    !skip {print}
  ' "$interfaces_file" > "$tmp"
  {
    cat "$tmp"
    printf '\n# BEGIN IPTV-SPIDER ETH1\n'
    printf 'auto eth1\n'
    printf 'iface eth1 inet static\n'
    printf '\taddress %s/24\n' "$STB_IP"
    printf '# END IPTV-SPIDER ETH1\n'
  } > "$interfaces_file"
  rm -f "$tmp"

  ip link set eth1 up
  ip -4 addr flush dev eth1 scope global
  ip addr add "$STB_IP/24" dev eth1
  echo "eth1 已配置为 $STB_IP/24；未重启网络，当前 SSH 连接不受影响。"
  echo "原网络配置备份：$backup"
  systemctl restart iptv-spider
}

echo '上海电信 IPTV Spider 安装程序'
echo '生成的配置包含 IPTV 认证信息；本安装程序不会上传这些信息。'

APP_DIR=$(ask '安装目录' "$DEFAULT_DIR")
PORT=$(ask '服务端口' '8888')
LAN_IP=$(ask '用于节目源、EPG 和 Logo 的服务器 LAN 地址')
require_value '服务器 LAN 地址' "$LAN_IP"

echo
echo '抓取模块与机顶盒配置'
echo '  1) 手工输入机顶盒信息'
echo '  2) 通过 RouterOS 自动抓取机顶盒认证信息'
STB_MODE=$(ask '请选择机顶盒信息获取方式' '2')
case "$STB_MODE" in
  2|[Cc]*) collect_stb_capture || collect_stb_manual ;;
  *) collect_stb_manual ;;
esac
require_value 'IPTV 账号 UID' "$STB_UID"
require_value '机顶盒 MAC 地址' "$STB_MAC"
require_value '机顶盒 SN 序列号' "$STB_SN"
require_value '机顶盒 IPTV 专网地址' "$STB_IP"

echo
echo '直播与回放配置'
SOURCE_M3U=$(ask '已有直播 M3U 地址（可留空，留空则使用项目自身输出）')
UDPXY=$(ask 'udpxy/msd_lite 地址（可留空，格式：主机:端口）')
CATCHUP_DAYS=$(ask '回放天数' '7')
RELAY_CLIENTS=$(ask '需要中继的客户端地址（可留空，多个地址用逗号分隔）')

echo
echo 'MySQL / MariaDB 配置'
MYSQL_HOST=$(ask 'MySQL 主机' '127.0.0.1')
MYSQL_DB=$(ask '数据库名称' 'iptv')
MYSQL_USER=$(ask '数据库用户名' 'iptv')
MYSQL_PASSWORD=$(ask_secret '数据库密码')
require_value '数据库密码' "$MYSQL_PASSWORD"

if [ -d "$APP_DIR" ] && [ -f "$APP_DIR/config.yaml" ]; then
  echo "$APP_DIR 已存在 config.yaml。为保护现有配置，安装已停止。"
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
  echo '安装包中没有兼容的程序，系统也未安装 Go，无法继续。'
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
configure_iptv_interface
show_epg_stats || true

echo
echo '安装完成。'
echo "节目源 M3U：http://$LAN_IP:$PORT/tv-direct.m3u"
echo "节目单 EPG：http://$LAN_IP:$PORT/api/epg?daysAgo=$CATCHUP_DAYS"
echo "Logo 示例：http://$LAN_IP:$PORT/iptvlogos/CGTN.png"
