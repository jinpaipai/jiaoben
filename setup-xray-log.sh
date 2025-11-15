#!/bin/bash
# ======================================================
# 一键安装 xray systemd 日志过滤 + 定期清理服务
# ======================================================

SCRIPT_FILTER="/usr/local/bin/xray-log-filter.sh"
SCRIPT_CLEAN="/usr/local/bin/xray-log-clean.sh"
DST_DIR="/usr/local/xray_log"
DST_LOG="$DST_DIR/xray.log"
SRC_LOG="/usr/local/x-ui/access.log"

echo "===> 创建 xray 日志目录..."
mkdir -p "$DST_DIR"

# ======================================================
# 1. 创建每分钟执行的过滤脚本
# ======================================================
echo "===> 创建过滤脚本：$SCRIPT_FILTER"

cat > "$SCRIPT_FILTER" <<'EOF'
#!/bin/bash

SRC_LOG="/usr/local/x-ui/access.log"
DST_DIR="/usr/local/xray_log"
DST_LOG="$DST_DIR/xray.log"

TMP_FILE=$(mktemp /tmp/xray_tmp.XXXXXX)

mkdir -p "$DST_DIR"

# 1️⃣ 排除 UDP 流量
grep -v 'accepted udp:' "$SRC_LOG" > "$TMP_FILE".step1

# 2️⃣ 排除指定域名
grep -v -E 'www\.gstatic\.com|www\.apple\.com|accounts\.google\.com|wpad\.mshome\.net|stream-production\.avcdn\.net|inputsuggestions\.msdxcdn\.microsoft\.com|jinpaipai\.top|jinpaipai\.fun|paipaijin\.dpdns\.org|jinpaipai\.qzz\.io|xxxyun\.top|jueduibupao\.top|6bnw\.top|sssyun\.xyz|captive\.apple\.com|dns\.google|cloudflare-dns\.com|dns\.adguard\.com|doh\.opendns\.com|www\.mathworks\.com' \
    "$TMP_FILE".step1 > "$TMP_FILE".step_domain

# 3️⃣ 过滤本地 API 调用
grep -v -E '127\.0\.0\.1:[0-9]+.*\[api -> api\]' \
    "$TMP_FILE".step_domain > "$TMP_FILE".step_api

# 4️⃣ 过滤端口 22000
grep -v ':22000' "$TMP_FILE".step_api > "$TMP_FILE".step2

# 5️⃣ 追加到目标日志
cat "$TMP_FILE".step2 >> "$DST_LOG"

rm -f "$TMP_FILE".step*

# 6️⃣ 控制日志大小（200MB 自动清空）
MAX_SIZE=$((200 * 1024 * 1024))
if [ -f "$DST_LOG" ]; then
    SIZE=$(stat -c%s "$DST_LOG")
    if [ "$SIZE" -ge "$MAX_SIZE" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 自动清理日志（超过 200MB）" > "$DST_LOG"
    fi
fi
EOF

chmod +x "$SCRIPT_FILTER"

# ======================================================
# 2. 创建每 5 天清空日志的脚本
# ======================================================
echo "===> 创建 5 天清理脚本：$SCRIPT_CLEAN"

cat > "$SCRIPT_CLEAN" <<'EOF'
#!/bin/bash
DST_LOG="/usr/local/xray_log/xray.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - 自动5天清理日志" > "$DST_LOG"
EOF

chmod +x "$SCRIPT_CLEAN"

# ======================================================
# 3. 创建 systemd 服务与 timer（每分钟）
# ======================================================
echo "===> 创建 systemd: xray-log-filter.service & timer"

cat > /etc/systemd/system/xray-log-filter.service <<EOF
[Unit]
Description=Xray Log Filter Service
Wants=xray-log-filter.timer

[Service]
Type=oneshot
ExecStart=$SCRIPT_FILTER
EOF

cat > /etc/systemd/system/xray-log-filter.timer <<EOF
[Unit]
Description=Run Xray Log Filter every minute

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=10s
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ======================================================
# 4. 创建 systemd 服务与 timer（每 5 天）
# ======================================================
echo "===> 创建 systemd: xray-log-clean.service & timer"

cat > /etc/systemd/system/xray-log-clean.service <<EOF
[Unit]
Description=Xray Log Clean (5 Days)

[Service]
Type=oneshot
ExecStart=$SCRIPT_CLEAN
EOF

cat > /etc/systemd/system/xray-log-clean.timer <<EOF
[Unit]
Description=Run Xray Log Clean every 5 days

[Timer]
OnUnitActiveSec=5d
AccuracySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ======================================================
# 5. 启动 systemd
# ======================================================
echo "===> 重新加载 systemd..."
systemctl daemon-reload

echo "===> 启动并启用过滤定时器..."
systemctl enable --now xray-log-filter.timer

echo "===> 手动启动一次 clean 服务以激活 timer..."
systemctl start xray-log-clean.service

echo "===> 启动并启用清理定时器..."
systemctl enable --now xray-log-clean.timer

echo "===> 查看生效的定时器..."
systemctl list-timers | grep xray

echo "======================================================="
echo "安装完成！"
echo "日志过滤脚本：$SCRIPT_FILTER"
echo "日志清理脚本：$SCRIPT_CLEAN"
echo "日志文件：$DST_LOG"
echo "======================================================="
