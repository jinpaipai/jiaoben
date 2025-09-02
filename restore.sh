#!/bin/bash

BACKUP_DIR="/root/backup"

LATEST_BACKUP=$(ls -1t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ 没有找到备份文件，请确认 $BACKUP_DIR 中存在 backup_xxx.tar.gz"
    exit 1
fi

echo "准备恢复备份文件：$LATEST_BACKUP"

read -p "是否继续恢复？这会覆盖已有文件 (y/n): " CONFIRM
CONFIRM=$(echo "$CONFIRM" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

if [ "$CONFIRM" != "y" ]; then
    echo "已取消恢复"
    exit 0
fi

# 恢复备份
tar -xzvf "$LATEST_BACKUP" -C /

if [ $? -eq 0 ]; then
    echo "✅ 恢复完成，数据已恢复到原始路径"

    # 自动开启开机自启
    SERVICES=(
        "nezha-dashboard.service"
        "nezha-agent.service"
        "cloudflared.service"
        "x-ui.service"
        "frpc.service"
        "frps.service"
        "qbittorrent-nox.service"
        "alist.service"
        "h-ui.service"
        "1panel-core.service"
        "1panel-agent.service"
        "filebrowser.service"
        "mihomo.service"
        "mihomo-update.service"
        "nodepass.service"
    )

    for SERVICE in "${SERVICES[@]}"; do
        if [ -f "/etc/systemd/system/$SERVICE" ]; then
            systemctl enable "$SERVICE"
            systemctl restart "$SERVICE"
            echo "✅ 已启用并重启 $SERVICE"
        else
            echo "⚠️ 服务文件 $SERVICE 不存在，跳过"
        fi
    done

    # 新增操作
    echo "🔄 重启网络服务..."
    systemctl restart networking

    echo "🔄 重新加载 systemd 配置..."
    systemctl daemon-reload

    echo "🔄 启用并立即启动 mihomo-update.timer..."
    systemctl enable --now mihomo-update.timer

    echo "✅ 所有操作完成"

else
    echo "❌ 恢复失败，请检查压缩包是否完整"
    exit 1
fi
