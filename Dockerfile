FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PORT=3389 \
    ROOT_PASSWORD=root \
    LIBGL_ALWAYS_SOFTWARE=1

# 1. Install minimal desktop, XRDP, network tools, and essentials
RUN apt-get update && apt-get install -y --no-install-recommends \
    xrdp \
    xorgxrdp \
    xfwm4 \
    xfce4-session \
    xfce4-panel \
    xfce4-terminal \
    thunar \
    dbus-x11 \
    sudo \
    procps \
    net-tools \
    iputils-ping \
    openssl \
    fonts-dejavu-core \
    locales \
    ca-certificates \
    curl \
    wget \
    nano \
    python3 \
    python3-pip \
    firefox-esr \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 2. Configure locale
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# 3. Prepare required directories & permissions
RUN mkdir -p /run/dbus /var/run/xrdp /tmp/.X11-unix /etc/xrdp \
    /root/.config/xfce4/xfconf/xfce-perchannel-xml \
    && chmod 1777 /tmp/.X11-unix \
    && adduser xrdp ssl-cert 2>/dev/null || true

# 4. XRDP performance tuning for minimum latency, low CPU & RAM
RUN sed -i 's/^[[:space:]]*AllowRootLogin=.*/AllowRootLogin=true/' /etc/xrdp/sesman.ini \
    && sed -i 's/^[[:space:]]*KillDisconnected=.*/KillDisconnected=true/' /etc/xrdp/sesman.ini \
    && sed -i -e '/^[[:space:]]*port[[:space:]]*=/d' \
              -e '/^[[:space:]]*max_bpp[[:space:]]*=/d' \
              -e '/^[[:space:]]*xserverbpp[[:space:]]*=/d' \
              -e '/^[[:space:]]*crypt_level[[:space:]]*=/d' \
              -e '/^[[:space:]]*use_compression[[:space:]]*=/d' /etc/xrdp/xrdp.ini \
    && sed -i '/^\[Globals\]/a port=3389\nmax_bpp=16\nxserverbpp=16\ncrypt_level=low\nuse_compression=yes' /etc/xrdp/xrdp.ini

# 5. Disable compositor & animations to eliminate CPU spikes & GPU stalls
RUN cat <<'EOF' > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="box_resize" type="bool" value="true"/>
    <property name="box_move" type="bool" value="true"/>
  </property>
</channel>
EOF

# 6. Optimized session launcher with root environment setup
RUN cat <<'EOF' > /etc/xrdp/startwm.sh
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export HOME=/root
export USER=root
exec dbus-launch --exit-with-session xfce4-session
EOF
RUN chmod +x /etc/xrdp/startwm.sh

# 7. Robust Entrypoint supporting Railway/Cloud $PORT, auto cert generation & self-healing
RUN cat <<'EOF' > /entrypoint.sh
#!/bin/sh
set -e

# Update root password dynamically (default: root)
PASS="${ROOT_PASSWORD:-root}"
echo "root:${PASS}" | chpasswd

# Respect dynamic PORT environment variable (standard on Railway, Render, etc.)
RDP_PORT="${PORT:-3389}"
sed -i -E "s/^[[:space:]]*port=[0-9]+/port=${RDP_PORT}/g" /etc/xrdp/xrdp.ini

# Clean stale sockets and lock files
rm -rf /var/run/xrdp/* /tmp/.X11-unix/* /tmp/.X* /run/xrdp.pid /run/xrdp-sesman.pid /run/dbus/pid 2>/dev/null || true
mkdir -p /run/dbus /var/run/xrdp /tmp/.X11-unix /etc/xrdp
chmod 1777 /tmp/.X11-unix

# Generate TLS certificates if missing or empty
if [ ! -s /etc/xrdp/cert.pem ] || [ ! -s /etc/xrdp/key.pem ]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /etc/xrdp/key.pem \
        -out /etc/xrdp/cert.pem \
        -days 3650 \
        -subj "/CN=debian-xrdp" 2>/dev/null || true
    chmod 600 /etc/xrdp/key.pem
    chmod 644 /etc/xrdp/cert.pem
    chown root:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem 2>/dev/null || true
fi

# Generate Machine ID for D-Bus
if [ ! -f /etc/machine-id ] || [ ! -s /etc/machine-id ]; then
    dbus-uuidgen --ensure=/etc/machine-id
fi
mkdir -p /var/lib/dbus
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Start D-Bus system bus daemon
dbus-daemon --system --fork 2>/dev/null || true

# Start XRDP Session Manager
/usr/sbin/xrdp-sesman

echo "=========================================================="
echo " Debian XRDP Server is ready!"
echo " Listening on Port: ${RDP_PORT}"
echo " Default Username : root"
echo "=========================================================="

# Start XRDP in foreground
exec /usr/sbin/xrdp -nodaemon
EOF
RUN chmod +x /entrypoint.sh

EXPOSE 3389

CMD ["/entrypoint.sh"]
