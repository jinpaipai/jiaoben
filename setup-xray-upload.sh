#!/bin/bash
# bash <(curl -sL https://raw.githubusercontent.com/jinpaipai/jiaoben/refs/heads/main/setup-xray-upload.sh)
# =======================================================
# Xray 日志上传脚本安装/卸载器（增强版）
# =======================================================

UPLOAD_SCRIPT="/usr/local/bin/xray-log-upload.sh"
SERVICE_FILE="/etc/systemd/system/xray-log-upload.service"
TIMER_FILE="/etc/systemd/system/xray-log-upload.timer"

# =======================================================
# 选择模式：安装 或 卸载
# =======================================================
echo "请选择操作："
echo "1) 安装"
echo "2) 卸载"
read -rp "请输入数字 (1/2)： " ACTION

# =======================================================
# 卸载功能
# =======================================================
if [[ "$ACTION" == "2" ]]; then
    echo "===> 正在停止 timer 和 service ..."
    systemctl disable --now xray-log-upload.timer 2>/dev/null
    systemctl disable --now xray-log-upload.service 2>/dev/null

    echo "===> 删除上传脚本：$UPLOAD_SCRIPT"
    rm -f "$UPLOAD_SCRIPT"

    echo "===> 删除 systemd service：$SERVICE_FILE"
    rm -f "$SERVICE_FILE"

    echo "===> 删除 systemd timer：$TIMER_FILE"
    rm -f "$TIMER_FILE"

    echo "===> 重新加载 systemd ..."
    systemctl daemon-reload

    echo "==========================================================="
    echo "✔ Xray 日志上传功能已完全卸载！"
    echo "==========================================================="
    exit 0
fi

# =======================================================
# 以下为安装流程
# =======================================================

echo "===> 请输入远程服务器域名/IP（例如：www.baidu.com）："
read -r REMOTE_ADDR

echo "===> 请输入 SSH 端口（例如：12345）："
read -r PORT

echo "===> 请输入本台服务器名称（例如：server01）："
read -r SERVER_NAME

# ===============================
# 生成上传脚本
# ===============================
echo "===> 创建上传脚本：$UPLOAD_SCRIPT"

cat > "$UPLOAD_SCRIPT" <<EOF
#!/bin/bash

SERVER_NAME="$SERVER_NAME"
SRC_LOG="/usr/local/xray_log/xray.log"

REMOTE="root@$REMOTE_ADDR"
REMOTE_DIR="/srv/xray_logs"
PORT=$PORT
KEY="/root/.ssh/xray_sync"

TMP_COPY="/tmp/\${SERVER_NAME}.log"
TMP_ARCHIVE="/tmp/\${SERVER_NAME}-\$(date +%Y%m%d%H%M%S).tar.gz"

echo "===> 开始打包上传 Xray 日志 ..."

cp "\$SRC_LOG" "\$TMP_COPY"
tar -czf "\$TMP_ARCHIVE" -C "/tmp" "\$(basename "\$TMP_COPY")"

scp -P "\$PORT" -i "\$KEY" "\$TMP_ARCHIVE" "\$REMOTE:\$REMOTE_DIR/"

REMOTE_ARCHIVE="\$REMOTE_DIR/\$(basename "\$TMP_ARCHIVE")"
ssh -p "\$PORT" -i "\$KEY" "\$REMOTE" "
  tar -xzf '\$REMOTE_ARCHIVE' -C '\$REMOTE_DIR';
  rm -f '\$REMOTE_ARCHIVE';
"

rm -f "\$TMP_COPY"
rm -f "\$TMP_ARCHIVE"

echo "===> 完成上传并解压日志！"
EOF

chmod +x "$UPLOAD_SCRIPT"

# ===============================
# 创建 systemd service
# ===============================
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
