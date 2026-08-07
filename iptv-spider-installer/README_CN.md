# 上海电信 IPTV Spider 安装包

该安装包用于合法订阅的上海电信 IPTV 用户，提供频道抓取、XMLTV、直播 M3U、TVOD 回看和本地 Logo 服务。安装包不含任何 IPTV 账号、机顶盒认证信息或数据库数据。

## 安装

在 Debian 12、Ubuntu 22.04 或更新版本的服务器上解压发行包后执行：

```bash
chmod +x install.sh
sudo ./install.sh
```

安装程序会交互式询问两类参数：

- 抓取模块：IPTV UID、机顶盒 MAC、SN、IP、型号和认证服务器。
- 回放模块：已有直播 M3U 源、udpxy/msd_lite 地址、回看天数和需要由本服务中继回看流的客户端 IP。

安装脚本会安装 MariaDB，若数据库地址填写 `127.0.0.1` 或 `localhost`，会自动创建数据库和用户。生成的 `config.yaml` 权限为 `600`，请勿提交到 Git 或公开分享。

## 地址

安装完成后会显示实际地址。常用接口：

```text
http://<server>:<port>/tv-direct.m3u
http://<server>:<port>/api/epg?daysAgo=5
http://<server>:<port>/iptvlogos/CGTN.png
```

`tv-direct.m3u` 使用配置的 udpxy/msd_lite 把 IPTV 多播转换为 HTTP 单播，并附加 TVOD 回看属性。Logo 与频道分组来自安装包中的离线参考映射，不依赖外部 Logo 主机。

## 服务管理

```bash
systemctl status iptv-spider
journalctl -u iptv-spider -f
systemctl restart iptv-spider
```

配置文件位于安装目录下的 `config.yaml`。修改后重启服务即可生效。

## 更新

升级前备份当前配置：

```bash
cp /opt/sh-iptv-spider/config.yaml /root/iptv-spider-config.yaml.bak
```

新发行包默认不会覆盖已有 `config.yaml`；需要先确认并迁移新增配置字段后再升级。
