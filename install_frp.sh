#!/bin/bash
# 一键安装或升级最新版 frp (client/server) 到 Debian 12
# 原有配置文件不覆盖，支持 systemd 服务开机自启
set -e

INSTALL_DIR="/usr/local/frp"

# 检查 root
if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 用户运行该脚本"
  exit 1
fi

# 检查参数
if [[ "$1" != "client" && "$1" != "server" ]]; then
  echo "用法: $0 [client|server]"
  exit 1
fi

MODE=$1
if [[ "$MODE" == "client" ]]; then
  BIN="frpc"
  CONF="frpc.toml"
  SERVICE="frpc"
elif [[ "$MODE" == "server" ]]; then
  BIN="frps"
  CONF="frps.toml"
  SERVICE="frps"
fi

echo "获取 frp 最新 Release tag..."
TAG=$(curl -fsSL https://api.github.com/repos/fatedier/frp/releases/latest \
  | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -z "$TAG" ]]; then
  echo "无法获取最新版本号，退出"
  exit 1
fi
echo "最新版本：$TAG"

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

# 如果服务正在运行，先停止
if systemctl is-active --quiet ${SERVICE}; then
    echo "停止 ${SERVICE} 服务以更新二进制..."
    systemctl stop ${SERVICE}
fi

# 更新二进制
cp "/tmp/frp_${VER}_${ARCH}/${BIN}" "${INSTALL_DIR}/"

# 如果不存在配置文件，则生成默认
if [[ ! -f "${INSTALL_DIR}/${CONF}" ]]; then
    cp "/tmp/frp_${VER}_${ARCH}/${CONF}" "${INSTALL_DIR}/${CONF}"
fi

# 始终生成最新的 example 文件
cp "/tmp/frp_${VER}_${ARCH}/${CONF}" "${INSTALL_DIR}/${CONF}.example"

# 清理临时文件
rm -rf "/tmp/frp_${VER}_${ARCH}" "/tmp/${TAR}"

# 创建 systemd 服务
SERVICE_FILE="/etc/systemd/system/${SERVICE}.service"
echo "创建 systemd 服务..."
cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=frp ${MODE} (${BIN})
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${BIN} -c ${INSTALL_DIR}/${CONF}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
echo "启用并启动 ${SERVICE} 服务..."
systemctl daemon-reload
systemctl enable ${SERVICE}
systemctl restart ${SERVICE}

echo "===== 安装/升级完成 ====="
echo "模式：${MODE}"
echo "版本：${TAG}"
echo "安装目录：${INSTALL_DIR}"
echo "配置文件：${INSTALL_DIR}/${CONF}"
echo "参考示例文件：${INSTALL_DIR}/${CONF}.example"
echo "管理命令："
echo "  systemctl status ${SERVICE}"
echo "  systemctl restart ${SERVICE}"
