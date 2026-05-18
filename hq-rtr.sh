#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Запусти от root" >$2
	exit 1
fi

VLAN_LIST=(
    "100:192.168.100.1/27"
    "200:192.168.200.1/24"
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

echo "Введите hostname: (hq-rtr.au-team.irpo)"
read HOSTNAME

echo "Введите IP и префикс для LAN1-интерфейса (например 172.16.1.2/28):"
read LAN1_IP

echo "Введите маршрут для LAN1-интерфейса (default via 172.16.1.1):"
read LAN1_ROUTE

hostnamectl set-hostname $HOSTNAME

mkdir -p "/etc/net/ifaces/$LAN1"
mkdir -p "/etc/net/ifaces/$LAN2"


echo "TYPE=eth" > "/etc/net/ifaces/$LAN1/options"
echo "$LAN1_IP" > "/etc/net/ifaces/$LAN1/ipv4address"
echo "$LAN1_ROUTE" > "/etc/net/ifaces/$LAN1/ipv4route"

echo "TYPE=eth" > "/etc/net/ifaces/$LAN2/options"
echo "nameserver	77.88.8.8" > "/etc/net/ifaces/$LAN1/resolv.conf"
echo "nameserver	8.8.8.8" >> "/etc/net/ifaces/$LAN1/resolv.conf"

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

echo $'search	au-team.irpo\nnameserver	192.168.100.2' > /etc/net/ifaces/$VLAN_PARENT.100/resolv.conf

sed -i 's/^net\.ipv4\.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
if ! grep -q '^net\.ipv4\.ip_forward = 1' /etc/net/sysctl.conf; then
	echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
fi

systemctl restart network

useradd net_admin
echo "net_admin:P@ssw0rd"|chpasswd
usermod -aG wheel net_admin
echo "net_admin ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/net_admin


apt-get update && apt-get dist-upgrade -y

apt-get install iptables -y

iptables -t nat -A POSTROUTING -o $LAN1 -j MASQUERADE
iptables-save >> /etc/sysconfig/iptables
systemctl enable --now iptables.service

mkdir -p "/etc/net/ifaces/gre1"

echo "Введите IP br-rtr для gre туннеля: (172.16.2.2)"
read BR_IP

echo "TYPE=iptun" > /etc/net/ifaces/gre1/options
echo "TUNTYPE=gre" >> /etc/net/ifaces/gre1/options
echo "TUNLOCAL=$LAN1_IP" >> /etc/net/ifaces/gre1/options
echo "TUNREMOTE=$BR_IP" >> /etc/net/ifaces/gre1/options
echo "TUNOPTIONS='ttl 64'" >> /etc/net/ifaces/gre1/options
echo "HOST=$LAN1" >> /etc/net/ifaces/gre1/options

echo "Введите IP и префикс для gre туннеля: (10.10.10.1/30)"
read GRE_IP
echo "$GRE_IP" > "/etc/net/ifaces/gre1/ipv4address"

systemctl restart network

apt-get install frr -y

sed -i "s/ospfd=no/ospfd=yes/g" /etc/frr/daemons
systemctl enable --now frr.service

cat <<'EOF' > /etc/frr/frr.conf

frr default trditional
hostanem hq-rtr.au-team.irpo
log file /var/log/frr/frr.log
no ipv6 forwarding
!
interface gre1
	ip ospf authentication message-digest
	ip ospf message-digest-key 1 md5 P@ssw0rd
	no ip ospf passive
exit
!
router ospf
	passive-interface default
	network 10.10.10.0/30 area 0
	network 192.168.99.0/29 area 0
	network 192.168.100.0/27 area 0
	network 192.168.200.0/24 area 0
exit
!

EOF

systemctl restart frr

apt-get update && apt-get install dhcp-server -y

sed -i "s/DHCPDARGS=/DHCPDARGS='$VLAN_PARENT.200'/g" /etc/susconfig/dhcpd
cat <<'EOF' > /etc/dhcp/dhcp.conf
option domain-name "au-team.irpo";
option domain-name-servers 192.168.100.2;
default-lease-time 6000;
max-lease-time 72000;
authoritative;
subnet 192.168.200.0 netmask 255.255.255.0 {
	range 192.168.200.2 192.168.200.254;
	option routers 192.168.200.1;
}
EOF

systemctl enable --now dhcpd.service


timedatectl set-timezone Asia/Vladivostok
systemctl restart network

sed -i "s/^pool/#pool/" /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd


iptables -t nat -A PREROUTING -i $LAN1 -p tcp --dport 2026 -j DNAT --to-destination 192.168.100.2:2026
iptables -t nat -A PREROUTING -i $LAN1 -p tcp --dport 8080 -j DNAT --to-destination 192.168.100.2:80
iptables-save >> /etc/sysconfig/iptables



exec bash
