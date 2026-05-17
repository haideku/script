#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Запусти от root" >$2
	exit 1
fi

hostnamectl set-hostname br-srv.au-team.irpo

ALL_IFACES=()
for iface in $(ls /sys/class/net | sort); do
	[[ "$iface" == "lo" ]] && continue
	ALL_IFACES+=("$iface")
done

LAN1="${ALL_IFACES[0]}"

LAN_IP="192.168.0.2/28"
LAN_ROUTE="default via 192.168.0.1"

mkdir -p /etc/net/ifaces/$LAN1

echo "$LAN_IP" > /etc/net/ifaces/$LAN1/ipv4address
echo "$LAN_ROUTE" > /etc/net/ifaces/$LAN1/ipv4route
echo $'search au-team.irpo\nnameserver 192.168.100.2' > /etc/net/ifaces/$LAN1/resolv.conf
systemctl restart network

apt-get update && apt-get dist-upgrade -y

useradd sshuser -u 2026
echo "sshuser:P@ssw0rd"|chpasswd
usermod -aG wheel sshuser
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/sshuser

echo "Authorized access only" > /etc/openssh/banner
echo -e "Port 2026\nMaxAuthTries 2\nAllowUsers sshuser\nBanner /etc/openssh/banner\n" >> /etc/openssh/sshd_config
systemctl restart sshd.service


timedatectl set-timezone Asia/Vladivostok
systemctl restart network

sed -i "s/^pool/#pool/" /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd



exec bash
