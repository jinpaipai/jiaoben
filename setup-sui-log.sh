#!/bin/bash
# ======================================================
# 安装 / 卸载 SUI systemd 日志提取过滤 一键脚本
# ======================================================

SCRIPT_FILTER="/usr/local/bin/sui-log-filter.sh"
SCRIPT_CLEAN="/usr/local/bin/sui-log-clean.sh"
DST_DIR="/usr/local/sui_log"
DST_LOG="$DST_DIR/sui.log"

SERVICE_FILTER="/etc/systemd/system/sui-log-filter.service"
TIMER_FILTER="/etc/systemd/system/sui-log-filter.timer"
SERVICE_CLEAN="/etc/systemd/system/sui-log-clean.service"
TIMER_CLEAN="/etc/systemd/system/sui-log-clean.timer"

# SUI 日志来源（你要求修正的路径）
SUI_LOG="/usr/local/s-ui/log/sui.log"

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
    echo "===> 停止并禁用 systemd 服务与定时器..."

    systemctl disable --now sui-log-filter.timer 2>/dev/null
    systemctl disable --now sui-log-filter.service 2>/dev/null
    systemctl disable --now sui-log-clean.timer 2>/dev/null
    systemctl disable --now sui-log-clean.service 2>/dev/null

    echo "===> 删除脚本..."
    rm -f "$SCRIPT_FILTER" "$SCRIPT_CLEAN"

    echo "===> 删除 systemd 文件..."
    rm -f "$SERVICE_FILTER" "$TIMER_FILTER" "$SERVICE_CLEAN" "$TIMER_CLEAN"

    echo "===> 重新加载 systemd..."
    systemctl daemon-reload

    echo "是否删除日志目录 $DST_DIR ? (y/n)"
    read -r RM_DIR
    if [[ "$RM_DIR" == "y" ]]; then
        rm -rf "$DST_DIR"
        echo "已删除目录：$DST_DIR"
    fi

    echo "======================================================="
    echo "✔ 卸载完成！SUI 日志过滤已移除。"
    echo "======================================================="
    exit 0
fi


# ======================================================
# 以下为安装流程
# ======================================================

echo "===> 创建 SUI 日志目录..."
mkdir -p "$DST_DIR"

# ======================================================
# 1. 创建过滤脚本
# ======================================================
echo "===> 创建过滤脚本：$SCRIPT_FILTER"

cat > "$SCRIPT_FILTER" <<EOF
#!/bin/bash

SRC_LOG="$SUI_LOG"
DST_DIR="/usr/local/sui_log"
DST_LOG="$DST_DIR/sui.log"

TMP=\$(mktemp /tmp/sui_tmp.XXXXXX)

mkdir -p "\$DST_DIR"

# 0️⃣ 去重同一条重复日志
awk '!seen[\$0]++' "\$SRC_LOG" > "\$TMP".step0

# 1️⃣ 过滤 Cloudflare / Google routine
grep -v -E 'cloudflare|gstatic|google|akamai|apple' "\$TMP".step0 > "\$TMP".step1

# 2️⃣ netlink 噪音
grep -v 'netlink' "\$TMP".step1 > "\$TMP".step2

# 3️⃣ DNS 查询噪音
grep -v -E 'query\[A\]|query\[AAAA\]|DNS' "\$TMP".step2 > "\$TMP".step3

# 4️⃣ inbound 噪音
grep -v -E 'inbound connection|accepted tcp:' "\$TMP".step3 > "\$TMP".step4

# 5️⃣ 过滤端口 80 / 22000
grep -v -E 'tcp:.*:(80|22000)[[:space:]]' "\$TMP".step4 > "\$TMP".step5

# 6️⃣ 排除指定域名
grep -v -E 'www\.gstatic\.com|www\.apple\.com|accounts\.google\.com|wpad\.mshome\.net|stream-production\.avcdn\.net|inputsuggestions\.msdxcdn\.microsoft\.com|jinpaipai\.top|jinpaipai\.fun|paipaijin\.dpdns\.org|jinpaipai\.qzz\.io|xxxyun\.top|jueduibupao\.top|6bnw\.top|sssyun\.xyz|clawcloudrun\.com|captive\.apple\.com|dns\.google|cloudflare-dns\.com|dns\.adguard\.com|doh\.opendns\.com|www\.mathworks\.com|best\.cdn\.sqeven\.cn|bestcf\.top|idsduf\.com|whtjdasha\.com' "\$TMP".step5 > "\$TMP".step6

# 7️⃣ 排除只有 IP 的目标连接
grep -v -E 'tcp:[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' "\$TMP".step6 > "\$TMP".step7

# 8️⃣ 写入
cat "\$TMP".step7 >> "\$DST_LOG"

rm -f "\$TMP".step*
EOF

chmod +x "$SCRIPT_FILTER"


# ======================================================
# 2. 清理日志脚本
# ======================================================
echo "===> 创建清理脚本：$SCRIPT_CLEAN"

cat > "$SCRIPT_CLEAN" <<'EOF'
#!/bin/bash
DST_LOG="/usr/local/sui_log/sui.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - 自动5天清理日志" > "$DST_LOG"
EOF

chmod +x "$SCRIPT_CLEAN"


# ======================================================
# 3. systemd 服务 / timer
# ======================================================
echo "===> 创建 systemd: sui-log-filter.service & timer"

cat > "$SERVICE_FILTER" <<EOF
[Unit]
Description=SUI Log Filter Service
Wants=sui-log-filter.timer

[Service]
Type=oneshot
ExecStart=$SCRIPT_FILTER
EOF

cat > "$TIMER_FILTER" <<EOF
[Unit]
Description=Run SUI Log Filter every minute

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=10s
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ======================================================
# 4. 5天清理日志
# ======================================================
echo "===> 创建 systemd: sui-log-clean.service & timer"

cat > "$SERVICE_CLEAN" <<EOF
[Unit]
Description=SUI Log Clean (every 5 天之前)

[Service]
Type=oneshot
ExecStart=$SCRIPT_CLEAN
EOF

cat > "$TIMER_CLEAN" <<EOF
[Unit]
Description=Run SUI Log Clean every 5 天之前

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

echo "===> 启动过滤定时器..."
systemctl enable --now sui-log-filter.timer

echo "===> 手动执行一次 Clean..."
systemctl start sui-log-clean.service

echo "===> 启用清理定时器..."
systemctl enable --now sui-log-clean.timer

echo "======================================================="
echo "✔ 安装完成 | SUI 日志过滤已启用"
echo "日志文件：$DST_LOG"
echo "======================================================="
