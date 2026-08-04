#!/usr/bin/env bash
set -euo pipefail

install_dir="${INSTALL_DIR:-/opt/iptv-spider}"
binary_path="$install_dir/iptv-spider"

if [[ "$(id -u)" != "0" ]]; then
  echo "请使用 root 运行此脚本" >&2
  exit 1
fi

install -d -m 0750 "$install_dir"
install -m 0755 iptv-spider "$binary_path"
if [[ ! -f "$install_dir/config.yaml" ]]; then
  install -m 0600 config.example.yaml "$install_dir/config.yaml"
  echo "已创建 $install_dir/config.yaml，请先填写 IPTV 和数据库信息。"
fi

cat > /etc/systemd/system/iptv-spider.service <<SERVICE
[Unit]
Description=Shanghai Telecom IPTV EPG Spider
After=network-online.target mariadb.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$install_dir
ExecStart=$binary_path -c $install_dir/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable iptv-spider
echo "安装完成。填写配置后执行: systemctl restart iptv-spider"
