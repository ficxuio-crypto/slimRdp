FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PORT=3389 \
    ROOT_PASSWORD=root \
    LIBGL_ALWAYS_SOFTWARE=1 \
    DONT_PROMPT_WSL_INSTALL=1

# 1. Install base Xorg, complete XFCE desktop, XRDP, and D-Bus tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    xserver-xorg-core \
    xorgxrdp \
    xrdp \
    x11-xserver-utils \
    x11-utils \
    x11-xkb-utils \
    xauth \
    xinit \
    xfce4 \
    xfce4-terminal \
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

# 3. Allow anybody to start Xorg server
RUN mkdir -p /etc/X11 \
    && echo "allowed_users=anybody" > /etc/X11/Xwrapper.config \
    && echo "needs_root_rights=yes" >> /etc/X11/Xwrapper.config

# 4. Prepare runtime directories & group permissions
RUN mkdir -p /run/dbus /var/run/xrdp /tmp/.X11-unix /etc/xrdp \
    /root/.config/xfce4/xfconf/xfce-perchannel-xml \
    && chmod 1777 /tmp/.X11-unix \
    && adduser xrdp ssl-cert 2>/dev/null || true

# 5. XRDP & sesman configuration
RUN sed -i 's/^[[:space:]]*AllowRootLogin=.*/AllowRootLogin=true/' /etc/xrdp/sesman.ini \
    && sed -i 's/^[[:space:]]*KillDisconnected=.*/KillDisconnected=true/' /etc/xrdp/sesman.ini \
    && sed -i 's/^[[:space:]]*FuseMountName=.*/FuseMountName=thinclient_drives/' /etc/xrdp/sesman.ini \
    && sed -i -e '/^[[:space:]]*port[[:space:]]*=/d' \
              -e '/^[[:space:]]*crypt_level[[:space:]]*=/d' /etc/xrdp/xrdp.ini \
    && sed -i '/^\[Globals\]/a port=3389\ncrypt_level=low' /etc/xrdp/xrdp.ini

# Prevent container PAM login hangs
RUN if [ -f /etc/pam.d/xrdp-sesman ]; then \
        sed -i '/pam_systemd.so/d' /etc/pam.d/xrdp-sesman; \
        sed -i '/pam_loginuid.so/d' /etc/pam.d/xrdp-sesman; \
    fi

# 6. Disable compositor for smoother remote rendering
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

# 7. Create root default .xsession with dbus wrapper
RUN echo "exec dbus-run-session -- xfce4-session" > /root/.xsession \
    && chmod +x /root/.xsession

# 8. StartWM script with XDG_RUNTIME_DIR and dbus session wrapper
RUN cat <<'EOF' > /etc/xrdp/startwm.sh
#!/bin/sh
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export HOME=/root
export USER=root

# Set up runtime directory for root
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
export DESKTOP_SESSION=xfce
export XDG_CONFIG_DIRS=/etc/xdg

unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER

if [ -r /etc/profile ]; then
    . /etc/profile
fi

exec dbus-run-session -- xfce4-session
EOF
RUN chmod +x /etc/xrdp/startwm.sh

# 9. Container Entrypoint
RUN cat <<'EOF' > /entrypoint.sh
#!/bin/sh
set -e

PASS="${ROOT_PASSWORD:-root}"
echo "root:${PASS}" | chpasswd

RDP_PORT="${PORT:-3389}"
sed -i -E "s/^[[:space:]]*port=[0-9]+/port=${RDP_PORT}/g" /etc/xrdp/xrdp.ini

# Clean stale sockets, locks, and temporary runtimes
rm -rf /var/run/xrdp/* /tmp/.X11-unix/* /tmp/.X* /run/xrdp.pid /run/xrdp-sesman.pid /run/dbus/pid /tmp/runtime-root 2>/dev/null || true
mkdir -p /run/dbus /var/run/xrdp /tmp/.X11-unix /etc/xrdp /var/log /tmp/runtime-root
chmod 1777 /tmp/.X11-unix
chmod 700 /tmp/runtime-root

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

exec /usr/sbin/xrdp -nodaemon
EOF
RUN chmod +x /entrypoint.sh

EXPOSE 3389

CMD ["/entrypoint.sh"]
