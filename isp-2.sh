#!/bin/bash

if [[ $EUID -ne 0 ]]; then
	echo "Запусти от root" >$2
	exit 1
fi

sed -i 's/^pool/#pool/' /etc/chrony.conf
cat <<'EOF' >> /etc/chrony.conf
server ntp0.ntp-servers.net iburst prefer minstratum 4
local stratum 5
allow 0.0.0.0/0
EOF

systemctl restart chronyd

apt-get update && apt-get dist-upgrade -y

apt-get install apache2-htpasswd -y


apt-get install nginx -y

cat <<'EOF' > /etc/nginx/sites-available.d/default.conf
server {
  listen 80;
  server_name web.au-team.irpo;
  location / {
    proxy_pass http://172.16.1.2:8080;
    auth_basic "Restricted area";
    auth_basic_user_file /etc/nginx/.htpasswd;
  }
}

server {
  listen 80;
  server_name docker.au-team.irpo;
  location / {
    proxy_pass http://172.16.2.2:8080;
  }
}
EOF

ln -s /etc/nginx/sites-available.d/default.conf /etc/nginx/sites-enabled.d/

htpasswd -c /etc/nginx/.htpasswd WEB



systemctl enable --now nginx
systemctl restart nginx










