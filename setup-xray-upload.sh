#!/bin/bash

# 用户自定义服务器名（每台服务器不同）
SERVER_NAME="SERVER_NAME_PLACEHOLDER"

# 本地日志路径
SRC_LOG="/usr/local/xray_log/xray.log"

# 远程服务器地址
REMOTE="root@REMOTE_ADDR_PLACEHOLDER"
REMOTE_DIR="/srv/xray_logs"
PORT=PORT_PLACEHOLDER
KEY="/root/.ssh/xray_sync"

# 临时文件
TMP_ARCHIVE="/tmp/${SERVER_NAME}-$(date +%Y%m%d%H%M%S).tar.gz"
TMP_COPY="/tmp/xray_copy_$$.log"

echo "===> 开始打包上传 Xray 日志 ..."

# -----------------------------
# 创建本地静态副本（避免文件变化导致 tar 损坏）
# -----------------------------
echo "===> 复制日志为静态文件：$TMP_COPY"
cp "$SRC_LOG" "$TMP_COPY"

# -----------------------------
# 压缩静态文件
# -----------------------------
echo "===> 压缩日志文件到 $TMP_ARCHIVE ..."
tar -czf "$TMP_ARCHIVE" -C "/tmp" "$(basename "$TMP_COPY")"

# 删除静态副本
rm -f "$TMP_COPY"

# -----------------------------
# 上传压缩包
# -----------------------------
echo "===> 上传日志压缩包到远程服务器 ..."
scp -P "$PORT" -i "$KEY" "$TMP_ARCHIVE" "$REMOTE:$REMOTE_DIR/"

# -----------------------------
# 远程解压 & 改名
# -----------------------------
REMOTE_ARCHIVE="$REMOTE_DIR/$(basename "$TMP_ARCHIVE")"

echo "===> 在远程服务器解压日志并改名为 $SERVER_NAME.log ..."
ssh -p "$PORT" -i "$KEY" "$REMOTE" "
  tar -xzf '$REMOTE_ARCHIVE' -C '$REMOTE_DIR' && \
  LOG_FILE=\$(ls '$REMOTE_DIR' | grep xray_copy | head -n1) && \
  mv \"$REMOTE_DIR/\$LOG_FILE\" \"$REMOTE_DIR/$SERVER_NAME.log\" && \
  rm -f '$REMOTE_ARCHIVE'
"

# -----------------------------
# 本地清理
# -----------------------------
rm -f "$TMP_ARCHIVE"

echo "===> 完成上传并解压日志！"
