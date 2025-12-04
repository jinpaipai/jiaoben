# 设置主路由wan，lan，dhcp等
# Wan口DHCP    bash -c "$(curl -fsSL https://raw.githubusercontent.com/jinpaipai/jiaoben/refs/heads/main/install_router.sh)" dhcp
# Wan口pppoe    bash -c "$(curl -fsSL https://raw.githubusercontent.com/jinpaipai/jiaoben/refs/heads/main/install_router.sh)" pppoe
#!/bin/bash
### ------------------------------
### Router One-Key Install Script
### Supports WAN: DHCP / PPPoE
### Auto-detect interfaces
### ------------------------------

# ====== 参数 ======
WAN_MODE=$1   # dhcp 或 pppoe
LAN_IP="192.168.31.2"
LAN_NETMASK="255.255.255.0"
LAN_IPv6="fd00:6868:6868::2"
LAN_IPv6_MASK="64"

if [[ "$WAN_MODE" != "dhcp" && "$WAN_MODE" != "pppoe" ]]; then
    echo "用法： ./install_router.sh {dhcp | pppoe}"
    exit 1
fi

echo "==> 启动模式：$WAN_MODE"

# ====== 自动识别网口 ======
echo "==> 自动识别网卡中..."

ALL_IFACES=$(ls /sys/class/net | grep -v lo)

# 识别 LAN：已有私网 IP 的接口
LAN_IFACE=""
for i in $ALL_IFACES; do
    ip addr show "$i" | grep -q "inet 192\.168" && LAN_IFACE="$i"
done

# 若未识别到，默认第一个非 lo 网口为 LAN
if [[ -z "$LAN_IFACE" ]]; then
    LAN_IFACE=$(echo $ALL_IFACES | awk '{print $1}')
fi

# WAN 为剩下的接口
WAN_IFACE=""
for i in $ALL_IFACES; do
    if [[ "$i" != "$LAN_IFACE" ]]; then
        WAN_IFACE="$i"
    fi
done

echo "==> 识别到 LAN 网口：$LAN_IFACE"
echo "==> 识别到 WAN 网口：$WAN_IFACE"

sleep 1


# ====== 1. 启用 IPv6 ======
echo "==> 配置 sysctl IPv6"

cat >/etc/sysctl.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
EOF

sysctl -p


# ====== 2. 生成 /etc/network/interfaces ======
echo "==> 写入网络接口配置"

cat >/etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# ========= LAN 接口 =========
allow-hotplug $LAN_IFACE
iface $LAN_IFACE inet static
    address $LAN_IP
    netmask $LAN_NETMASK

iface $LAN_IFACE inet6 static
    address $LAN_IPv6
    netmask $LAN_IPv6_MASK

# ========= WAN 接口 =========
EOF

if [[ "$WAN_MODE" == "dhcp" ]]; then
cat >>/etc/network/interfaces <<EOF
auto $WAN_IFACE
iface $WAN_IFACE inet dhcp
iface $WAN_IFACE inet6 auto
EOF
else
cat >>/etc/network/interfaces <<EOF
auto $WAN_IFACE
iface $WAN_IFACE inet manual
EOF
fi


# ====== 3. 安装 dnsmasq ======
echo "==> 安装 dnsmasq"

apt update
apt install -y dnsmasq

echo "==> 写入 dnsmasq 配置"

cat >/etc/dnsmasq.conf <<EOF
interface=$LAN_IFACE
bind-interfaces

# ====== IPv4 DHCP ======
dhcp-range=192.168.31.100,192.168.31.200,12h
dhcp-option=3,$LAN_IP
dhcp-option=6,$LAN_IP

# ====== IPv6 DHCP + RA ======
enable-ra
dhcp-range=::100,::200,constructor:$LAN_IFACE,ra-only,12h
dhcp-option=option6:dns-server,[$LAN_IPv6]

# 固定租约部分已移除，需要时自行添加
EOF


# ====== 4. 写入 nftables ======
echo "==> 写入 nftables 配置"

if [[ "$WAN_MODE" == "dhcp" ]]; then
OUT_IFACE="$WAN_IFACE"
else
OUT_IFACE='ppp*'
fi

cat >/etc/nftables.conf <<EOF
table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100;
        oifname "$OUT_IFACE" masquerade
    }
}

table ip6 nat {
    chain postrouting {
        type nat hook postrouting priority 100;
        oifname "$OUT_IFACE" masquerade
    }
}
EOF

systemctl restart nftables


# ====== 5. PPPoE 配置（仅在 pppoe 模式下） ======
if [[ "$WAN_MODE" == "pppoe" ]]; then

    echo "==> 配置 PPPoE"

    apt install -y pppoe ppp

cat >/etc/ppp/peers/wan <<EOF
plugin rp-pppoe.so $WAN_IFACE
user "your_account"
defaultroute
persist
noauth
mtu 1492
EOF

cat >/etc/ppp/chap-secrets <<EOF
"your_account" * "your_password" *
EOF

# systemd 开机自动拨号
cat >/etc/systemd/system/pppoe-wan.service <<EOF
[Unit]
Description=PPPoE WAN Connection
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/pon wan
ExecStop=/usr/sbin/poff wan
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pppoe-wan.service

fi


# ====== 6. 重启服务 ======
systemctl restart dnsmasq

echo "=================================================="
echo "安装完成！"
echo "LAN: $LAN_IFACE"
echo "WAN: $WAN_IFACE"
echo "模式: $WAN_MODE"
echo "=================================================="

if [[ "$WAN_MODE" == "pppoe" ]]; then
    echo "请编辑账号密码: /etc/ppp/chap-secrets"
fi

exit 0
