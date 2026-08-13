# 上海电信 IPTV Spider 安装包

该安装包用于合法订阅的上海电信 IPTV 用户，提供频道抓取、XMLTV、直播 M3U、TVOD 回看和本地 Logo 服务。安装包不含任何 IPTV 账号、机顶盒认证信息或数据库数据。

## 安装时获取机顶盒参数

安装程序提供两种方式：手工填写，或通过 RouterOS 自动抓取实体机顶盒认证信息。
自动抓包适用于新建 Ubuntu/CT 尚未接入 IPTV 专网的情况，安装主机只需能通过 SSH
访问 RouterOS。发行包已包含 `stb-probe`，无需安装 Go。

选择自动抓包后，安装程序会询问 RouterOS 地址、SSH 端口、用户名、登录方式、连接
机顶盒的物理端口和抓包时长。登录方式支持用户名和密码，也支持 SSH 私钥；密码采用
隐藏输入，只通过临时进程环境传给 `sshpass`，不会写入 `config.yaml` 或日志。按提示
准备好后按回车，看到“现在重启机顶盒”时立即
重新启动实体机顶盒。抓包结束后会完整显示 UID、MAC、SN、型号、认证服务器、A 面
IP、B 面 IP 和 B 面网关，并自动写入 `config.yaml`。
认证服务器地址由程序固定为 `222.68.208.73:7001`，不会采用抓包中出现的其他
TM 或后端 7001 地址。

其余组件安装完成后，程序会提示关闭实体机顶盒。用户输入 `YES` 确认后，安装程序
把抓到的 B 面专网 IP 持久化到 `eth1`，仅启用该接口并重启 IPTV Spider，不会重启
整个网络服务，也不会修改承载 SSH 的 `eth0`。如暂时不希望接管机顶盒专网地址，可
输入 `SKIP`，以后再手工配置。

抓包期间工具会临时关闭指定 RouterOS bridge port 的硬件卸载，并在结束后恢复；也会
保存和恢复 RouterOS 全局 sniffer 参数、删除临时 pcap。默认物理端口为
`ether3_lan`，默认不限制 VLAN，因此可以同时识别未打标签流量、VLAN 51 和 VLAN 85。
机顶盒认证参数属于账号凭据，请勿公开发布。

## 在 Proxmox VE 创建 CT

推荐使用 Debian 12 非特权 CT。下面的模板以 CT 编号 `116`、管理地址
`192.168.100.90/24`、网关 `192.168.100.1` 和存储 `local-lvm` 为例：

```bash
pct create 116 local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
  --arch amd64 \
  --cores 2 \
  --memory 2048 \
  --swap 512 \
  --hostname iptv-spider \
  --rootfs local-lvm:10 \
  --unprivileged 1 \
  --features nesting=1 \
  --onboot 1 \
  --net0 name=eth0,bridge=vmbr0,gw=192.168.100.1,ip=192.168.100.90/24,type=veth \
  --net1 name=eth1,bridge=vmbr0,tag=85,type=veth \
  --net2 name=eth2,bridge=vmbr0,tag=51,type=veth
```

执行前先确认 CT 编号未被占用，并检查模板文件名：

```bash
pct status 116
pveam list local | grep debian-12
```

如果本机模板名称不同，请替换 `local:vztmpl/...`；如果使用其他存储，请同时替换
`local-lvm:10`。`vmbr0` 及其上联交换链路必须允许所需 VLAN 通过。

三张网卡的用途如下：

- `eth0`：LAN 管理网卡，固定地址为 `192.168.100.90/24`，安装、SSH、M3U、EPG 和 Logo 服务均通过它访问。
- `eth1`：VLAN 85 IPTV 专网网卡。创建时无需填写 IP；自动抓包安装流程会在最后提示关闭实体机顶盒，并把抓到的 B 面专网 IP 配置到该接口。
- `eth2`：VLAN 51 预留网卡，用于需要 A 面或特定认证网络的环境。当前 IPTV Spider 的常规安装和运行不依赖它；确定不用时可以省略 `--net2`。

创建后启动、进入和查看配置：

```bash
pct start 116
pct enter 116
pct config 116
```

进入 CT 后确认 `eth0` 能访问 LAN 和互联网，再运行一键安装程序。不要在 PVE
宿主机或 CT 内同时给 `eth1` 配置与仍在线机顶盒相同的专网 IP，以免发生地址冲突。

## 安装

在 Debian 12、Ubuntu 22.04 或更新版本的服务器上解压发行包后执行：

```bash
chmod +x install.sh
sudo ./install.sh
```

安装程序会交互式询问两类参数：

- 抓取模块：可手工填写，或通过 RouterOS 抓包自动取得 IPTV UID、机顶盒 MAC、SN、A/B 面 IP、型号、网关和认证服务器。
- 回放模块：已有直播 M3U 源、udpxy/msd_lite 地址、回看天数和需要由本服务中继回看流的客户端 IP。

安装脚本会安装 MariaDB，若数据库地址填写 `127.0.0.1` 或 `localhost`，会自动创建数据库和用户。生成的 `config.yaml` 权限为 `600`，请勿提交到 Git 或公开分享。

服务启动后，安装程序会等待首次 EPG 抓取（最多 3 分钟），并显示频道记录数、已有
节目单频道数、节目总数、节目覆盖时间及抓取警告数。如果超时或服务启动失败，会显示
对应的日志检查命令，但不会删除已经生成的配置。

## 地址

安装完成后会显示实际地址。常用接口：

```text
http://<server>:<port>/tv.m3u
http://<server>:<port>/api/epg?daysAgo=7
http://<server>:<port>/iptvlogos/CGTN.png
```

`tv.m3u` 使用配置的 udpxy/msd_lite 把 IPTV 多播转换为 HTTP 单播，并附加 TVOD 回看属性。Logo 与频道分组来自安装包中的离线参考映射，不依赖外部 Logo 主机。

## 服务管理

使用中文日常管理菜单：

```bash
iptv-spider
```

菜单提供状态显示、手动抓取频道和 EPG、重启服务以及交互式卸载。选择 `0` 只退出
菜单，不会停止 IPTV Spider 服务。

```bash
systemctl status iptv-spider
journalctl -u iptv-spider -f
systemctl restart iptv-spider
```

配置文件位于安装目录下的 `config.yaml`。修改后重启服务即可生效。

日常检查可以执行：

```bash
iptv-spider-status
```

该命令会显示软件版本、systemd 状态、监听端口、`eth1` 专网地址、M3U/EPG/Logo
接口状态、数据库频道与节目数量、EPG 覆盖时间、最近两小时的错误日志，并动态选择
一个已经播完的节目进行 5 秒回放取流测试。只查看状态、不测试回放时执行：

```bash
iptv-spider-status --skip-replay
```

全新安装和覆盖升级成功后，安装器也会自动执行一次完整状态检查。

## 覆盖升级

在已经安装 IPTV Spider 的服务器上运行新版一键安装命令，安装器检测到现有
`config.yaml` 后会提供覆盖升级选项。覆盖升级会：

- 保留现有 `config.yaml`、数据库内容和 `eth1` IPTV 专网配置；
- 更新主程序、抓包工具、Logo、频道映射、帮助文件和 systemd 单元；
- 在安装目录旁创建带时间戳的完整备份；
- 新版本无法稳定启动时自动恢复旧版本。

覆盖升级不会重新抓取机顶盒信息，也不会要求重新输入数据库密码。确认新版本稳定后，
可手工删除安装目录旁的 `upgrade-backup` 备份。

## 卸载

安装完成后可以执行：

```bash
iptv-spider-uninstall
```

卸载程序默认只停止并删除 IPTV Spider 服务和程序，保留配置、日志、数据库及
MariaDB 软件包。交互过程中可以单独选择是否删除 IPTV 数据库和用户、是否卸载
MariaDB。若网络配置中存在安装器创建的 `IPTV-SPIDER ETH1` 标记段，卸载时只移除
该段且不会重启网络。选择保留配置时，文件会备份到 `/root/iptv-spider-uninstall-backup-*`。

## RouterOS 回看路由

回看调度和视频 CDN 必须经 IPTV 专网网关访问。以下以 `30.182.0.1` 为例，实际网关
应使用抓包得到的 B 面网关：

```routeros
/ip route
add dst-address=222.68.211.94/32 gateway=30.182.0.1 comment="IPTV TVOD dispatch"
add dst-address=124.75.26.0/24 gateway=30.182.0.1 comment="IPTV TVOD CDN"
add dst-address=124.75.27.0/24 gateway=30.182.0.1 comment="IPTV TVOD CDN"
add dst-address=124.75.28.0/24 gateway=30.182.0.1 comment="IPTV TVOD CDN"
```

特别是 `124.75.26.0/24`：缺少这条路由时，部分节目会先报 401/404 或长时间加载，
重试后才可能播放。安装程序不会自动修改 RouterOS 路由。

## 更新

升级前备份当前配置：

```bash
cp /opt/sh-iptv-spider/config.yaml /root/iptv-spider-config.yaml.bak
```

新发行包默认不会覆盖已有 `config.yaml`；需要先确认并迁移新增配置字段后再升级。
