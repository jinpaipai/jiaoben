#!/data/data/com.termux/files/usr/bin/bash
# update_mihomo_android_sub.sh - 修改 update_mihomo.sh 中的订阅链接并更新订阅，自动使用 root 重启 Mihomo

UPDATE_SCRIPT="$HOME/.shortcuts/tasks/update_mihomo.sh"
CONFIG_DIR="/data/clash"
TMP_FILE="$CONFIG_DIR/config.yaml.tmp"

# -----------------------------
# 自动提升权限
# -----------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "[INFO] 当前非 root，尝试使用 su 提升权限..."
    exec su -c "bash $0 $*"
    exit 0
fi

# -----------------------------
# 检查 update_mihomo.sh 是否存在
# -----------------------------
if [ ! -f "$UPDATE_SCRIPT" ]; then
    echo "[ERROR] 找不到 $UPDATE_SCRIPT，请先安装 Mihomo"
    exit 1
fi

# -----------------------------
# 交互输入新的订阅链接
# -----------------------------
read -p "请输入新的订阅链接: " NEW_SUB_LINK
if [ -z "$NEW_SUB_LINK" ]; then
    echo "[ERROR] 订阅链接不能为空"
    exit 1
fi

# -----------------------------
# 替换 update_mihomo.sh 中的 CONFIG_URL
# -----------------------------
sed -i "s|^CONFIG_URL=.*|CONFIG_URL=\"$NEW_SUB_LINK\"|" "$UPDATE_SCRIPT"
echo "[INFO] 已更新 $UPDATE_SCRIPT 中的订阅链接 ✅"

# -----------------------------
# 更新订阅配置
# -----------------------------
echo "[INFO] 开始更新订阅..."
if command -v curl >/dev/null 2>&1; 键，然后
    curl -L -k --fail -o "$TMP_FILE" "$NEW_SUB_LINK"
elif command -v wget >/dev/null 2>&1; 键，然后
    wget --no-check-certificate -O "$TMP_FILE" "$NEW_SUB_LINK"
else
    echo "[ERROR] 没有 curl 或 wget 可用，无法下载订阅"
    exit 1
fi

if [ -f "$TMP_FILE" ]; then
    mv "$TMP_FILE" "$CONFIG_DIR/config.yaml"
    sed -i 's/stack: system/stack: gvisor/' "$CONFIG_DIR/config.yaml"
    echo "[INFO] 配置已更新 ✅"
else
    echo "[ERROR] 下载失败 ❌ 保留旧配置"
    exit 1
fi

# -----------------------------
# 重启 Mihomo
# -----------------------------
if command -v killall >/dev/null 2>&1; then
    killall -9 mihomo 2>/dev/null
    nohup /data/clash/mihomo -d /data/clash/ >/dev/null 2>&1 &
    echo "[INFO] Mihomo 已重启 ✅"
else
    echo "[WARN] 未找到 killall 命令，请手动重启 Mihomo"
fi
