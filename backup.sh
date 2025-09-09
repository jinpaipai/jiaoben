#!/bin/bash
# backup.sh - 完整备份脚本（含 .deb 文件，无 _apt 警告）

# ----------------------------
# 确保 rsync 已安装
# ----------------------------
if ! command -v rsync >/dev/null 2>&1; then
    echo "⚠️ rsync 未安装，正在安装..."
    apt update
    apt install -y rsync
fi

BACKUP_DIR="/root/backup"
mkdir -p "$BACKUP_DIR"
LOG_FILE="$BACKUP_DIR/backup.log"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
ENCRYPTED_FILE="$BACKUP_FILE.gpg"

# ----------------------------
# 需要备份的文件和目录
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
# 排除目录
# ----------------------------
EXCLUDES=(
    "/root/nodepassdash/logs"
    "/root/ql/data/log"
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
# 日志
# ----------------------------
echo "===============================" >> "$LOG_FILE"
echo "备份开始：$(date)" >> "$LOG_FILE"

# ----------------------------
# 检查文件是否存在
# ----------------------------
EXISTING_FILES=()
for FILE in "${FILES_TO_BACKUP[@]}"; do
    if [ -e "$FILE" ]; then
        EXISTING_FILES+=("$FILE")
    else
        echo "警告：$FILE 不存在，已跳过" | tee -a "$LOG_FILE"
    fi
done

if [ ${#EXISTING_FILES[@]} -eq 0 ]; then
    echo "没有可打包的文件或文件夹，脚本退出" | tee -a "$LOG_FILE"
    exit 1
fi

# ----------------------------
# 创建临时打包目录
# ----------------------------
TMP_BACKUP_DIR="/tmp/backup_root_$TIMESTAMP"
mkdir -p "$TMP_BACKUP_DIR"

# 拷贝文件和目录
for f in "${EXISTING_FILES[@]}"; do
    BASENAME=$(basename "$f")
    DEST="$TMP_BACKUP_DIR/$BASENAME"
    if [ -d "$f" ]; then
        mkdir -p "$DEST"
        rsync -a "$f"/ "$DEST"/
    else
        cp -a "$f" "$DEST"
    fi
done

# ----------------------------
# 下载 deb 文件到 root 可写目录，彻底消除警告
# ----------------------------
DEB_DIR="$TMP_BACKUP_DIR/deb"
mkdir -p "$DEB_DIR"
cd "$DEB_DIR" || exit 1
echo "🔽 下载 aria2 和 qbittorrent-nox deb 文件..."
apt download aria2 qbittorrent-nox
cd -

# ----------------------------
# 打包整个临时目录，包括 deb 文件
# ----------------------------
echo "正在打包文件..." | tee -a "$LOG_FILE"
tar -czvf "$BACKUP_FILE" -C "$TMP_BACKUP_DIR" . >> "$LOG_FILE" 2>&1
rm -rf "$TMP_BACKUP_DIR"

# ----------------------------
# 验证备份完整性
# ----------------------------
tar -tzf "$BACKUP_FILE" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "备份验证通过 ✅" | tee -a "$LOG_FILE"
else
    echo "备份验证失败 ❌" | tee -a "$LOG_FILE"
    exit 1
fi

# ----------------------------
# 加密
# ----------------------------
echo "请输入加密密码："
gpg -c --batch --yes "$BACKUP_FILE"
if [ $? -eq 0 ]; then
    echo "备份已加密：$ENCRYPTED_FILE" | tee -a "$LOG_FILE"
    rm -f "$BACKUP_FILE"
else
    echo "加密失败 ❌" | tee -a "$LOG_FILE"
    exit 1
fi

# ----------------------------
# 备份轮转
# ----------------------------
MAX_BACKUPS=7
BACKUP_COUNT=$(ls -1t "$BACKUP_DIR"/backup_*.tar.gz.gpg 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    OLDEST_BACKUPS=$(ls -1t "$BACKUP_DIR"/backup_*.tar.gz.gpg | tail -n +$(($MAX_BACKUPS + 1)))
    rm -f $OLDEST_BACKUPS
fi

echo "备份结束：$(date)" >> "$LOG_FILE"
echo "===============================" >> "$LOG_FILE"
echo "✅ 备份完成：$ENCRYPTED_FILE"
