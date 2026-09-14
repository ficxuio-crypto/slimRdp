#!/bin/bash
set -e

# Update password
PASS="${ROOT_PASSWORD:-root}"
echo "root:${PASS}" | chpasswd

# Bind port
RDP_PORT="${PORT:-3389}"
sed -i -E "s/^[[:space:]]*port=[0-9]+/port=${RDP_PORT}/g" /etc/xrdp/xrdp.ini

# Ensure runtime directories exist
mkdir -p /var/run/xrdp /var/run/dbus /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

service dbus start

# Start session manager and XRDP daemon
xrdp-sesman
xrdp

# Keep container alive and stream logs
touch /var/log/xrdp.log /var/log/xrdp-sesman.log
exec tail -f /var/log/xrdp.log /var/log/xrdp-sesman.log
