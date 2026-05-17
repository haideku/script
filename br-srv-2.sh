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
LAN2="${ALL_IFACES[1]}"

mkdir -p /etc/net/$LAN1
mkdir -p /etc/net/$LAN2
