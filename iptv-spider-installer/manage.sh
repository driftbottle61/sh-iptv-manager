#!/usr/bin/env bash
set -uo pipefail

APP_DIR=${IPTV_SPIDER_DIR:-/opt/sh-iptv-spider}
STATUS_CMD=/usr/local/sbin/iptv-spider-status
SERVICE=iptv-spider.service

if [ "${EUID}" -ne 0 ]; then
  echo '请使用 root 用户运行 IPTV Spider 管理菜单。'
  exit 1
fi

config_value() {
  local section=$1 key=$2
  awk -v section="$section" -v key="$key" '
    $0 == section ":" {inside=1; next}
    inside && $0 ~ /^[^[:space:]]/ {exit}
    inside && $0 ~ "^[[:space:]]+" key ":[[:space:]]*" {
      value=$0
      sub("^[[:space:]]+" key ":[[:space:]]*", "", value)
      gsub(/^\047|\047[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$APP_DIR/config.yaml"
}

wait_for_log() {
  local pattern=$1 since=$2 title=$3 attempt
  echo "正在等待$title完成（最多 3 分钟）..."
  for attempt in $(seq 1 90); do
    if journalctl -u "$SERVICE" --since "@$since" --no-pager 2>/dev/null | grep -q "$pattern"; then
      echo "$title已完成。"
      return 0
    fi
    systemctl is-active --quiet "$SERVICE" || return 1
    sleep 2
  done
  echo "等待超时，$title可能仍在后台运行。"
  return 1
}

manual_fetch() {
  local addr port base started response
  if ! systemctl is-active --quiet "$SERVICE"; then
    echo '服务未运行，不能抓取。请先选择 3 重启服务。'
    return 1
  fi
  addr=$(config_value system addr)
  port=${addr##*:}
  [[ "$port" =~ ^[0-9]+$ ]] || port=8888
  base="http://127.0.0.1:$port/api/run"

  echo '开始手动刷新频道和 EPG 数据。'
  started=$(date +%s)
  response=$(curl -fsS --connect-timeout 5 --max-time 15 "$base?task=update-chi" 2>/dev/null || true)
  if [ "$response" != 'OK' ]; then
    echo '频道抓取任务启动失败。'
    return 1
  fi
  wait_for_log '频道信息列表更新完成' "$started" '频道抓取' || true

  started=$(date +%s)
  response=$(curl -fsS --connect-timeout 5 --max-time 15 "$base?task=update-epg" 2>/dev/null || true)
  if [ "$response" != 'OK' ]; then
    echo 'EPG 抓取任务启动失败。'
    return 1
  fi
  wait_for_log '更新节目信息列表完成' "$started" 'EPG 抓取' || true
  echo
  "$STATUS_CMD" --skip-replay || true
}

restart_service() {
  echo '正在重启 IPTV Spider...'
  if systemctl restart "$SERVICE" && timeout 30 bash -c \
    'until systemctl is-active --quiet iptv-spider.service; do sleep 1; done'; then
    echo '服务已成功重启。'
    "$STATUS_CMD" --skip-replay || true
  else
    echo '服务重启失败，最近日志如下：'
    journalctl -u "$SERVICE" -n 30 --no-pager || true
  fi
}

while :; do
  echo
  echo 'IPTV Spider 管理菜单'
  echo '------------------------------------------------------------'
  echo '  1、状态显示'
  echo '  2、手动抓取'
  echo '  3、重启服务'
  echo '  4、卸载'
  echo '  0、退出'
  echo '------------------------------------------------------------'
  read -r -p '请选择 [0-4]：' choice
  case "$choice" in
    1) "$STATUS_CMD" || true ;;
    2) manual_fetch ;;
    3) restart_service ;;
    4)
      /usr/local/sbin/iptv-spider-uninstall
      if [ ! -x /usr/local/sbin/iptv-spider-uninstall ]; then
        echo '卸载完成，管理菜单即将退出。'
        exit 0
      fi
      ;;
    0)
      echo '已退出管理菜单，IPTV Spider 服务保持运行。'
      exit 0
      ;;
    *) echo '输入无效，请输入 0 到 4。' ;;
  esac
done
