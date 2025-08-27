#!/bin/bash
# 一键安装或升级最新版 frpc 到 Debian 12
# 保留原有 frpc.toml 配置文件
set -e

INSTALL_DIR="/usr/local/frp"
SERVICE_FILE="/etc/systemd/system/frpc.service"

# 确保以 root 权限执行
if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 用户运行该脚本"
  exit 1
fi

echo "获取 frp 最新 Release tag..."
TAG=$(curl -fsSL https://api.github.com/repos/fatedier/frp/releases/latest \
  | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -z "$TAG" ]]; then
  echo "无法获取最新版本号，退出"
  exit 1
fi
echo "最新版本：$TAG"

# 去掉前缀 'v'（如果存在）
VER=${TAG#v}

# 自动判断架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="linux_amd64" ;;
  aarch64) ARCH="linux_arm64" ;;
  *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

TAR="frp_${VER}_${ARCH}.tar.gz"
URL="https://github.com/fatedier/frp/releases/download/${TAG}/${TAR}"

echo "下载 $TAR..."
wget -q --show-progress "$URL" -O "/tmp/${TAR}"

echo "解压并安装到 ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"
tar -xzf "/tmp/${TAR}" -C /tmp
# 只更新 frpc 二进制
cp "/tmp/frp_${VER}_${ARCH}/frpc" "${INSTALL_DIR}/"
# 如果不存在 frpc.toml，则生成默认配置
if [[ ! -f "${INSTALL_DIR}/frpc.toml" ]]; then
  cp "/tmp/frp_${VER}_${ARCH}/frpc.toml" "${INSTALL_DIR}/frpc.toml"
fi
# 始终生成最新的 example 文件
cp "/tmp/frp_${VER}_${ARCH}/frpc.toml" "${INSTALL_DIR}/frpc.toml.example"
rm -rf "/tmp/frp_${VER}_${ARCH}" "/tmp/${TAR}"

# 创建 systemd 服务
echo "创建 systemd 服务..."
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=frp client (frpc)
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/frpc -c ${INSTALL_DIR}/frpc.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
echo "启用并启动 frpc 服务..."
systemctl daemon-reload
systemctl enable frpc
systemctl restart frpc

echo "===== 安装/升级完成 ====="
echo "版本：${TAG}"
echo "安装目录：${INSTALL_DIR}"
echo "配置文件：${INSTALL_DIR}/frpc.toml"
echo "参考示例文件：${INSTALL_DIR}/frpc.toml.example"
echo "管理命令："
echo "  systemctl status frpc"
echo "  systemctl restart frpc"
