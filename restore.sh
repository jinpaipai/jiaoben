#!/bin/bash

BACKUP_DIR="/root/backup"

# 优先找加密备份
LATEST_ENC=$(ls -1t "$BACKUP_DIR"/backup_*.tar.gz.gpg 2>/dev/null | head -n 1)
LATEST_PLAIN=$(ls -1t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | head -n 1)

if [ -n "$LATEST_ENC" ]; then
    BACKUP_FILE="$LATEST_ENC"
    IS_ENC=1
elif [ -n "$LATEST_PLAIN" ]; then
    BACKUP_FILE="$LATEST_PLAIN"
    IS_ENC=0
else
    echo "❌ 没有找到备份文件，请确认 $BACKUP_DIR 中存在 backup_xxx.tar.gz 或 backup_xxx.tar.gz.gpg"
    exit 1
fi

echo "准备恢复备份文件：$BACKUP_FILE"

read -p "是否继续恢复？这会覆盖已有文件 (y/n): " CONFIRM
CONFIRM=$(echo "$CONFIRM" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

if [ "$CONFIRM" != "y" ]; then
    echo "已取消恢复"
    exit 0
fi

# 解密（如果是加密备份）
if [ "$IS_ENC" -eq 1 ]; then
    DECRYPTED_FILE="/tmp/restore_$$.tar.gz"
    echo "🔑 请输入解密密码（输入时不会显示字符）："
    read -s DECRYPT_PWD
    echo

    gpg --batch --yes --passphrase "$DECRYPT_PWD" -d "$BACKUP_FILE" > "$DECRYPTED_FILE"
    if [ $? -ne 0 ]; then
        echo "❌ 解密失败，请检查密码是否正确"
        rm -f "$DECRYPTED_FILE"
        exit 1
    fi
    RESTORE_FILE="$DECRYPTED_FILE"
else
    RESTORE_FILE="$BACKUP_FILE"
fi

# 解压恢复
echo "📦 正在解压并恢复..."
tar -xzvf "$RESTORE_FILE" -C /

if [ $? -eq 0 ]; then
    echo "✅ 恢复完成，数据已恢复到原始路径"

    # 删除临时解密文件
    if [ "$IS_ENC" -eq 1 ]; then
        rm -f "$DECRYPTED_FILE"
    fi

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
        "AdGuardHome.service"
        "aria2.service"
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

    # 网络和 systemd
    echo "🔄 重启网络服务..."
    systemctl restart networking

    echo "🔄 重新加载 systemd 配置..."
    systemctl daemon-reload

    echo "🔄 启用并立即启动 mihomo-update.timer..."
    systemctl enable --now mihomo-update.timer

    echo "✅ 所有操作完成"

else
    echo "❌ 恢复失败，请检查压缩包是否完整"
    if [ "$IS_ENC" -eq 1 ]; then
        rm -f "$DECRYPTED_FILE"
    fi
    exit 1
fi
