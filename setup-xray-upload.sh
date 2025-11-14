#!/bin/bash
# =======================================================
# 交互式创建 xray-log-upload.sh + systemd 定时器（每小时）
# =======================================================

UPLOAD_SCRIPT="/usr/local/bin/xray-log-upload.sh"

echo "===> 请输入远程服务器域名/IP（例如：www.baidu.com）："
read -r REMOTE_ADDR

echo "===> 请输入 SSH 端口（例如：12345）："
read -r PORT

# ===============================
# 生成上传脚本
# ===============================
echo "===> 创建上传脚本：$UPLOAD_SCRIPT"

cat > "$UPLOAD_SCRIPT" <<EOF
#!/bin/bash

# 用户自定义服务器名（每台服务器不同即可）
SERVER_NAME="server01"   # ← 可自行修改

# 本地日志
SRC_LOG="/usr/local/xray_log/xray.log"

# 远程服务器（root@ 固定，域名/IP 由用户输入）
REMOTE="root@$REMOTE_ADDR"
REMOTE_DIR="/srv/xray_logs"
PORT=$PORT
KEY="/root/.ssh/xray_sync"

# 上传日志
scp -P \$PORT -i \$KEY "\$SRC_LOG" "\$REMOTE:\$REMOTE_DIR/\$SERVER_NAME.log"
EOF

chmod +x "$UPLOAD_SCRIPT"


# ===============================
# 创建 systemd service
# ===============================
SERVICE_FILE="/etc/systemd/system/xray-log-upload.service"

echo "===> 创建 systemd 服务：$SERVICE_FILE"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Upload Xray Log to Central Server

[Service]
Type=oneshot
ExecStart=$UPLOAD_SCRIPT
EOF


# ===============================
# 创建 systemd timer（每小时执行）
# ===============================
TIMER_FILE="/etc/systemd/system/xray-log-upload.timer"

echo "===> 创建 systemd 定时器：$TIMER_FILE"

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run Xray Log Upload Every Hour

[Timer]
OnCalendar=*-*-* *:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF


# ===============================
# 启动 systemd
# ===============================
echo "===> 重新加载 systemd..."
systemctl daemon-reload

echo "===> 启用定时器（每小时上传一次）..."
systemctl enable --now xray-log-upload.timer

echo "===> 完成！查看定时器："
systemctl list-timers | grep xray-log-upload

echo "==========================================================="
echo "远程地址      : $REMOTE_ADDR"
echo "SSH 端口      : $PORT"
echo "上传脚本路径  : $UPLOAD_SCRIPT"
echo "定时器        : xray-log-upload.timer（每小时执行）"
echo "==========================================================="
