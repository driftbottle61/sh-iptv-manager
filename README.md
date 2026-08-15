# 上海电信 IPTV Spider

中文完整使用手册请阅读 [README_CN.md](README_CN.md)。

本仓库包含上海电信 IPTV 节目单、直播列表和 TVOD 回看代理。请先阅读专网配置章节，再安装程序。

上海电信 IPTV 抓取程序，用于抓取 IPTV EPG 和 M3U8 数据。

## 环境要求
1. 上海电信 IPTV 机顶盒以及账号
2. mysql 数据库
3. 能够访问 IPTV 专网网络

因为 IPTV 专网的限制，程序需要在能够访问 IPTV 专网的环境中运行，该程序访问的所有地址都必须走专网出口，无法通过公网抓取。
回放地址也需要走专网才能访问。

## 安装使用
自行探索

## 安装前发现机顶盒认证参数

新 Ubuntu/CT 还未打通 IPTV 专网时，可从有 SSH 管理权限的 RouterOS 上抓取实体
机顶盒认证流量，而不是在目标 CT 或 `.90` 上抓包。安装包中的
[`stb-probe`](iptv-spider-installer/cmd/stb-probe/) 会通过 RouterOS 生成短时 pcap、
下载到运行工具的主机解析，并恢复 RouterOS 原有 sniffer 参数。使用方法见
[安装包中文文档](iptv-spider-installer/README_CN.md#安装前从-routeros-获取机顶盒参数)。

## 可安装发行版

面向 Debian/Ubuntu 的交互式安装包在
[`iptv-spider-installer/`](iptv-spider-installer/)；它不包含任何账号、机顶盒认证信息或现网配置。

最新发行版为 `v1.2.26`。下载 `releases/sh-iptv-spider-installer-1.2.26-linux-amd64.tar.gz` 后执行：

```bash
tar -xzf sh-iptv-spider-installer-1.2.26-linux-amd64.tar.gz
cd sh-iptv-spider-installer
./install.sh
```

安装程序支持使用 RouterOS 用户名/密码或 SSH 私钥抓取机顶盒信息，启动后显示 EPG
抓取统计，并内置频道 Logo。安装后运行 `iptv-spider` 可打开中文日常管理菜单。

也可使用一键安装脚本：

```bash
curl -fsSL https://github.com/driftbottle61/sh-iptv-manager/releases/download/v1.2.26/install-oneclick.sh | bash
```
详细说明见 [安装包中文文档](iptv-spider-installer/README_CN.md)。

## 其他说明
1. 程序使用Go语言编写，编译后可在支持的系统上运行。
2. 程序会将抓取到的频道列表和流媒体地址存储到 mysql 数据库中，数据库结构请参考源码中的建表语句。
3. 程序仅支持上海电信 IPTV，其他地区或运营商的 IPTV 无法使用。
4. 代码写的比较烂，欢迎有兴趣的同学自行fork改进。

## 免责申明
1. 本程序仅供学习和研究使用，请勿用于商业用途。
2. 如因使用本程序而引起的任何法律纠纷或其他问题，作者概不负责。
3. 使用本程序即表示您同意遵守相关法律法规，并自行承担使用风险。
