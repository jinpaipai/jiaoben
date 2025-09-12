#!/bin/bash

# ----------------------------
# 设置备份目标路径
# ----------------------------
BACKUP_DIR="/root/backup"
mkdir -p "$BACKUP_DIR"
LOG_FILE="$BACKUP_DIR/backup.log"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

# ----------------------------
# 指定需要打包的文件夹和文件
# ----------------------------
FILES_TO_BACKUP=(
    "/root/.ssh"
    "/etc/aria2"
    "/root/AdGuardHome"
    "/usr/local/alist"
    "/usr/local/frp"
    "/root/nodepassdash"
    "/etc/nodepass"
    "/root/ql"
    "/etc/sub-store"
    "/opt/vault-data"
    "/opt/srs"
    "/usr/bin/filebrowser"
    "/etc/filebrowser.db"
    "/opt/nezha"
    "/opt/1panel"
    "/usr/local/bin/lang"
    "/usr/local/bin/1panel-agent"
    "/usr/local/bin/1panel-core"
    "/usr/local/bin/1pctl"
    "/usr/bin/1panel"
    "/usr/bin/1panel-agent"
    "/usr/bin/1panel-core"
    "/usr/bin/1pctl"
    "/root/zhengshu/"
    "/etc/localtime"
    "/usr/local/x-ui"
    "/usr/bin/x-ui"
    "/etc/x-ui/"
    "/usr/local/h-ui"
    "/etc/mihomo"
    "/usr/local/bin/mihomo"
    "/etc/sysctl.conf"
    "/root/.cloudflared"
    "/usr/local/bin/cloudflared"
    "/usr/bin/qbittorrent-nox"
    "$HOME/.config/qBittorrent"
    "/var/spool/cron/crontabs/root"
    "$HOME/.local/share/qBittorrent"
    "/usr/local/bin/mihomo_subupdate.sh"
    "/etc/systemd/system/mihomo-update.timer"
    "/lib/systemd/system/docker.socket"
    "/etc/systemd/system/nezha-dashboard.service"
    "/etc/systemd/system/nezha-agent.service"
    "/etc/systemd/system/cloudflared.service"
    "/etc/systemd/system/x-ui.service"
    "/etc/systemd/system/frpc.service"
    "/etc/systemd/system/frps.service"
    "/etc/systemd/system/qbittorrent-nox.service"
    "/etc/systemd/system/alist.service"
    "/etc/systemd/system/h-ui.service"
    "/etc/systemd/system/1panel-core.service"
    "/etc/systemd/system/1panel-agent.service"
    "/etc/systemd/system/filebrowser.service"
    "/etc/systemd/system/mihomo.service"
    "/etc/systemd/system/mihomo-update.service"
    "/etc/systemd/system/nodepass.service"
    "/etc/systemd/system/AdGuardHome.service"
    "/etc/systemd/system/aria2.service"
)

# ----------------------------
# 指定需要排除的目录
# ----------------------------
EXCLUDES=(
    "/opt/1panel/log"
    "/opt/1panel/tmp"
    "/opt/1panel/backup"
    "/opt/1panel/resource/apps/remote"
    "/opt/1panel/apps/openresty/openresty/log"
    "/opt/1panel/apps/openresty/openresty/build/tmp"
)

EXCLUDE_PARAMS=()
for e in "${EXCLUDES[@]}"; do
    EXCLUDE_PARAMS+=(--exclude="$e")
done

# ----------------------------
# 日志：备份开始
# ----------------------------
echo "===============================" >> "$LOG_FILE"
echo "备份开始：$(date)" >> "$LOG_FILE"

# ----------------------------
# 检查文件是否存在
# ----------------------------
EXISTING_FILES=()
for FILE 在 "${FILES_TO_BACKUP[@]}"; do
    if [ -e "$FILE" ]; then
        EXISTING_FILES+=("$FILE")
    else
        echo "警告：$FILE 不存在，已跳过" | tee -a "$LOG_FILE"
    fi
done

if [ ${#EXISTING_FILES[@]} -eq 0 ]; 键，然后
    echo "没有可打包的文件或文件夹，脚本退出" | tee -a "$LOG_FILE"
    exit 1
fi

# ----------------------------
# 执行打包
# ----------------------------
echo "正在打包文件..." | tee -a "$LOG_FILE"
tar -czvf "$BACKUP_FILE" "${EXCLUDE_PARAMS[@]}" "${EXISTING_FILES[@]}" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    echo "备份失败，请检查权限和路径" | tee -a "$LOG_FILE"
    exit 1
fi

# ----------------------------
# 验证备份完整性
# ----------------------------
echo "验证备份完整性..." | tee -a "$LOG_FILE"
tar -tzf "$BACKUP_FILE" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "备份验证通过 ✅" | tee -a "$LOG_FILE"
else
    echo "备份验证失败 ❌" | tee -a "$LOG_FILE"
    exit 1
fi

# ----------------------------
# 显示备份大小
# ----------------------------
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "备份完成：$BACKUP_FILE，大小：$BACKUP_SIZE" | tee -a "$LOG_FILE"

# ----------------------------
# 备份轮转：保留最近 3 个备份
# ----------------------------
MAX_BACKUPS=3
BACKUP_COUNT=$(ls -1t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | wc -l)

if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    OLDEST_BACKUPS=$(ls -1t "$BACKUP_DIR"/backup_*.tar.gz | tail -n +$(($MAX_BACKUPS + 1)))
    echo "删除旧备份文件：" | tee -a "$LOG_FILE"
    echo "$OLDEST_BACKUPS" | tee -a "$LOG_FILE"
    rm -f $OLDEST_BACKUPS
fi

# ----------------------------
# 日志：备份结束
# ----------------------------
echo "备份结束：$(date)" >> "$LOG_FILE"
echo "===============================" >> "$LOG_FILE"
