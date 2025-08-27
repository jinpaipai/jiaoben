#!/bin/bash

# 脚本：restore.sh
# 功能：自动恢复 /root/backup 中的最新备份文件
# 兼容：Debian 12

BACKUP_DIR="/root/backup"
LATEST_BACKUP=$(ls -1t $BACKUP_DIR/backup_*.tar.gz 2>/dev/null | head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ 没有找到备份文件，请确认 $BACKUP_DIR 中存在 backup_xxx.tar.gz"
    exit 1
fi

echo "准备恢复备份文件：$LATEST_BACKUP"

# 询问是否继续
read -p "是否继续恢复？这会覆盖已有文件 (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "已取消恢复"
    exit 0
fi

# 解压到根目录
tar -xzvf "$LATEST_BACKUP" -C /

if [ $? -eq 0 ]; then
    echo "✅ 恢复完成，数据已恢复到原始路径"
else
    echo "❌ 恢复失败，请检查压缩包是否完整"
    exit 1
fi
