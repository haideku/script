#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Запусти от root" >$2
	exit 1
fi

ALL_IFACES=()
for iface in $(ls /sys/class/net | sort); do
	[[ "$iface" == "lo" ]] && continue
	ALL_IFACES+=("$iface")
done

LAN1="${ALL_IFACES[0]}"

echo "Введите hostname: (hq-cli.au-team.irpo"
read HOSTNAME

hostnamectl set-hostname $HOSTNAME

VLAN="$LAN1.200"


mkdir -p /etc/net/ifaces/$LAN1

mkdir -p /etc/net/ifaces/$VLAN

echo "TYPE=eth" > /etc/net/ifaces/$LAN1/options
echo "TYPE=vlan" > /etc/net/ifaces/$VLAN/options
echo "HOST=$LAN1" >> /etc/net/ifaces/$VLAN/options
echo "VID=200" >> /etc/net/ifaces/$VLAN/options
echo "BOOTPROTO=dhcp" >> /etc/net/ifaces/$VLAN/options

timedatectl set-timezone Asia/Vladivostok
systemctl restart network

apt-get update && apt-get dist-upgrade -y

sed -i "s/^pool/#pool/" /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd

echo "172.16.1.1 web.au-team.irpo" >> /etc/hosts
echo "172.16.2.1 docker.au-team.irpo" >> /etc/hosts


exec bash
