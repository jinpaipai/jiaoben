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

# 将下载链接存到数组
echo "找到以下可用版本："
URLS=()
i=1
while read -r url; do
  fname=$(basename "$url")
  echo "[$i] $fname"
  URLS+=("$url")
  ((i++))
done <<< "$DOWNLOADS"

# 让用户选择版本
read -rp "请输入要安装的版本编号 [默认 1]: " CHOICE
CHOICE=${CHOICE:-1}

if (( CHOICE < 1 || CHOICE > ${#URLS[@]} )); then
  echo "❌ 输入编号无效"
  exit 1
fi

SELECTED_URL="${URLS[$((CHOICE-1))]}"
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

# 如果旧版本存在则覆盖（不再额外备份）
mv -f /tmp/mihomo /usr/local/bin/mihomo
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
systemctl restart mihomo || true

echo "=== mihomo 安装完成 ==="
systemctl status mihomo --no-pager

# =======================
# 订阅更新部分
# =======================
read -rp "是否配置订阅更新功能？(y/N): " ENABLE_SUB
if [[ "$ENABLE_SUB" =~ ^[Yy]$ ]]; then
    read -rp "请输入你的订阅链接: " SUB_URL

    if [ -z "$SUB_URL" ]; then
        echo "❌ 订阅链接为空，跳过配置订阅更新"
        exit 0
    fi

    echo "创建 mihomo_subupdate 脚本..."
    cat > /usr/local/bin/mihomo_subupdate.sh <<EOF
#!/bin/bash
# ================================================
# Mihomo 配置自动更新脚本（只在有变化时 reload）
# ================================================

CONFIG_DIR="/etc/mihomo"
CONFIG_FILE="\$CONFIG_DIR/config.yaml"
SUB_URL="$SUB_URL"
LOG_FILE="/var/log/mihomo_update.log"

mkdir -p "\$CONFIG_DIR"
touch "\$LOG_FILE"

# 拉取订阅配置到临时文件
curl -sSL "\$SUB_URL" -o "\$CONFIG_FILE".tmp
if [ \$? -ne 0 ] || [ ! -s "\$CONFIG_FILE".tmp ]; then
    echo "\$(date '+%F %T') 配置更新失败（下载错误或文件为空）" | tee -a "\$LOG_FILE"
    rm -f "\$CONFIG_FILE".tmp
    exit 1
fi

# 检查新旧配置是否有变化
if ! cmp -s "\$CONFIG_FILE".tmp "\$CONFIG_FILE"; then
    mv "\$CONFIG_FILE".tmp "\$CONFIG_FILE"
    # 尝试 reload，如果失败再 fallback 到 restart
    if systemctl reload mihomo 2>/dev/null; then
        echo "\$(date '+%F %T') 配置有变化，已 reload 服务" | tee -a "\$LOG_FILE"
    else
        systemctl restart mihomo
        echo "\$(date '+%F %T') 配置有变化，reload 不支持，已 restart 服务" | tee -a "\$LOG_FILE"
    fi
else
    rm -f "\$CONFIG_FILE".tmp
    echo "\$(date '+%F %T') 配置无变化，无需 reload" | tee -a "\$LOG_FILE"
fi
EOF

    chmod +x /usr/local/bin/mihomo_subupdate.sh

    echo "创建 systemd 服务和定时器..."
    cat > /etc/systemd/system/mihomo-update.service <<EOF
[Unit]
Description=Update mihomo config.yaml

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mihomo_subupdate.sh
EOF

    cat > /etc/systemd/system/mihomo-update.timer <<EOF
[Unit]
Description=Run mihomo_subupdate script every 30 minutes

[Timer]
OnCalendar=*:30
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now mihomo-update.timer

    echo "=== 订阅更新功能已启用 ==="
    systemctl list-timers --all | grep mihomo-update
fi
