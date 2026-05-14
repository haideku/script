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

LAN1_IP="172.16.1.1/28"
LAN2_IP="172.16.2.1/28"

LAN1_ROUTE="default via 172.16.1.2"
LAN2_ROUTE="default via 172.16.2.2"

LAN1_NET="172.16.1.0/28"
LAN2_NET="172.16.2.0/28"

hostnamectl set-hostname ISP 2>/dev/nill || hostaname ISP
hostname ISP

mkdir -p "/etc/net/ifaces/$WAN"
echo "TYPE=eth" > /etc/net/ifaces/$WAN/options
echo "BOOTPTOTO=dhcp" >> /etc/net/ifaces/$WAN/options
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
