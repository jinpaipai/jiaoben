#!/bin/bash
# ======================================================
# 一键安装 xray 日志过滤脚本（稳定版）
# 支持屏蔽 UDP 流量、指定泛域名、API 调用
# ======================================================

# 定义变量
SCRIPT_PATH="/usr/local/bin/xray-log-filter.sh"
DST_DIR="/usr/local/xray_log"
DST_LOG="$DST_DIR/xray.log"
SRC_LOG="/usr/local/x-ui/access.log"

# 1️⃣ 创建日志过滤脚本
echo "创建 xray 日志过滤脚本..."
sudo bash -c "cat > $SCRIPT_PATH << 'EOF'
#!/bin/bash

SRC_LOG=\"$SRC_LOG\"
DST_DIR=\"$DST_DIR\"
DST_LOG=\"$DST_LOG\"
TMP_FILE=\"/tmp/xray_tmp.log\"

# 创建目标目录
mkdir -p \"\$DST_DIR\"

# 1. 排除系统流量
grep 'email:'

# 1. 排除 UDP 流量
grep -v 'accepted udp:' \"\$SRC_LOG\" > \"\$TMP_FILE\".step1

# 2. 排除指定域名和本地 API 调用
grep -v -E '(\.|^)xxxyun\.top|(\.|^)jueduibupao\.top|(\.|^)6bnw\.top|(\.|^)sssyun\.xyz|captive\.apple\.com|dns\.google|cloudflare-dns\.com|dns\.adguard\.com|doh\.opendns\.com|127\.0\.0\.1:.*\[api -> api\]' \"\$TMP_FILE\".step1 > \"\$TMP_FILE\".step2

# 3. 追加到目标日志
cat \"\$TMP_FILE\".step2 >> \"\$DST_LOG\"

# 删除临时文件
rm -f \"\$TMP_FILE\".step1 \"\$TMP_FILE\".step2

# 4. 控制日志大小，大于 20MB 自动清空
MAX_SIZE=\$((20 * 1024 * 1024))
if [ -f \"\$DST_LOG\" ]; then
    SIZE=\$(stat -c%s \"\$DST_LOG\")
    if [ \"\$SIZE\" -ge \"\$MAX_SIZE\" ]; then
        echo \"\" > \"\$DST_LOG\"
        echo \"\$(date '+%Y-%m-%d %H:%M:%S') - 自动清理日志（超过 20MB）\" >> \"\$DST_LOG\"
    fi
fi
EOF"

# 2️⃣ 赋予可执行权限
echo "赋予脚本可执行权限..."
sudo chmod +x $SCRIPT_PATH

# 3️⃣ 创建日志目录（防止未创建）
mkdir -p "$DST_DIR"

# 4️⃣ 配置去重 cron 定时任务
echo "配置 cron 定时任务（去重）..."
CURRENT_CRON=$(crontab -l 2>/dev/null)
TASK_MINUTE="* * * * * $SCRIPT_PATH >/dev/null 2>&1"
TASK_5DAY="0 0 */5 * * echo \"\" > $DST_LOG"

# 添加每分钟任务
if ! grep -Fq "$TASK_MINUTE" <<< "$CURRENT_CRON"; then
    (echo "$CURRENT_CRON"; echo "$TASK_MINUTE") | crontab -
fi

# 添加每5天清理任务
CURRENT_CRON=$(crontab -l 2>/dev/null)
if ! grep -Fq "$TASK_5DAY" <<< "$CURRENT_CRON"; then
    (echo "$CURRENT_CRON"; echo "$TASK_5DAY") | crontab -
fi

echo "✅ 设置完成！"
echo "脚本路径：$SCRIPT_PATH"
echo "日志目录：$DST_DIR"
echo "日志文件：$DST_LOG"
echo "日志过滤每分钟执行一次，大于20MB自动清空，每5天清空一次。"
