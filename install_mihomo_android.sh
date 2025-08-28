#!/data/data/com.termux/files/usr/bin/bash
# install_mihomo_android.sh - 自动安装/更新 Mihomo 并配置快捷脚本
# 使用 GitHub 镜像: https://github.jinpaipai.fun

set -e

# GitHub 镜像前缀
MIRROR="https://github.jinpaipai.fun/https://github.com"
REPO="MetaCubeX/mihomo"
INSTALL_DIR="/data/clash"
TASK_DIR="$HOME/.shortcuts/tasks"

# 检测系统架构
ARCH=$(uname -m)
case "$ARCH" in
    aarch64)   FILE_KEY="android-arm64" ;;
    armv7l)    FILE_KEY="android-armv7" ;;
    x86_64)    FILE_KEY="android-amd64" ;;
    i*86)      FILE_KEY="android-386" ;;
    *) echo "❌ 未知架构: $ARCH"; exit 1 ;;
esac

echo "[INFO] 检测到架构: $ARCH -> $FILE_KEY"

# 获取最新 release tag（兼容 Termux）
TAG=$(curl -sL "$MIRROR/$REPO/releases/latest" | grep -o 'releases/tag/[^"]*' | sed 's#.*/##' | head -n1)
if [ -z "$TAG" ]; then
    echo "❌ 获取最新版本失败"; exit 1
fi
echo "[INFO] 最新版本: $TAG"

# 拼接下载地址
ASSET_URL="$MIRROR/$REPO/releases/download/$TAG/mihomo-$FILE_KEY-$TAG.tar.gz"
TMP_TAR="/tmp/mihomo.tar.gz"

echo "[INFO] 正在下载: $ASSET_URL"
curl -L --fail -o "$TMP_TAR" "$ASSET_URL"

# 安装目录
su -c "mkdir -p $INSTALL_DIR"

# 解压并安装
su -c "tar -xzf $TMP_TAR -C $INSTALL_DIR"
# 有的压缩包解压出来叫 mihomo-xxx，这里统一重命名
BIN_PATH=$(find "$INSTALL_DIR" -type f -name "mihomo*" | head -n1)
su -c "mv $BIN_PATH $INSTALL_DIR/mihomo"
su -c "chmod +x $INSTALL_DIR/mihomo"
rm -f "$TMP_TAR"

echo "[INFO] Mihomo 已安装到 $INSTALL_DIR/mihomo ✅"

# 创建任务目录
mkdir -p "$TASK_DIR"

# restart_mihomo.sh
cat > "$TASK_DIR/restart_mihomo.sh" <<'EOF'
#!/system/bin/sh
# restart_mihomo.sh - 重启 mihomo

su -c "killall -9 mihomo 2>/dev/null"
su -c "nohup /data/clash/mihomo -d /data/clash/ >/dev/null 2>&1 &"

echo "mihomo 已重启"
EOF
chmod +x "$TASK_DIR/restart_mihomo.sh"

# stop_mihomo.sh
cat > "$TASK_DIR/stop_mihomo.sh" <<'EOF'
#!/system/bin/sh
# stop_mihomo.sh - 停止 mihomo

su -c "killall -9 mihomo 2>/dev/null"

echo "mihomo 已停止"
EOF
chmod +x "$TASK_DIR/stop_mihomo.sh"

# 交互输入订阅链接
read -p "请输入你的订阅链接: " SUB_LINK

# update_mihomo.sh
cat > "$TASK_DIR/update_mihomo.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
CONFIG_DIR="/data/clash"
CONFIG_URL="$SUB_LINK"
TMP_FILE="\$CONFIG_DIR/config.yaml.tmp"

echo "[INFO] 开始更新订阅..."

if su -c "curl -L --fail -o \$TMP_FILE \$CONFIG_URL"; then
    su -c "mv \$TMP_FILE \$CONFIG_DIR/config.yaml"
    # 覆写 tun.stack
    su -c "sed -i 's/stack: system/stack: gvisor/' \$CONFIG_DIR/config.yaml"
    echo "[INFO] 配置已更新 ✅"
else
    echo "[ERROR] 下载失败 ❌ 保留旧配置"
    su -c "rm -f \$TMP_FILE"
fi
EOF
chmod +x "$TASK_DIR/update_mihomo.sh"

echo "[INFO] 已生成快捷任务脚本 ✅"
echo "👉 订阅链接已写入 $TASK_DIR/update_mihomo.sh"
