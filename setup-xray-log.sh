#!/bin/bash
# ======================================================
# 一键安装 xray 日志过滤脚本（稳定版）
# 功能：
#  - 过滤 UDP 流量
#  - 排除指定域名和本地 API 调用
#  - 日志大小超过 20MB 自动清空并写入时间戳
#  - cron 每分钟执行
# ======================================================

# ----------------------------
# 配置变量
# ----------------------------
SCRIPT_PATH="/usr/local/bin/xray-log-filter.sh"
DST_DIR="/usr/local/xray_log"
DST_LOG="$DST_DIR/xray.log"
SRC_LOG="/usr/local/x-ui/access.log"

# ----------------------------
# 创建脚本
# ----------------------------
echo "创建 xray 日志过滤脚本..."
sudo bash -c "cat > $SCRIPT_PATH << 'EOF'
#!/bin/bash

SRC_LOG=\"$SRC_LOG\"
DST_DIR=\"$DST_DIR\"
DST_LOG=\"$DST_LOG\"

# 使用 mktemp 创建临时文件，避免并发冲突
TMP_FILE=\$(mktemp /tmp/xray_tmp.XXXXXX)

mkdir -p \"\$DST_DIR\"

# 1️⃣ 排除 UDP 流量
grep -v 'accepted udp:' \"\$SRC_LOG\" > \"\$TMP_FILE\".step1

# 2️⃣ 排除指定域名和本地 API 调用
grep -v -E 'jinpaipai\.top|jinpaipai\.fun|paipaijin\.dpdns\.org|jinpaipai\.qzz\.io|xxxyun\.top|jueduibupao\.top|6bnw\.top|sssyun\.xyz|captive\.apple\.com|dns\.google|cloudflare-dns\.com|dns\.adguard\.com|doh\.opendns\.com|127\.0\.0\.1:.*\[api -> api\]|:22000' "$TMP_FILE".step1 > "$TMP_FILE".step2


# 3️⃣ 追加到目标日志
cat \"\$TMP_FILE\".step2 >> \"\$DST_LOG\"

# 删除临时文件
rm -f \"\$TMP_FILE\".step1 \"\$TMP_FILE\".step2

# 4️⃣ 控制日志大小（20MB），超过自动清空并写入时间戳
MAX_SIZE=\$((20 * 1024 * 1024))
if [ -f \"\$DST_LOG\" ]; then
    SIZE=\$(stat -c%s \"\$DST_LOG\")
    if [ \"\$SIZE\" -ge \"\$MAX_SIZE\" ]; then
        echo \"\$(date '+%Y-%m-%d %H:%M:%S') - 自动清理日志（超过 20MB）\" > \"\$DST_LOG\"
    fi
fi
EOF"

# ----------------------------
# 授权脚本可执行
# ----------------------------
echo "赋予脚本可执行权限..."
sudo chmod +x $SCRIPT_PATH

# ----------------------------
# 创建日志目录
# ----------------------------
mkdir -p "$DST_DIR"

# ----------------------------
# 配置 cron 任务
# ----------------------------
echo "配置 cron 定时任务..."

# 每分钟执行 xray 日志过滤
CRON_MINUTE="* * * * * \"$SCRIPT_PATH\" >/dev/null 2>&1 # xray-log-filter"

# 每5天清空日志
CRON_5DAY="0 0 */5 * * echo \"\$(date '+\%Y-\%m-\%d \%H:\%M:\%S') - 自动5天清理日志\" > \"$DST_LOG\" # xray-log-clean"

# 添加 cron 任务（去重）
CURRENT_CRON=$(crontab -l 2>/dev/null || true)

if ! grep -Fq "# xray-log-filter" <<< "$CURRENT_CRON"; then
    (echo "$CURRENT_CRON"; echo "$CRON_MINUTE") | crontab -
fi

CURRENT_CRON=$(crontab -l 2>/dev/null || true)
if ! grep -Fq "# xray-log-clean" <<< "$CURRENT_CRON"; then
    (echo "$CURRENT_CRON"; echo "$CRON_5DAY") | crontab -
fi

echo "✅ 设置完成！"
echo "脚本路径：$SCRIPT_PATH"
echo "日志目录：$DST_DIR"
echo "日志文件：$DST_LOG"
echo "日志过滤每分钟执行一次，大于20MB自动清空，每5天清空一次。"
