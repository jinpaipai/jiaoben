#!/usr/bin/env bash
set -e

CONFIG_DIR="/etc/mihomo"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
LOG_FILE="/var/log/mihomo_update.log"
SERVICE_NAME="mihomo"

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

# 提示输入新的订阅链接
read -rp "请输入新的订阅链接: " NEW_SUB_URL
if [ -z "$NEW_SUB_URL" ]; then
    echo "❌ 订阅链接为空，操作取消"
    exit 1
fi

mkdir -p "$CONFIG_DIR"
touch "$LOG_FILE"

# 下载订阅到临时文件
curl -sSL "$NEW_SUB_URL" -o "$CONFIG_FILE.tmp"
if [ $? -ne 0 ] || [ ! -s "$CONFIG_FILE.tmp" ]; then
    echo "$(date '+%F %T') 配置更新失败（下载错误或文件为空）" | tee -a "$LOG_FILE"
    rm -f "$CONFIG_FILE.tmp"
    exit 1
fi

# 检查是否有变化
if ! cmp -s "$CONFIG_FILE.tmp" "$CONFIG_FILE"; then
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    # 尝试 reload，如果失败再 fallback 到 restart
    if systemctl reload "$SERVICE_NAME" 2>/dev/null; then
        echo "$(date '+%F %T') 配置有变化，已 reload 服务" | tee -a "$LOG_FILE"
    else
        systemctl restart "$SERVICE_NAME"
        echo "$(date '+%F %T') 配置有变化，reload 不支持，已 restart 服务" | tee -a "$LOG_FILE"
    fi
else
    rm -f "$CONFIG_FILE.tmp"
    echo "$(date '+%F %T') 配置无变化，无需 reload" | tee -a "$LOG_FILE"
fi

echo "✅ 订阅更新完成"
