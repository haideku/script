#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Запусти от root" >$2
	exit 1
fi

hostnamectl set-hostname hq-cli.au-team.irpo

ALL_IFACES=()
for iface in $(ls /sys/class/net | sort); do
	[[ "$iface" == "lo" ]] && continue
	ALL_IFACES+=("$iface")
done

LAN1="${ALL_IFACES[0]}"

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

exec bash
