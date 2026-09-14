#!/bin/bash

# Update root password dynamically (default: root)
PASS="${ROOT_PASSWORD:-root}"
echo "root:${PASS}" | chpasswd

# Respect dynamic PORT environment variable (Railway / Cloud)
RDP_PORT="${PORT:-3389}"
sed -i -E "s/^[[:space:]]*port=[0-9]+/port=${RDP_PORT}/g" /etc/xrdp/xrdp.ini

# Start D-Bus service
service dbus start || service dbus restart

# Start XRDP service
service xrdp start || service xrdp restart

# Prepare runtime X11 socket directory
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

echo "=============================================="
echo "      XRDP SERVER IS RUNNING SMOOTHLY         "
echo "=============================================="
echo " Listening Port : ${RDP_PORT}"
echo " Username       : root"
echo " Password       : ${PASS}"
echo "=============================================="

# Keep container alive by tailing log
tail -f /var/log/xrdp-sesman.log /var/log/xrdp.log 2>/dev/null || tail -f /dev/null
