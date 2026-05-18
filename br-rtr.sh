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

echo "Введите hostname: (br-rtr.au-team.irpo)"
read HOSTNAME

echo "Введите IP и префикс для LAN1-интерфейса (например 172.16.2.2/28):"
read LAN1_IP

echo "Введите IP и префикс для LAN2-интерфейса (например 192.168.0.1/28):"
read LAN2_IP

echo "Введите маршрут для LAN1-интерфейса (default via 172.16.2.1):"
read LAN1_ROUTE

hostnamectl set-hostname $HOSTNAME

mkdir -p "/etc/net/ifaces/$LAN1"
mkdir -p "/etc/net/ifaces/$LAN2"


echo "TYPE=eth" > "/etc/net/ifaces/$LAN1/options"
echo "$LAN1_IP" > "/etc/net/ifaces/$LAN1/ipv4address"
echo "$LAN2_IP" > "/etc/net/ifaces/$LAN2/ipv4address"
echo "$LAN1_ROUTE" > "/etc/net/ifaces/$LAN1/ipv4route"


echo "TYPE=eth" > "/etc/net/ifaces/$LAN2/options"
echo "nameserver	77.88.8.8" > "/etc/net/ifaces/$LAN1/resolv.conf"
echo "nameserver	8.8.8.8" >> "/etc/net/ifaces/$LAN/resolv.conf"


sed -i 's/^net\.ipv4\.ip_forward = 0/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
if ! grep -q '^net\.ipv4\.ip_forward = 1' /etc/net/sysctl.conf; then
	echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
fi

mkdir -p "/etc/net/ifaces/gre1"

echo "Введите IP HQ-RTR для GRE туннеля (например 172.16.1.2):"
read HQ_IP

echo "TYPE=iptun" > /etc/net/ifaces/gre1/options
echo "TUNTYPE=gre" >> /etc/net/ifaces/gre1/options
echo "TUNLOCAL=$LAN1_IP" >> /etc/net/ifaces/gre1/options
echo "TUNREMOTE=$HQ_IP" >> /etc/net/ifaces/gre1/options
echo "TUNOPTIONS='ttl 64'" >> /etc/net/ifaces/gre1/options
echo "HOST=$LAN1" >> /etc/net/ifaces/gre1/options

echo "Введите IP и префикс для GRE туннеля: (10.10.10.2/30)
read GRE_IP

echo "$GRE_IP" > "/etc/net/ifaces/gre1/ipv4address"

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

apt-get update
apt-get install frr -y

sed -i "s/ospfd=no/ospfd=yes/g" /etc/frr/daemons
systemctl enable --now frr.service

cat <<'EOF' > /etc/frr/frr.conf
frr default trditional
hostanem br-rtr.au-team.irpo
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
	network 192.168.0.0/29 area 0
exit
!
EOF

systemctl restart frr

timedatectl set-timezone Asia/Vladivostok
systemctl restart network

sed -i "s/^pool/#pool/" /etc/chrony.conf
echo "server 172.16.2.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd


iptables -t nat -A PREROUTING -i $LAN1 -p tcp --dport 2026 -j DNAT --to-destination 192.168.100.2:2026
iptables -t nat -A PREROUTING -i $LAN1 -p tcp --dport 8080 -j DNAT --to-destination 192.168.100.2:80
iptables-save >> /etc/sysconfig/iptables


exec bash




