#!/bin/bash
set -e

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

echo "=== mihomo 自动安装脚本 ==="

# 获取最新 release 所有下载链接
echo "获取最新版本信息..."
DOWNLOADS=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
  | grep "browser_download_url" \
  | grep "linux-amd64-v1-.*.gz" \
  | cut -d '"' -f 4)

if [ -z "$DOWNLOADS" ]; then
  echo "❌ 未找到 amd64-v1.gz 下载链接！"
  exit 1
fi

# 将下载链接列出供用户选择
echo "找到以下可用版本："
i=1
declare -A URL_MAP
while read -r url; do
  fname=$(basename "$url")
  echo "[$i] $fname"
  URL_MAP[$i]=$url
  ((i++))
done <<< "$DOWNLOADS"

# 让用户选择版本
read -rp "请输入要安装的版本编号 [默认 1]: " CHOICE
CHOICE=${CHOICE:-1}

if [[ -z "${URL_MAP[$CHOICE]}" ]]; then
  echo "❌ 输入编号无效"
  exit 1
fi

SELECTED_URL="${URL_MAP[$CHOICE]}"
SELECTED_FILE=$(basename "$SELECTED_URL")

echo "你选择安装：$SELECTED_FILE"
sleep 1

# 下载
echo "正在下载 $SELECTED_FILE ..."
wget -O /tmp/mihomo.gz "$SELECTED_URL"

# 解压并安装
echo "正在解压并安装..."
gunzip -f /tmp/mihomo.gz
chmod +x /tmp/mihomo

# 备份旧版本
if [ -f /usr/local/bin/mihomo ]; then
  mv /usr/local/bin/mihomo /usr/local/bin/mihomo.bak.$(date +%s)
  echo "已备份旧版本到 /usr/local/bin/mihomo.bak.$(date +%s)"
fi

mv /tmp/mihomo /usr/local/bin/mihomo
mkdir -p /etc/mihomo

# 创建 systemd 服务
echo "创建 systemd 服务..."
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=mihomo Daemon, Another Clash Kernel.
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

# 启用 IP 转发
echo "启用 IP 转发..."
sed -i 's/^#\?net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sed -i 's/^#\?net.ipv6.conf.all.forwarding=.*/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
sysctl -p

# 启动服务
systemctl daemon-reload
systemctl enable mihomo
systemctl restart networking

# 显示状态
echo "=== 安装完成 ==="
systemctl status mihomo --no-pager
echo "旧版本如有备份在 /usr/local/bin/mihomo.bak.*"
