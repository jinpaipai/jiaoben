#!/bin/bash

# 一键安装 qbittorrent-nox 并启动服务，同时保留已有配置文件

set -e

# 定义用户主目录
USER_HOME="$HOME"

# 备份已有配置（以防万一）
if [ -d "$USER_HOME/.config/qBittorrent" ]; then
    echo "备份现有配置文件..."
    cp -r "$USER_HOME/.config/qBittorrent" "$USER_HOME/.config/qBittorrent.bak_$(date +%s)"
fi

if [ -d "$USER_HOME/.local/share/qBittorrent" ]; then
    echo "备份现有数据..."
    cp -r "$USER_HOME/.local/share/qBittorrent" "$USER_HOME/.local/share/qBittorrent.bak_$(date +%s)"
fi

# 安装 qbittorrent-nox
echo "安装 qbittorrent-nox..."
sudo apt update
sudo apt install qbittorrent-nox -y

# 创建 systemd 服务文件
echo "创建 systemd 服务文件..."
SERVICE_FILE="/etc/systemd/system/qbittorrent-nox.service"
sudo bash -c "cat > $SERVICE_FILE" <<EOL
[Unit]
Description=qBittorrent Command Line Client
After=network.target

[Service]
Type=forking
User=root
ExecStart=/usr/bin/qbittorrent-nox -d --webui-port=32187
ExecStop=/usr/bin/kill -w qbittorrent-nox
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL

# 重新加载 systemd
echo "重新加载 systemd 配置..."
sudo systemctl daemon-reload

# 启动并设置开机自启
echo "启动 qbittorrent-nox 服务..."
sudo systemctl start qbittorrent-nox
sudo systemctl enable qbittorrent-nox

echo "qbittorrent-nox 安装并启动完成！"
echo "WebUI 端口: 32187"