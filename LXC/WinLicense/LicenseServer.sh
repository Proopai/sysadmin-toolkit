#!/bin/bash
apt update && apt upgrade -y
apt update
apt upgrade
apt install git gcc make
mkdir vlmcsd_install
cd vlmcsd_install/
git clone https://github.com/Wind4/vlmcsd
cd vlmcsd/
make
mkdir /opt/vlmcsd
cp -r ./bin /opt/vlmcsd/
ln -s /opt/vlmcsd/bin/vlmcsd /usr/bin
mkdir /var/log/vlmcsd
rm -rf ~/vlmcsd_install

cat << 'EOF' > /etc/systemd/system/vlmcsd.service
[Unit]
Description=VLMCSD KMS Server
After=network.target
After=network-online.target
Wants=network-online.target
StartLimitInterval=0

[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/usr/bin/vlmcsd -l /var/log/vlmcsd/vlmcsd.log
User=root

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/vlmcsd.service

systemctl start vlmcsd
systemctl status vlmcsd
systemctl enable vlmcsd

