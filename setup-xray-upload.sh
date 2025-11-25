#!/bin/bash
# =======================================================
# Xray 日志上传脚本自动安装器（方案 A：静态副本压缩）
# =======================================================

UPLOAD_SCRIPT="/usr/local/bin/xray-log-upload.sh"

echo "===> 请输入远程服务器域名/IP（例如：www.baidu.com）："
read -r REMOTE_ADDR

echo "===> 请输入 SSH 端口（例如：12345）："
read -r PORT

echo "===> 请输入本台服务器名称（例如：server01）："
read -r SERVER_NAME

# ===============================
# 生成上传脚本（方案 A 已集成）
# ===============================
echo "===> 创建上传脚本：$UPLOAD_SCRIPT"

cat > "$UPLOAD_SCRIPT" <<EOF
#!/bin/bash

# 服务器名称
SERVER_NAME="$SERVER_NAME"

# 本地日志
SRC_LOG="/usr/local/xray_log/xray.log"

# 远程服务器
REMOTE="root@$REMOTE_ADDR"
REMOTE_DIR="/srv/xray_logs"
PORT=$PORT
KEY="/root/.ssh/xray_sync"

# 临时文件
TMP_ARCHIVE="/tmp/\${SERVER_NAME}-\$(date +%Y%m%d%H%M%S).tar.gz"
TMP_COPY="/tmp/xray_copy_\$\$.log"

echo "===> 开始打包上传 Xray 日志 ..."

# -----------------------------
# 创建本地静态副本（避免 tar 损坏）
# -----------------------------
echo "===> 复制日志为静态文件：\$TMP_COPY"
cp "\$SRC_LOG" "\$TMP_COPY"

# -----------------------------
# 压缩静态副本
# -----------------------------
echo "===> 压缩日志文件到 \$TMP_ARCHIVE ..."
tar -czf "\$TMP_ARCHIVE" -C "/tmp" "\$(basename "\$TMP_COPY")"

rm -f "\$TMP_COPY"

# -----------------------------
# 上传压缩包
# -----------------------------
echo "===> 上传日志压缩包到远程服务器 ..."
scp -P "\$PORT" -i "\$KEY" "\$TMP_ARCHIVE" "\$REMOTE:\$REMOTE_DIR/"

# -----------------------------
# 远程解压 & 自动识别文件名 & 改名
# -----------------------------
REMOTE_ARCHIVE="\$REMOTE_DIR/\$(basename "\$TMP_ARCHIVE")"

echo "===> 在远程服务器解压日志并改名为 \$SERVER_NAME.log ..."

ssh -p "\$PORT" -i "\$KEY" "\$REMOTE" "
  tar -xzf '\$REMOTE_ARCHIVE' -C '\$REMOTE_DIR' && \
  LOG_FILE=\$(ls '\$REMOTE_DIR' | grep xray_copy | head -n1) && \
  mv \"\$REMOTE_DIR/\$LOG_FILE\" \"\$REMOTE_DIR/\$SERVER_NAME.log\" && \
  rm -f '\$REMOTE_ARCHIVE'
"

# -----------------------------
# 本地清理
# -----------------------------
rm -f "\$TMP_ARCHIVE"

echo "===> 完成上传并解压日志！"

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
# 创建 systemd timer
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

echo "===> 重新加载 systemd..."
systemctl daemon-reload

echo "===> 启用定时器..."
systemctl enable --now xray-log-upload.timer

systemctl list-timers | grep xray-log-upload

echo "==========================================================="
echo "远程地址      : $REMOTE_ADDR"
echo "SSH 端口      : $PORT"
echo "服务器名称    : $SERVER_NAME"
echo "上传脚本路径  : $UPLOAD_SCRIPT"
echo "定时器        : xray-log-upload.timer（每小时执行）"
echo "==========================================================="
echo "安装完成！"
