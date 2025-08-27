#!/bin/bash
# 一键安装最新版 frpc 到 Debian 12
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
ARCH="linux_amd64"  # 你也可以改成 linux_arm64 或自适应判断

TAR="frp_${VER}_${ARCH}.tar.gz"
URL="https://github.com/fatedier/frp/releases/download/${TAG}/${TAR}"

echo "正在下载 $TAR..."
wget -q --show-progress "$URL" -O "/tmp/${TAR}"

echo "解压并安装到 ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
tar -xzf "/tmp/${TAR}" -C /tmp
cp "/tmp/frp_${VER}_${ARCH}/frpc" "${INSTALL_DIR}/"
cp "/tmp/frp_${VER}_${ARCH}/frpc.toml" "${INSTALL_DIR}/frpc.toml.example"
rm -rf "/tmp/frp_${VER}_${ARCH}" "/tmp/${TAR}"

# 如果配置文件缺失，则生成默认示例
if [[ ! -f "${INSTALL_DIR}/frpc.toml" ]]; then
  cat > "${INSTALL_DIR}/frpc.toml" <<EOF
[common]
server_addr = "x.x.x.x"
server_port = 7000
# token = "your_token"

[[proxies]]
name = "ssh"
type = "tcp"
local_ip = "127.0.0.1"
local_port = 22
remote_port = 6000
EOF
  echo "已生成默认配置：${INSTALL_DIR}/frpc.toml"
fi

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

echo "启用并启动 frpc 服务..."
systemctl daemon-reload
systemctl enable frpc
systemctl restart frpc

echo "===== 安装完成 ====="
echo "版本：${TAG}"
echo "安装目录：${INSTALL_DIR}"
echo "管理命令："
echo "  systemctl status frpc"
echo "  systemctl restart frpc"
echo "配置文件：${INSTALL_DIR}/frpc.toml"
