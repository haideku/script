#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Запусти от root" >$2
	exit 1
fi

VLAN_LIST=(
    "100:192.168.100.1/27"
    "200:192.168.200.1/28"
    "999:192.168.99.1/29"
)

ALL_IFACES=()
for iface in $(ls /sys/class/net | sort); do
	[[ "$iface" == "lo" ]] && continue
	[[ "$iface" == "$WAN" ]] && continue
	ALL_IFACES+=("$iface")
done

LAN1="${ALL_IFACES[0]}"
LAN2="${ALL_IFACES[1]}"

VLAN_PARENT="$LAN2"

LAN1_IP="172.16.2.2/28"
LAN1_ROUTE="default via 172.16.1.1"

mkdir -p "/etc/net/ifaces/$LAN1" "/etc/net/ifaces/$LAN2"

echo "TYPE=eth" > /etc/net/ifaces/$LAN1/options
echo "$LAN1_IP" > "/etc/net/ifaces/$LAN1/ipv4address"
echo "$LAN1_ROUTE" > "/etc/net/ifaces/$LAN1/ipv4route"
