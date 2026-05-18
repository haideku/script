#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Запусти от root" >$2
	exit 1
fi

WAN=$(ip route show default 2>/dev/null | awk '{print $5; exit}') || true
if [[ -z "$WAN" ]]; then
	WAN=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v lo | head -1)
fi

ALL_IFACES=()
for iface in $(ls /sys/class/net | sort); do
	[[ "$iface" == "lo" ]] && continue
	[[ "$iface" == "$WAN" ]] && continue
	ALL_IFACES+=("$iface")
done

LAN1="${ALL_IFACES[0]}"
LAN2="${ALL_IFACES[1]}"

echo "Введите hostname: (ISP)"
read HOSTNAME

echo "Введите IP и префикс для LAN1-интерфейса (например 172.16.1.1/28):"
read LAN1_IP

echo "Введите IP и префикс для LAN2-интерфейса (например 172.16.2.1/28):"
read LAN2_IP

echo "Введите маршрут для LAN1-интерфейса (default via 172.16.1.2):"
read LAN1_ROUTE

echo "Введите маршрут для LAN2-интерфейса (default via 172.16.2.2):"
read LAN2_ROUTE

echo "Введите подсеть для iptables (172.16.1.0/28):"
read LAN1_NET

echo "Введите подсеть для iptables (172.16.2.0/28):"
read LAN2_NET

hostnamectl set-hostname $HOSTNAME

mkdir -p "/etc/net/ifaces/$WAN"
echo "TYPE=eth" > /etc/net/ifaces/$WAN/options
echo "BOOTPROTO=dhcp" >> /etc/net/ifaces/$WAN/options
echo "ONBOOT=yes" >> /etc/net/ifaces/$WAN/options

cat "/etc/net/ifaces/$WAN/options"

for iface in "$LAN1" "$LAN2"; do
	mkdir -p "/etc/net/ifaces/$iface"
	echo "TYPE=eth" > "/etc/net/ifaces/$iface/options"
done

echo "$LAN1_IP" > "/etc/net/ifaces/$LAN1/ipv4address"
echo "$LAN2_IP" > "/etc/net/ifaces/$LAN2/ipv4address"

echo "$LAN1_ROUTE" > "/etc/net/ifaces/$LAN1/ipv4route"
echo "$LAN2_ROUTE" > "/etc/net/ifaces/$LAN2/ipv4route"

echo "nameserver	8.8.8.8" > "/etc/net/ifaces/$WAN/resolv.conf"

apt-get update && apt-get dist-upgrade -y
apt-get install iptables -y

iptables -t nat -A POSTROUTING -s "$LAN1_NET" -o "$WAN" -j MASQUERADE
iptables -t nat -A POSTROUTING -s "$LAN2_NET" -o "$WAN" -j MASQUERADE

iptables-save >> /etc/sysconfig/iptables
systemctl enable --now iptables.service

iptables -t nat -L -n -v


sed -i 's/^net\.ipv4\.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
if ! grep -q '^net\.ipv4\.ip_forward = 1' /etc/net/sysctl.conf; then
	echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
fi

systemctl restart network

sysctl net.ipv4.ip_forward

ip link set "$LAN1" down
ip link set "$LAN2" down

ping -c4 8.8.8.8

ip link set "$LAN1" up
ip link set "$LAN2" up

exec bash
