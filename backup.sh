#!/bin/bash

echo "=== Installing backup script & systemd timer ==="

BACKUP_DIR="/root/backup"
mkdir -p "$BACKUP_DIR"
LOG_FILE="$BACKUP_DIR/backup.log"
PWD_FILE="$BACKUP_DIR/.backup_gpg_pass"

# ----------------------------
# First-time password input
# ----------------------------
if [ ! -f "$PWD_FILE" ]; then
    echo -n "Enter encryption password (it will be saved locally for automation): "
    read -s BACKUP_PWD
    echo
    echo "$BACKUP_PWD" > "$PWD_FILE"
    chmod 600 "$PWD_FILE"
    echo "✅ Password saved for automated backups."
else
    BACKUP_PWD=$(cat "$PWD_FILE")
fi

# ----------------------------
# Write backup script
# ----------------------------
cat >/usr/local/bin/backup.sh <<EOF
#!/bin/bash

BACKUP_DIR="$BACKUP_DIR"
LOG_FILE="$LOG_FILE"
PWD_FILE="$PWD_FILE"

BACKUP_PWD=\$(cat "\$PWD_FILE")
TIMESTAMP=\$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="\$BACKUP_DIR/backup_\$TIMESTAMP.tar.gz"
ENCRYPTED_FILE="\$BACKUP_FILE.gpg"

# ----------------------------
# Limit log size
# ----------------------------
MAX_LOG_SIZE=\$((10 * 1024 * 1024))
if [ -f "\$LOG_FILE" ]; then
    LOG_SIZE=\$(stat -c%s "\$LOG_FILE" 2>/dev/null || echo 0)
    if [ "\$LOG_SIZE" -ge "\$MAX_LOG_SIZE" ]; then
        echo "\$(date) Log exceeded 10MB, truncating..." > "\$LOG_FILE"
    fi
fi

# ----------------------------
# Files and directories
# ----------------------------
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
    "\$HOME/.config/qBittorrent"
    "/var/spool/cron/crontabs/root"
    "\$HOME/.local/share/qBittorrent"
    "/etc/systemd/system/s-ui.service"
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

EXCLUDES=(
    "/opt/1panel/log"
    "/opt/1panel/tmp"
    "/opt/1panel/backup"
    "/opt/1panel/resource/apps/remote"
    "/opt/1panel/apps/openresty/openresty/log"
    "/opt/1panel/apps/openresty/openresty/build/tmp"
)

EXCLUDE_PARAMS=()
for e in "\${EXCLUDES[@]}"; do
    EXCLUDE_PARAMS+=(--exclude="\$e")
done

# ----------------------------
# Start backup
# ----------------------------
echo "===============================" >> "\$LOG_FILE"
echo "Backup start: \$(date)" >> "\$LOG_FILE"

EXISTING_FILES=()
for FILE in "\${FILES_TO_BACKUP[@]}"; do
    if [ -e "\$FILE" ]; then
        EXISTING_FILES+=("\$FILE")
    else
        echo "Warning: \$FILE does not exist, skipped" | tee -a "\$LOG_FILE"
    fi
done

if [ \${#EXISTING_FILES[@]} -eq 0 ]; then
    echo "No files to backup, exiting..." | tee -a "\$LOG_FILE"
    exit 1
fi

echo "Backing up files..." | tee -a "\$LOG_FILE"
# ----------------------------
# Add --ignore-failed-read to avoid tar exit on missing files
# ----------------------------
tar --ignore-failed-read -czvf "\$BACKUP_FILE" "\${EXCLUDE_PARAMS[@]}" "\${EXISTING_FILES[@]}" >> "\$LOG_FILE" 2>&1
if [ \$? -ne 0 ]; then
    echo "Backup failed (tar errors ignored, continuing with encryption)" | tee -a "\$LOG_FILE"
fi

# ----------------------------
# Verify backup
# ----------------------------
tar -tzf "\$BACKUP_FILE" > /dev/null 2>&1
if [ \$? -ne 0 ]; then
    echo "Backup verification failed" | tee -a "\$LOG_FILE"
    exit 1
fi

# ----------------------------
# Encrypt backup
# ----------------------------
gpg --batch --yes --passphrase "\$BACKUP_PWD" --symmetric --cipher-algo AES256 "\$BACKUP_FILE"
if [ \$? -ne 0 ]; then
    echo "Encryption failed" | tee -a "\$LOG_FILE"
    exit 1
fi
rm -f "\$BACKUP_FILE"
BACKUP_FILE="\$ENCRYPTED_FILE"

# ----------------------------
# Rotation: keep last 3 encrypted backups
# ----------------------------
MAX_BACKUPS=3
BACKUP_COUNT=\$(ls -1t "\$BACKUP_DIR"/backup_*.tar.gz.gpg 2>/dev/null | wc -l)
if [ "\$BACKUP_COUNT" -gt "\$MAX_BACKUPS" ]; then
    OLDEST_BACKUPS=\$(ls -1t "\$BACKUP_DIR"/backup_*.tar.gz.gpg | tail -n +\$((MAX_BACKUPS + 1)))
    echo "Deleting old backups:" | tee -a "\$LOG_FILE"
    echo "\$OLDEST_BACKUPS" | tee -a "\$LOG_FILE"
    rm -f \$OLDEST_BACKUPS
fi

echo "Backup completed: \$BACKUP_FILE, size: \$(du -h "\$BACKUP_FILE" | cut -f1)" | tee -a "\$LOG_FILE"
echo "Backup end: \$(date)" >> "\$LOG_FILE"
echo "===============================" >> "\$LOG_FILE"
EOF

chmod +x /usr/local/bin/backup.sh

# ----------------------------
# Write systemd service
# ----------------------------
cat >/etc/systemd/system/backup.service <<'EOF'
[Unit]
Description=Run system backup script
[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
EOF

cat >/etc/systemd/system/backup.timer <<'EOF'
[Unit]
Description=Daily backup at 02:00
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now backup.timer

echo "=== Backup system installed successfully ==="
systemctl status backup.timer --no-pager
