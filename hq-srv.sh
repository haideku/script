#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Запусти от root" >$2
	exit 1
fi

hostnamectl set-hostname hq-srv.au-team.irpo

ALL_IFACES=()
for iface in $(ls /sys/class/net | sort); do
	[[ "$iface" == "lo" ]] && continue
	ALL_IFACES+=("$iface")
done

LAN1="${ALL_IFACES[0]}"


LAN1_IP="192.168.100.2/27"
LAN1_ROUTE="default via 192.168.100.1"

VLAN="$LAN1.100"

mkdir -p /etc/net/ifaces/$LAN1

echo "TYPE=eth" > /etc/net/ifaces/$LAN1/options

mkdir -p /etc/net/ifaces/$VLAN

echo "TYPE=vlan" > /etc/net/ifaces/$VLAN/options
echo "HOST=$LAN1" >> /etc/net/ifaces/$VLAN/options
echo "VID=100" >> /etc/net/ifaces/$VLAN/options


echo "$LAN1_IP" > /etc/net/ifaces/$VLAN/ipv4address
echo "$LAN1_ROUTE" > /etc/net/ifaces/$VLAN/ipv4route
echo "nameserver 8.8.8.8" > /etc/net/ifaces/$VLAN/resolv.conf
echo "nameserver 77.88.8.8" >> /etc/net/ifaces/$VLAN/resolv.conf

systemctl restart network

useradd sshuser -u 2026
echo "sshuser:P@ssw0rd"|chpasswd
usermod -aG wheel sshuser
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/sshuser

apt-get update && apt-get dist-upgrade -y

echo "Authorized access only" > /etc/openssh/banner
echo -e "Port 2026\nMaxAuthTries 2\nAllowUsers sshuser\nBanner /etc/openssh/banner\n" >> /etc/openssh/sshd_config
systemctl restart sshd.service

apt-get update && apt-get install dnsmasq -y

cat <<'EOF' > /etc/dnsmasq.conf
no-hosts
server=77.88.8.8
cache-size=1000
all-servers
no-negcache
interface=*
host-record=hq-rtr.au-team.irpo,192.168.100.1
host-record=hq-rtr.au-team.irpo,192.168.200.1
host-record=hq-rtr.au-team.irpo,192.168.99.1
host-record=hq-srv.au-team.irpo,192.168.100.2
host-record=hq-cli.au-team.irpo,192.168.200.2
address=/br-rtr.au-team.irpo/192.168.0.1
address=/br-srv.au-team.irpo/192.168.0.2
address=/docker.au-team.irpo/172.16.1.1
address=/web.au-team.irpo/172.16.2.1
EOF

systemctl enable --now dnsmasq.service

timedatectl set-timezone Asia/Vladivostok
systemctl restart network


sed -i "s/^pool/#pool/" /etc/chrony.conf
echo "server 172.16.1.1 iburst" >> /etc/chrony.conf
systemctl restart chronyd




exec bash
