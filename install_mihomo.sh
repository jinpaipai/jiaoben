#!/bin/bash
set -e

# 检查是否为root
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 下载mihomo amd64 V1版本
echo "正在下载 mihomo amd64 V1 版本..."
LATEST_URL=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest \
  | grep "browser_download_url" \
  | grep "linux-amd64-v1" \
  | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
  echo "未找到最新的 amd64 v1 版本下载链接，请检查。"
  exit 1
fi

wget -O /tmp/mihomo.tar.gz "$LATEST_URL"

# 解压并移动
echo "正在解压..."
tar -xvf /tmp/mihomo.tar.gz -C /tmp
chmod +x /tmp/mihomo
mv /tmp/mihomo /usr/local/bin/mihomo

# 创建配置目录
mkdir -p /etc/mihomo

# 写入 systemd service 文件
echo "正在创建 systemd 服务..."
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

# 重新加载 systemd
systemctl daemon-reexec
systemctl enable mihomo
systemctl restart networking

echo "mihomo 已安装并启动完成 ✅"
