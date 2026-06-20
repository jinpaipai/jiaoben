#    wget -qO- https://raw.githubusercontent.com/jinpaipai/jiaoben/refs/heads/main/install_mihomo.sh | sudo bash
#!/usr/bin/env bash
set -e

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

echo "=== mihomo 自动安装脚本（镜像版）==="

# 获取最新 release JSON
echo "获取最新版本信息..."
RELEASE_JSON=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest)

# 提取 linux-amd64 gz 链接
DOWNLOADS=$(echo "$RELEASE_JSON" | grep "browser_download_url" | grep "linux-amd64" | grep "\.gz" | cut -d '"' -f 4)

if [ -z "$DOWNLOADS" ]; then
    echo "❌ 未找到 amd64 gz 下载链接！"
    exit 1
fi

# 加国内镜像前缀
MIRRORED_DOWNLOADS=""
while read -r url; do
    MIRRORED_DOWNLOADS+=$(echo "https://github.jinpaipai.fun:1443/$url")$'\n'
done <<< "$DOWNLOADS"

# 存入数组
URLS=()
while IFS= read -r line; do
    line="${line//$'\r'/}"
    if [[ -n "$line" ]]; then
        URLS+=("$line")
    fi
done <<< "$MIRRORED_DOWNLOADS"

# 列出可用版本
echo "找到以下可用版本："
for i in "${!URLS[@]}"; do
    fname=$(basename "${URLS[i]}")
    echo "[$((i+1))] $fname"
done

# 用户选择版本
while true; do
    read -rp "请输入要安装的版本编号 [默认 1]: " CHOICE
    CHOICE="${CHOICE:-1}"
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
        echo "❌ 输入无效，请输入数字"
        continue
    fi
    if (( CHOICE < 1 || CHOICE > ${#URLS[@]} )); then
        echo "❌ 编号超出范围"
        continue
    fi
    break
done

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
mv -f /tmp/mihomo /usr/local/bin/mihomo
mkdir -p /etc/mihomo

# 创建 systemd 服务
echo "创建 systemd 服务..."
cat > /etc/systemd/system/mihomo.service <<EOF
[Unit]
Description=mihomo Daemon, Another Clash Kernel.
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
Restart=always
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF

# 确保 sysctl.conf 存在
if [ ! -f /etc/sysctl.conf ]; then
    echo "# sysctl configuration" > /etc/sysctl.conf
fi

# 启用 IP 转发
echo "启用 IP 转发..."
sed -i 's/^#\?net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sed -i 's/^#\?net.ipv6.conf.all.forwarding=.*/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p

# 启动服务
systemctl daemon-reload
systemctl enable mihomo
systemctl restart networking
systemctl restart mihomo || true

echo "=== mihomo 安装完成 ==="
systemctl status mihomo --no-pager

# =======================
# 订阅更新功能
# =======================
read -rp "是否配置订阅更新功能？(y/N): " ENABLE_SUB
if [[ "$ENABLE_SUB" =~ ^[Yy]$ ]]; then
    read -rp "请输入你的订阅链接: " SUB_URL

    if [ -z "$SUB_URL" ]; then
        echo "❌ 订阅链接为空，跳过配置订阅更新"
    else
        echo "创建 mihomo_subupdate.sh 脚本..."
        cat > /usr/local/bin/mihomo_subupdate.sh <<'EOF'
#!/bin/bash

CONFIG_DIR="/etc/mihomo"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SUB_URL="__SUB_URL__"
LOG_FILE="/var/log/mihomo_update.log"

mkdir -p "$CONFIG_DIR"
touch "$LOG_FILE"

TMP_FILE="${CONFIG_FILE}.tmp"

# 下载配置
if ! curl -fsSL --connect-timeout 10 --max-time 60 \
    "$SUB_URL" -o "$TMP_FILE"; then
    echo "$(date '+%F %T') 配置下载失败" | tee -a "$LOG_FILE"
    rm -f "$TMP_FILE"
    exit 1
fi

# 检查文件是否为空
if [ ! -s "$TMP_FILE" ]; then
    echo "$(date '+%F %T') 下载的配置为空" | tee -a "$LOG_FILE"
    rm -f "$TMP_FILE"
    exit 1
fi

# 检查是否是 HTML 错误页面
if grep -qiE '<html|<!DOCTYPE|<head|<body|Error code|Cloudflare|502 Bad Gateway|503 Service Unavailable|504 Gateway|522|404 Not Found' "$TMP_FILE"; then
    echo "$(date '+%F %T') 下载内容不是有效配置（疑似错误页面）" | tee -a "$LOG_FILE"
    rm -f "$TMP_FILE"
    exit 1
fi

# 使用 mihomo 校验配置
if ! /usr/local/bin/mihomo -t -d "$CONFIG_DIR" -f "$TMP_FILE" >/dev/null 2>&1; then
    echo "$(date '+%F %T') 配置校验失败，未更新" | tee -a "$LOG_FILE"
    rm -f "$TMP_FILE"
    exit 1
fi

# 判断是否有变化
if cmp -s "$TMP_FILE" "$CONFIG_FILE"; then
    rm -f "$TMP_FILE"
    echo "$(date '+%F %T') 配置无变化" | tee -a "$LOG_FILE"
    exit 0
fi

# 替换配置
mv -f "$TMP_FILE" "$CONFIG_FILE"

# 优先 reload，不支持则 restart
if systemctl reload mihomo >/dev/null 2>&1; then
    echo "$(date '+%F %T') 配置已更新，reload 成功" | tee -a "$LOG_FILE"
else
    if systemctl restart mihomo; then
        echo "$(date '+%F %T') 配置已更新，restart 成功" | tee -a "$LOG_FILE"
    else
        echo "$(date '+%F %T') 配置已更新，但重启失败" | tee -a "$LOG_FILE"
        exit 1
    fi
fi

exit 0
EOF

        # 替换订阅链接
        sed -i "s|__SUB_URL__|$SUB_URL|g" /usr/local/bin/mihomo_subupdate.sh
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
OnCalendar=*:0/30
Persistent=true

[Install]
WantedBy=timers.target
EOF

        systemctl daemon-reload
        systemctl enable --now mihomo-update.timer

        echo "=== 订阅更新功能已启用 ==="
        systemctl list-timers --all | grep mihomo-update
    fi
fi

echo "=== 安装与配置完成 ==="
