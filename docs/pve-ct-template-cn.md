# IPTV Spider PVE CT 创建模板

在 PVE 主机上执行。模板适用于上海电信 IPTV Spider，使用 Debian 12 非特权 CT，包含管理 LAN、VLAN 85 IPTV 专网和预留 VLAN 51 三张网卡。

## 创建命令

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

## 使用前必须修改

- `116`：替换为未占用的 CT ID。
- `192.168.100.90/24`：替换为未占用的管理 LAN 地址。
- `local:vztmpl/...`：替换为本机实际 Debian 模板名称。
- `local-lvm:10`：如果使用其他存储，替换存储名和磁盘大小。
- `vmbr0`：替换为实际桥接名称。

创建前检查：

```bash
pct list
pveam list local | grep debian-12
ping -c 2 192.168.100.90
```

## 网卡用途

| 网卡 | 用途 | 配置 |
| --- | --- | --- |
| `eth0` | 管理 LAN、SSH、M3U、EPG、Logo | `192.168.100.90/24` |
| `eth1` | IPTV VLAN 85，抓包和 B 面专网 | 创建时不填写 IP |
| `eth2` | VLAN 51，A 面/特殊认证预留 | 当前常规运行可不使用 |

PVE 宿主机、交换机上联和 `vmbr0` 必须允许 VLAN 85/51 通过。`eth1` 的 IPTV 专网地址由安装程序在抓到机顶盒信息后配置；不要让在线机顶盒和 CT 同时使用相同专网 IP。

## 启动与安装

```bash
pct start 116
pct enter 116
passwd
ip -br addr
ip route
```

确认 `eth0` 可以访问 LAN 和互联网后，执行项目发行版的一键安装命令。创建后检查：

```bash
pct config 116
pct status 116
pct exec 116 -- ip -br addr
pct exec 116 -- ip route
```

安装程序会提供手工填写或 RouterOS 抓包两种方式，并在自动抓包完成后将 IPTV 专网信息写入项目配置。
