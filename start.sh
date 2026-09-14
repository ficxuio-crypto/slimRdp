#!/bin/bash

# Update root password dynamically
PASS="${ROOT_PASSWORD:-root}"
echo "root:${PASS}" | chpasswd

# Respect dynamic PORT environment variable (Railway / Cloud)
RDP_PORT="${PORT:-3389}"
sed -i -E "s/^[[:space:]]*port=[0-9]+/port=${RDP_PORT}/g" /etc/xrdp/xrdp.ini

service dbus start
pulseaudio --start --system --disallow-exit --disable-shm 2>/dev/null || true
service xrdp start

mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

tail -f /var/log/xrdp-sesman.log /var/log/xrdp.log 2>/dev/null || tail -f /dev/null
