#!/bin/bash
set -e

# 获取最新版本号（GitHub release latest）
LATEST=$(curl -sL https://api.github.com/repos/filebrowser/filebrowser/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
if [ -z "$LATEST" ]; then
  echo "无法获取最新版本（GitHub API 返回空）。"
  exit 1
fi

echo "检测到最新版本：$LATEST"

# 判断系统架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    FB_ARCH="linux-amd64"
    ;;
  aarch64|arm64)
    FB_ARCH="linux-arm64"
    ;;
  armv7l)
    FB_ARCH="linux-armv7"
    ;;
  i386|i686)
    FB_ARCH="linux-386"
    ;;
  *)
    echo "不支持的架构：$ARCH"
    exit 1
    ;;
esac

DOWNLOAD_URL="https://github.com/filebrowser/filebrowser/releases/download/${LATEST}/${FB_ARCH}-filebrowser.tar.gz"

echo "架构：$ARCH -> $FB_ARCH"
echo "下载链接： $DOWNLOAD_URL"

# 下载并解压
tmpdir=$(mktemp -d)
wget -O "$tmpdir/filebrowser.tar.gz" "$DOWNLOAD_URL"
tar -zxvf "$tmpdir/filebrowser.tar.gz" -C "$tmpdir"

# 安装到 /usr/bin
mv "$tmpdir/filebrowser" /usr/bin/filebrowser
chmod +x /usr/bin/filebrowser

# 清理临时目录
rm -rf "$tmpdir"

# 创建 systemd 服务
cat > /etc/systemd/system/filebrowser.service <<EOF
[Unit]
Description=File Browser
After=network.target

[Service]
ExecStart=/usr/bin/filebrowser -d /etc/filebrowser.db
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
systemctl daemon-reload
systemctl enable --now filebrowser

echo "✅ Filebrowser $LATEST 已安装并启动"
echo "访问方式： http://<你的服务器IP>:11000"
