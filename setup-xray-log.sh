#!/bin/bash
# bash <(curl -sL https://raw.githubusercontent.com/jinpaipai/jiaoben/refs/heads/main/setup-xray-log.sh)
# ======================================================
# 安装 / 卸载 Xray systemd 日志提取过滤 一键脚本
# ======================================================

SCRIPT_FILTER="/usr/local/bin/xray-log-filter.sh"
SCRIPT_CLEAN="/usr/local/bin/xray-log-clean.sh"
DST_DIR="/usr/local/xray_log"
DST_LOG="$DST_DIR/xray.log"

SERVICE_FILTER="/etc/systemd/system/xray-log-filter.service"
TIMER_FILTER="/etc/systemd/system/xray-log-filter.timer"
SERVICE_CLEAN="/etc/systemd/system/xray-log-clean.service"
TIMER_CLEAN="/etc/systemd/system/xray-log-clean.timer"

# ======================================================
# 选择操作
# ======================================================
echo "请选择操作："
echo "1) 安装"
echo "2) 卸载"
read -rp "请输入数字 (1/2): " ACTION

# ======================================================
# 卸载功能
# ======================================================
if [[ "$ACTION" == "2" ]]; then
    echo "===> 停止并禁用所有相关 systemd 服务与定时器..."

    systemctl disable --now xray-log-filter.timer 2>/dev/null
    systemctl disable --now xray-log-filter.service 2>/dev/null
    systemctl disable --now xray-log-clean.timer 2>/dev/null
    systemctl disable --now xray-log-clean.service 2>/dev/null

    echo "===> 删除脚本..."
    rm -f "$SCRIPT_FILTER"
    rm -f "$SCRIPT_CLEAN"

    echo "===> 删除 systemd 文件..."
    rm -f "$SERVICE_FILTER"
    rm -f "$TIMER_FILTER"
    rm -f "$SERVICE_CLEAN"
    rm -f "$TIMER_CLEAN"

    echo "===> 重新加载 systemd..."
    systemctl daemon-reload

    # 询问是否删除日志目录
    echo "是否删除日志目录 $DST_DIR ? (y/n)"
    read -r RM_DIR
    if [[ "$RM_DIR" == "y" ]]; then
        rm -rf "$DST_DIR"
        echo "已删除目录：$DST_DIR"
    fi

    echo "======================================================="
    echo "✔ 卸载完成！所有 xray 日志过滤与清理功能已移除。"
    echo "======================================================="
    exit 0
fi


# ======================================================
# 以下为安装流程
# ======================================================

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
grep -v -E 'www\.gstatic\.com|www\.apple\.com|accounts\.google\.com|wpad\.mshome\.net|stream-production\.avcdn\.net|inputsuggestions\.msdxcdn\.microsoft\.com|jinpaipai\.top|jinpaipai\.fun|paipaijin\.dpdns\.org|jinpaipai\.qzz\.io|xxxyun\.top|jueduibupao\.top|6bnw\.top|sssyun\.xyz|clawcloudrun\.com|captive\.apple\.com|dns\.google|cloudflare-dns\.com|dns\.adguard\.com|doh\.opendns\.com|www\.mathworks\.com|best\.cdn\.sqeven\.cn|bestcf\.top|idsduf\.com|whtjdasha\.com' \
    "$TMP_FILE".step1 > "$TMP_FILE".step2

# 3️⃣ 过滤目标端口 80 与 22000
grep -v -E 'tcp:.*:(80|22000)[[:space:]]' "$TMP_FILE".step2 > "$TMP_FILE".step3

# 4️⃣ 过滤本地 API 调用
grep -v -E '127\.0\.0\.1:[0-9]+.*\[api -> api\]' \
    "$TMP_FILE".step3 > "$TMP_FILE".step4

# 5️⃣ 排除目标地址为纯 IP
grep -v -E 'tcp:[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' \
    "$TMP_FILE".step4 > "$TMP_FILE".step5

cp "$TMP_FILE".step5 "$TMP_FILE".step_filtered

cat "$TMP_FILE".step_filtered >> "$DST_LOG"

rm -f "$TMP_FILE".step*

# 8️⃣ 控制日志大小
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
# 2. 创建 5 天清空日志的脚本
# ======================================================
echo "===> 创建清理脚本：$SCRIPT_CLEAN"

cat > "$SCRIPT_CLEAN" <<'EOF'
#!/bin/bash
DST_LOG="/usr/local/xray_log/xray.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - 自动5天清理日志" > "$DST_LOG"
EOF

chmod +x "$SCRIPT_CLEAN"

# ======================================================
# 3. 创建 systemd 服务/定时器
# ======================================================
echo "===> 创建 systemd: xray-log-filter.service & timer"

cat > "$SERVICE_FILTER" <<EOF
[Unit]
Description=Xray Log Filter Service
Wants=xray-log-filter.timer

[Service]
Type=oneshot
ExecStart=$SCRIPT_FILTER
EOF

cat > "$TIMER_FILTER" <<EOF
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
# 4. 每 5 天清理日志 timer
# ======================================================
echo "===> 创建 systemd: xray-log-clean.service & timer"

cat > "$SERVICE_CLEAN" <<EOF
[Unit]
Description=Xray Log Clean (5 Days)

[Service]
Type=oneshot
ExecStart=$SCRIPT_CLEAN
EOF

cat > "$TIMER_CLEAN" <<EOF
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

echo "===> 手动触发 clean 一次以激活 timer..."
systemctl start xray-log-clean.service

echo "===> 启用清理定时器..."
systemctl enable --now xray-log-clean.timer

echo "======================================================="
echo "安装完成！"
echo "日志过滤脚本：$SCRIPT_FILTER"
echo "日志清理脚本：$SCRIPT_CLEAN"
echo "日志文件：$DST_LOG"
echo "======================================================="
