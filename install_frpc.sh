#!/bin/bash
# 一键安装并配置 frpc for Debian 12
# Author: ChatGPT

# 下载地址（可改为自己需要的版本）
FRP_VERSION="0.61.1"
FRP_TAR="frp_${FRP_VERSION}_linux_amd64.tar.gz"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_TAR}"

INSTALL_DIR="/usr/local/frp"
SERVICE_FILE="/etc/systemd/system/frpc.service"

# 检查是否 root
if [[ $EUID -ne 0 ]]; then
   echo "请使用 root 用户运行此脚本"
   exit 1
fi

echo "==== 下载 frpc v${FRP_VERSION} ===="
wget -q --show-progress $DOWNLOAD_URL -O /tmp/${FRP_TAR}
if [[ $? -ne 0 ]]; then
    echo "下载失败，请检查网络或版本号"
    exit 1
fi

echo "==== 解压到 ${INSTALL_DIR} ===="
mkdir -p ${INSTALL_DIR}
tar -xzf /tmp/${FRP_TAR} -C /tmp
cp /tmp/frp_${FRP_VERSION}_linux_amd64/frpc ${INSTALL_DIR}/
cp /tmp/frp_${FRP_VERSION}_linux_amd64/frpc.toml ${INSTALL_DIR}/frpc.toml.example
rm -rf /tmp/frp_${FRP_VERSION}_linux_amd64
rm -f /tmp/${FRP_TAR}

# 如果配置文件不存在，则创建空文件
if [[ ! -f ${INSTALL_DIR}/frpc.toml ]]; then
    cat > ${INSTALL_DIR}/frpc.toml <<EOF
# frpc.toml 示例配置
serverAddr = "x.x.x.x"
serverPort = 7000

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 22
remotePort = 6000
EOF
    echo "已生成默认配置文件：${INSTALL_DIR}/frpc.toml"
fi

echo "==== 创建 systemd 服务 ===="
cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=frp client
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/frpc -c ${INSTALL_DIR}/frpc.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

echo "==== 重新加载 systemd ===="
systemctl daemon-reexec
systemctl enable frpc
systemctl restart frpc

echo "==== 安装完成 ===="
echo "可使用以下命令管理 frpc："
echo "  systemctl start frpc"
echo "  systemctl stop frpc"
echo "  systemctl restart frpc"
echo "  systemctl status frpc"