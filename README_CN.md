# 上海电信 IPTV 专网与回看部署手册

本项目用于在自己的上海电信 IPTV 账号和家庭网络中获取频道、节目单、直播列表与节目回看地址。本项目只适用于合法订阅的上海电信 IPTV 用户；请勿公开账号、机顶盒认证信息或带有 `AuthInfo` 的播放地址。

## 第一部分：打通上海电信 IPTV 专网

### 1. 先理解网络结构

家庭普通网络和 IPTV 专网是两条不同的网络：

```text
普通设备 -> 家庭 LAN -> 普通宽带 -> 互联网
IPTV 服务 -> IPTV VLAN -> 上海电信 IPTV 专网
```

IPTV 的认证、节目单、直播和回看服务器都必须经 IPTV 专网访问。只让 DNS 能解析、或只让部分 IP 走专网，都不足以实现回看。

### 2. 推荐网络拓扑

```text
光猫/ONT
  └─ IPTV VLAN（常见为 VLAN 85，按本地实际配置）
       └─ RouterOS bridge_iptv
            ├─ 真实机顶盒
            └─ IPTV Spider 所在服务器或容器的 IPTV 网卡

普通 LAN -> RouterOS bridge_lan -> TiviMate / xTeVe / 家庭设备
```

IPTV Spider 最少需要两条网络：

| 网卡 | 用途 | 示例 |
| --- | --- | --- |
| `eth0` | 家庭 LAN，供浏览器、xTeVe、TiviMate 访问 | `192.168.x.x` |
| `eth1` | IPTV 专网，使用机顶盒对应的 VLAN/MAC/IP | `30.x.x.x` |

不要把 IPTV 专网默认路由设成服务器默认路由。普通互联网、软件更新、数据库访问等仍应从家庭 LAN 走普通宽带。

### 3. RouterOS 基础配置要点

以下名称和地址只是示例，请替换成自己的接口、VLAN 和网段。

1. 从 WAN 创建 IPTV VLAN，并将其桥接到 IPTV 网络。

```routeros
/interface vlan
add name=pon-vlan85 interface=ether5_wan vlan-id=85

/interface bridge
add name=bridge_iptv

/interface bridge port
add bridge=bridge_iptv interface=pon-vlan85
```

2. 如果 IPTV Spider 通过交换机或 Proxmox 接入，连接宿主机的 LAN 端口必须允许 IPTV VLAN 带标签通过；容器的第二块网卡应配置 `tag=85`。

3. 为电信 IPTV 回看服务器添加静态专线路由。实际 IP 会因地区和时间变化，以抓包或访问日志为准。

```routeros
/ip route
add dst-address=222.68.211.94/32 gateway=30.182.0.1 comment="IPTV TVOD dispatch"
add dst-address=124.75.27.0/24 gateway=30.182.0.1 comment="IPTV TVOD CDN"
add dst-address=124.75.28.0/24 gateway=30.182.0.1 comment="IPTV TVOD CDN"
```

其中 `30.182.0.1` 只是示例网关，应以 IPTV DHCP 下发的网关为准。

4. IPTV Spider 从家庭 LAN 访问 IPTV 专网时，通常需要从 IPTV 出口做源地址转换：

```routeros
/ip firewall nat
add chain=srcnat src-address=192.168.100.90 out-interface=bridge_iptv action=masquerade comment="iptv-spider auth"
```

### 4. 避免端口转发误伤 IPTV 回看

电信 TVOD 常使用 TCP `8006`。如果路由器中存在类似“所有 TCP 8006 转发到 PVE”的规则，IPTV 回看请求可能会被错误送回内网服务器。

正确做法是在 PVE 端口转发规则之前加入精确豁免：

```routeros
/ip firewall nat
add chain=dstnat action=accept protocol=tcp dst-address=222.68.211.94 dst-port=8006 comment="IPTV TVOD bypass"
add chain=dstnat action=accept protocol=tcp dst-address=124.75.27.0/24 dst-port=8006 comment="IPTV TVOD CDN bypass"
add chain=dstnat action=accept protocol=tcp dst-address=124.75.28.0/24 dst-port=8006 comment="IPTV TVOD CDN bypass"
```

不要使用“所有 `8006` 不转发”的宽泛规则，以免影响自己的 PVE 服务。

### 5. 专网连通性检查

在 IPTV Spider 服务器上检查：

```bash
ip route get 222.68.211.94
curl -I --connect-timeout 5 http://222.68.211.94:8006/
```

第一条应显示 IPTV 专网对应的接口或策略路由。第二条不一定返回 `200`，但不应被错误连到内网 PVE，也不应长期超时。

### 6. Proxmox LXC 特别说明

推荐容器两块网卡：

```text
net0: bridge=vmbr0, ip=192.168.100.90/24
net1: bridge=vmbr0, tag=85, hwaddr=<机顶盒 MAC>, ip=<IPTV 地址>/24
```

宿主机的物理上联、`vmbr0` 和交换机端口都必须允许 VLAN 85。不要在未确认 DHCP、MAC 绑定规则前，随意让容器与真实机顶盒同时申请同一个 IPTV 租约。

## 第二部分：项目安装、配置与使用

### 1. 环境要求

- Debian 12 / Ubuntu 22.04 或更新版本
- Go 1.23 或更新版本
- MariaDB/MySQL 8.x
- 可访问上海电信 IPTV 专网
- 一台已认证的上海电信机顶盒，或合法取得的账号、SN、MAC、专网地址
- 可选：xTeVe 与 TiviMate

### 2. 获取源码与准备配置

```bash
git clone <你的仓库地址> /opt/iptv-spider
cd /opt/iptv-spider
cp config.example.yaml config.yaml
chmod 600 config.yaml
```

`config.yaml` 必须保留在服务器本地，且不要提交 Git。至少需要填写：

```yaml
system:
  addr: '0.0.0.0:8888'
  db-type: 'mysql'

stb:
  uid: '<你的 IPTV 账号>'
  mac: '<机顶盒 MAC>'
  sn: '<机顶盒 SN>'
  ip: '<IPTV 专网地址>'
  type: '<机顶盒型号>'
  auth_host: '<认证服务器:端口>'

epg:
  xml_url: 'http://<服务器 LAN IP>:8888/api/epg?daysAgo=7'
  fetch_cron: '0 0 8,16,23 * * *'

mysql:
  path: '127.0.0.1'
  db-name: 'iptv'
  username: 'iptv'
  password: '<数据库密码>'
```

可将 OSS 关闭，除非确实需要向 MinIO/COS 上传节目单：

```yaml
oss:
  enable: false
```

### 3. 初始化数据库

```sql
CREATE DATABASE iptv CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'iptv'@'127.0.0.1' IDENTIFIED BY '请使用强密码';
GRANT ALL PRIVILEGES ON iptv.* TO 'iptv'@'127.0.0.1';
FLUSH PRIVILEGES;
```

程序首次启动时会自动建立数据表。

### 4. 编译与安装

```bash
cd /opt/iptv-spider
go mod download
go build -o iptv-spider .
install -m 755 iptv-spider /usr/local/bin/iptv-spider
```

创建 systemd 服务 `/etc/systemd/system/iptv-spider.service`：

```ini
[Unit]
Description=Shanghai Telecom IPTV EPG Spider
After=network-online.target mariadb.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/iptv-spider
ExecStart=/usr/local/bin/iptv-spider -c /opt/iptv-spider/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

启动并检查：

```bash
systemctl daemon-reload
systemctl enable --now iptv-spider
systemctl status iptv-spider
curl http://127.0.0.1:8888/tv.m3u -o /dev/null
```

### 5. 主要访问地址

| 地址 | 用途 |
| --- | --- |
| `http://<服务器IP>:8888/api/epg?daysAgo=7` | XMLTV 节目单 |
| `http://<服务器IP>:8888/tv.m3u` | 适配 TiviMate 的直播和回看播放列表 |
| `http://<服务器IP>:8888/api/catchup/m3u` | 带回看属性的通用 M3U |

`tv.m3u` 会读取 xTeVe 播放列表，并为支持回看的频道注入 `catchup` 属性。默认 xTeVe 地址应按实际部署修改。

### 6. xTeVe 与 TiviMate 配置

1. 将 IPTV Spider 的直播列表导入 xTeVe。
2. 在 xTeVe 中完成频道映射和 XMLTV 映射。
3. 在 TiviMate 新建播放列表，填写：

```text
http://<IPTV Spider LAN IP>:8888/tv.m3u
```

4. 节目单地址填写：

```text
http://<IPTV Spider LAN IP>:8888/api/epg?daysAgo=7
```

5. 刷新播放列表与节目单后，历史节目应显示回看入口。

### 7. 回看工作原理

直播是固定频道流；回看必须先从电信 EPG 获取某个节目的正式 TVOD 地址：

```text
TiviMate 选择历史节目
  -> IPTV Spider 根据时间找到节目 ID
  -> 调用电信 getTvodPlayUrl
  -> 电信返回带签名的 index.m3u8
  -> TiviMate 播放 HLS 分片
```

不要把 `AuthInfo`、`Playseek` URL、数据库备份或抓包文件上传到 GitHub，它们可用于访问个人 IPTV 会话。

### 8. 常见故障排查

| 现象 | 优先检查项 |
| --- | --- |
| 直播可播、回看 HTTP 错误 | RouterOS 是否把 IPTV 的 TCP 8006 误 DNAT 到 PVE；IPTV 路由是否覆盖 CDN 网段 |
| 所有历史节目都播放直播 | 是否使用了旧 RTSP 时移实现；应使用 `getTvodPlayUrl` 的 HLS 回看实现 |
| 当前正在播出的节目回看报错 | TVOD 结束时间不能晚于当前时刻；使用已播部分作为结束时间 |
| 频道或节目单为空 | 检查 IPTV 专网、认证信息、MariaDB 连接和服务日志 |
| 回看突然失效 | 认证会话可能过期；检查服务日志并等待/触发重新认证 |

查看日志：

```bash
journalctl -u iptv-spider -f
```

## 安全清单

- 将 `config.yaml` 加入 `.gitignore`。
- 不提交数据库文件、`log/`、认证抓包、播放 URL。
- 对服务端口使用 LAN 防火墙限制，不要直接暴露到公网。
- 定期备份 MariaDB，但备份文件应加密并保存在私有位置。
