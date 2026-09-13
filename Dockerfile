FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PORT=3389 \
    ROOT_PASSWORD=root \
    LIBGL_ALWAYS_SOFTWARE=1 \
    DONT_PROMPT_WSL_INSTALL=1

# 1. Install Xorg server, X11 utilities, full XFCE desktop components, and XRDP
RUN apt-get update && apt-get install -y --no-install-recommends \
    xserver-xorg-core \
    xorgxrdp \
    xrdp \
    x11-xserver-utils \
    x11-utils \
    x11-xkb-utils \
    xauth \
    xinit \
    xfwm4 \
    xfce4-session \
    xfce4-panel \
    xfce4-terminal \
    xfce4-settings \
    xfdesktop4 \
    thunar \
    dbus-x11 \
    sudo \
    procps \
    net-tools \
    iputils-ping \
    openssl \
    fonts-dejavu-core \
    fonts-freefont-ttf \
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

# 3. Allow anybody to start Xorg server (fixes root/non-console Xorg permission crashes)
RUN mkdir -p /etc/X11 \
    && echo "allowed_users=anybody" > /etc/X11/Xwrapper.config \
    && echo "needs_root_rights=yes" >> /etc/X11/Xwrapper.config

# 4. Prepare runtime directories & group permissions
RUN mkdir -p /run/dbus /var/run/xrdp /tmp/.X11-unix /etc/xrdp \
    /root/.config/xfce4/xfconf/xfce-perchannel-xml \
    && chmod 1777 /tmp/.X11-unix \
    && adduser xrdp ssl-cert 2>/dev/null || true

# 5. XRDP & sesman configuration for seamless root login and high compatibility
RUN sed -i 's/^[[:space:]]*AllowRootLogin=.*/AllowRootLogin=true/' /etc/xrdp/sesman.ini \
    && sed -i 's/^[[:space:]]*KillDisconnected=.*/KillDisconnected=true/' /etc/xrdp/sesman.ini \
    && sed -i 's/^[[:space:]]*FuseMountName=.*/FuseMountName=thinclient_drives/' /etc/xrdp/sesman.ini \
    && sed -i -e '/^[[:space:]]*port[[:space:]]*=/d' \
              -e '/^[[:space:]]*crypt_level[[:space:]]*=/d' /etc/xrdp/xrdp.ini \
    && sed -i '/^\[Globals\]/a port=3389\ncrypt_level=low' /etc/xrdp/xrdp.ini

# Disable pam_systemd and pam_loginuid in xrdp-sesman pam if present to prevent container session hang
RUN if [ -f /etc/pam.d/xrdp-sesman ]; then \
        sed -i '/pam_systemd.so/d' /etc/pam.d/xrdp-sesman; \
        sed -i '/pam_loginuid.so/d' /etc/pam.d/xrdp-sesman; \
    fi

# 6. Disable compositor & animations in XFCE for low CPU / instant rendering
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

# 7. Create root default .xsession and /etc/skel/.xsession
RUN echo "startxfce4" > /root/.xsession \
    && echo "startxfce4" > /root/.Xclients \
    && chmod +x /root/.xsession

# 8. StartWM script with clean environment variables
RUN cat <<'EOF' > /etc/xrdp/startwm.sh
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export DESKTOP_SESSION=xfce
export XDG_CONFIG_DIRS=/etc/xdg
export HOME=/root
export USER=root

if [ -r /etc/profile ]; then
    . /etc/profile
fi

if [ -f /root/.xsession ]; then
    exec /bin/sh /root/.xsession
else
    exec /usr/bin/startxfce4
fi
EOF
RUN chmod +x /etc/xrdp/startwm.sh

# 9. Container Entrypoint
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
mkdir -p /run/dbus /var/run/xrdp /tmp/.X11-unix /etc/xrdp /var/log
chmod 1777 /tmp/.X11-unix

# Generate TLS certificates if missing
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

# D-Bus Machine ID setup
if [ ! -f /etc/machine-id ] || [ ! -s /etc/machine-id ]; then
    dbus-uuidgen --ensure=/etc/machine-id
fi
mkdir -p /var/lib/dbus
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Start D-Bus system bus
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
