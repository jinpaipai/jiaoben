#!/bin/bash
#bash -c "$(curl -fsSL https://raw.githubusercontent.com/jinpaipai/jiaoben/refs/heads/main/backup.sh)"

set -e

echo "=== Installing backup script & systemd timer ==="

# ----------------------------
# 1. Write /usr/local/bin/backup.sh
# ----------------------------
cat >/usr/local/bin/backup.sh <<'EOF'
#!/bin/bash

BACKUP_DIR="/root/backup"
mkdir -p "$BACKUP_DIR"

LOG_FILE="$BACKUP_DIR/backup.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

FILES_TO_BACKUP=(
    "/alist"
    "/root/.ssh"
    "/etc/aria2"
    "/usr/local/s-ui/"
    "/usr/bin/s-ui"
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
    "/usr/local/sync"
    "/opt/pansou/"
    "/usr/local/python"
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
)

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

{
echo "==============================="
echo "Backup start: $(date)"

EXISTING_FILES=()
for FILE in "${FILES_TO_BACKUP[@]}"; do
    if [ -e "$FILE" ]; then
        EXISTING_FILES+=("$FILE")
    else
        echo "Warning: $FILE does not exist, skipped"
    fi
done

if [ ${#EXISTING_FILES[@]} -eq 0 ]; then
    echo "No files to backup, exiting."
    exit 1
fi

echo "Creating archive..."
tar -czf "$BACKUP_FILE" "${EXCLUDE_PARAMS[@]}" "${EXISTING_FILES[@]}"

echo "Verifying archive..."
tar -tzf "$BACKUP_FILE" >/dev/null

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "Backup completed: $BACKUP_FILE ($BACKUP_SIZE)"

# keep last 3 backups
ls -1t "$BACKUP_DIR"/backup_*.tar.gz | tail -n +4 | xargs -r rm -f

echo "Backup end: $(date)"
echo "==============================="
} >>"$LOG_FILE" 2>&1
EOF

chmod +x /usr/local/bin/backup.sh

# ----------------------------
# 2. systemd service
# ----------------------------
cat >/etc/systemd/system/backup.service <<'EOF'
[Unit]
Description=Run system backup script

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
EOF

# ----------------------------
# 3. systemd timer
# ----------------------------
cat >/etc/systemd/system/backup.timer <<'EOF'
[Unit]
Description=Daily backup at 02:00

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ----------------------------
# 4. logrotate config
# ----------------------------
cat >/etc/logrotate.d/backup <<'EOF'
/root/backup/backup.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

# ----------------------------
# 5. enable
# ----------------------------
systemctl daemon-reload
systemctl enable --now backup.timer

echo "=== Backup system installed successfully ==="
systemctl status backup.timer --no-pager
