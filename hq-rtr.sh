#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Запусти от root" >$2
	exit 1
fi

hostnamectl set-hostname hq-rtr.au-team.irpo

VLAN_LIST=(
    "100:192.168.100.1/27"
    "200:192.168.200.1/28"
    "999:192.168.99.1/29"
)

ALL_IFACES=()
for iface in $(ls /sys/class/net | sort); do
	[[ "$iface" == "lo" ]] && continue
	ALL_IFACES+=("$iface")
done

LAN1="${ALL_IFACES[0]}"
LAN2="${ALL_IFACES[1]}"

VLAN_PARENT="$LAN2"

LAN1_IP="172.16.1.2/28"
LAN1_ROUTE="default via 172.16.1.1"

mkdir -p "/etc/net/ifaces/$LAN1"
mkdir -p "/etc/net/ifaces/$LAN2"


echo "TYPE=eth" > "/etc/net/ifaces/$LAN1/options"
echo "$LAN1_IP" > "/etc/net/ifaces/$LAN1/ipv4address"
echo "$LAN1_ROUTE" > "/etc/net/ifaces/$LAN1/ipv4route"

echo "TYPE=eth" > "/etc/net/ifaces/$LAN2/options"
echo "nameserver	8.8.8.8" > "/etc/resolv.conf"

for entry in "${VLAN_LIST[@]}"; do
    vid="${entry%%:*}"
    ip_cidr="${entry##*:}"
    vlan_iface="$VLAN_PARENT.$vid"

	mkdir -p "/etc/net/ifaces/$vlan_iface"

	echo "TYPE=vlan" > "/etc/net/ifaces/$vlan_iface/options"
	echo "HOST=$VLAN_PARENT" >> "/etc/net/ifaces/$vlan_iface/options"
	echo "VID=$vid" >> "/etc/net/ifaces/$vlan_iface/options"
	echo "$ip_cidr" > "/etc/net/ifaces/$vlan_iface/ipv4address"
done


sed -i 's/^net\.ipv4\.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
if ! grep -q '^net\.ipv4\.ip_forward = 1' /etc/net/sysctl.conf; then
	echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
fi

systemctl restart network

apt-get update && apt-get dist-upgrade -y

mkdir -p "/etc/net/ifaces/gre1"

echo "TYPE=iptun" > /etc/net/ifaces/gre1/options
echo "TUNTYPE=gre" >> /etc/net/ifaces/gre1/options
echo "TUNLOCAL=172.16.1.2" >> /etc/net/ifaces/gre1/options
echo "TUNREMOTE=172.16.2.2" >> /etc/net/ifaces/gre1/options
echo "TUNOPTIONS='ttl 64'" >> /etc/net/ifaces/gre1/options
echo "HOST=$LAN1" >> /etc/net/ifaces/gre1/options

echo "10.10.10.1/30" > "/etc/net/ifaces/gre1/ipv4address"

systemctl restart network

apt-get install frr -y

sed -i "s/ospfd=no/ospfd=yes/g" /etc/frr/daemons
systemctl enable --now frr.service

cat <<'EOF' > /etc/frr/frr.conf

interface gre

no ip ospf passive

exit

!

interface gre1

ip ospf area 0

ip ospf authentication

ip ospf authentication-key P@ssw0rd

no ip ospf passive

exit

!

interface "$VLAN_PARENT.100"

ip ospf area 0

exit

!

interface "$VLAN_PARENT.200"

ip ospf area 0

exit

!

interface "$VLAN_PARENT.999"

ip ospf area 0

exit

!

router ospf

passive-interface default

exit

EOF


apt-get install iptables


systemctl restart network
