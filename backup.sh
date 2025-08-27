#!/bin/bash

# 脚本：backup.sh
# 功能：将指定文件夹和文件打包到 /root/backup，并保留最近 7 个备份
# 兼容：Debian 12

# 设置备份目标路径
BACKUP_DIR="/root/backup"
mkdir -p "$BACKUP_DIR"  # 如果目录不存在，自动创建

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

# 指定需要打包的文件夹和文件
FILES_TO_BACKUP=(
    "/usr/local/alist"
    "/usr/local/frp"
    "/root/nodepassdash"
    "/root/ql"
    "/etc/sub-store"
    "/opt/vault-data"
    "/etc/filebrowser.db"
)

# 检查文件是否存在，忽略不存在的文件
EXISTING_FILES=()
for FILE 在 "${FILES_TO_BACKUP[@]}"; do
    if [ -e "$FILE" ]; then
        EXISTING_FILES+=("$FILE")
    else
        echo "警告：$FILE 不存在，已跳过"
    fi
done

# 执行打包
if [ ${#EXISTING_FILES[@]} -eq 0 ]; then
    echo "没有可打包的文件或文件夹，脚本退出"
    exit 1
fi

echo "正在打包文件..."
tar -czvf "$BACKUP_FILE" "${EXISTING_FILES[@]}"

if [ $? -eq 0 ]; then
    echo "备份完成，文件保存为：$BACKUP_FILE"
else
    echo "备份失败，请检查权限和路径"
    exit 1
fi

# ----------------------------
# 备份轮转：保留最近 7 个备份
# ----------------------------
MAX_BACKUPS=7
BACKUP_COUNT=$(ls -1t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | wc -l)

if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    # 删除最旧的备份
    OLDEST_BACKUPS=$(ls -1t "$BACKUP_DIR"/backup_*.tar.gz | tail -n +$(($MAX_BACKUPS + 1)))
    echo "删除旧备份文件："
    echo "$OLDEST_BACKUPS"
    rm -f $OLDEST_BACKUPS
fi
