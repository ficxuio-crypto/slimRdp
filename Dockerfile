FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PORT=3389 \
    ROOT_PASSWORD=root \
    LIBGL_ALWAYS_SOFTWARE=1 \
    DONT_PROMPT_WSL_INSTALL=1

# 1. Install TigerVNC server, Xorg backend, full XFCE, Polkit, D-Bus, and network tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    xrdp \
    tigervnc-standalone-server \
    tigervnc-common \
    xserver-xorg-core \
    xorgxrdp \
    x11-xserver-utils \
    x11-utils \
    xauth \
    xinit \
    xfce4 \
    xfce4-terminal \
    dbus \
    dbus-x11 \
    policykit-1 \
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

# 3. Create default non-root user (debian:debian) with passwordless sudo
RUN useradd -m -s /bin/bash -u 1000 debian \
    && echo "debian:debian" | chpasswd \
    && usermod -aG sudo debian \
    && echo "debian ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 4. Xwrapper config for root & non-root Xorg execution
RUN mkdir -p /etc/X11 \
    && echo "allowed_users=anybody" > /etc/X11/Xwrapper.config \
    && echo "needs_root_rights=yes" >> /etc/X11/Xwrapper.config

# 5. XRDP & sesman configuration (Supports root login, security_layer=rdp, and Xvnc/Xorg)
RUN sed -i 's/^[[:space:]]*AllowRootLogin=.*/AllowRootLogin=true/' /etc/xrdp/sesman.ini \
    && sed -i 's/^[[:space:]]*KillDisconnected=.*/KillDisconnected=true/' /etc/xrdp/sesman.ini \
    && sed -i 's/^[[:space:]]*FuseMountName=.*/FuseMountName=thinclient_drives/' /etc/xrdp/sesman.ini \
    && sed -i -e '/^[[:space:]]*port[[:space:]]*=/d' \
              -e '/^[[:space:]]*crypt_level[[:space:]]*=/d' \
              -e '/^[[:space:]]*security_layer[[:space:]]*=/d' /etc/xrdp/xrdp.ini \
    && sed -i '/^\[Globals\]/a port=3389\ncrypt_level=low\nsecurity_layer=rdp' /etc/xrdp/xrdp.ini \
    && adduser xrdp ssl-cert 2>/dev/null || true

# Disable PAM systemd modules inside container to prevent login session stalls
RUN if [ -f /etc/pam.d/xrdp-sesman ]; then \
        sed -i '/pam_systemd.so/d' /etc/pam.d/xrdp-sesman; \
        sed -i '/pam_loginuid.so/d' /etc/pam.d/xrdp-sesman; \
    fi

# 6. Disable window compositor in XFCE for instant software rendering & low CPU usage
RUN mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
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
RUN cp /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml \
    && mkdir -p /home/debian/.config/xfce4/xfconf/xfce-perchannel-xml \
    && cp /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml /home/debian/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml \
    && chown -R debian:debian /home/debian/.config

# 7. Create default .xsession and .Xauthority
RUN echo "exec dbus-run-session -- xfce4-session" > /etc/skel/.xsession \
    && cp /etc/skel/.xsession /home/debian/.xsession \
    && chown debian:debian /home/debian/.xsession \
    && chmod +x /home/debian/.xsession \
    && cp /etc/skel/.xsession /root/.xsession \
    && chmod +x /root/.xsession \
    && touch /root/.Xauthority /home/debian/.Xauthority \
    && chown debian:debian /home/debian/.Xauthority

# 8. StartWM launcher script
RUN cat <<'EOF' > /etc/xrdp/startwm.sh
#!/bin/sh
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

if [ -z "$USER" ]; then
    export USER="$(id -un)"
fi
if [ -z "$HOME" ]; then
    export HOME="$(getent passwd "$USER" | cut -d: -f6)"
fi

export XDG_RUNTIME_DIR="/tmp/runtime-${USER}"
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

if [ -f "$HOME/.xsession" ]; then
    exec /bin/sh "$HOME/.xsession"
else
    exec dbus-run-session -- xfce4-session
fi
EOF
RUN chmod +x /etc/xrdp/startwm.sh

# 9. Clean, robust start entrypoint
RUN cat <<'EOF' > /entrypoint.sh
#!/bin/sh
set -e

# Update credentials dynamically
PASS="${ROOT_PASSWORD:-root}"
echo "root:${PASS}" | chpasswd

RDP_PORT="${PORT:-3389}"
sed -i -E "s/^[[:space:]]*port=[0-9]+/port=${RDP_PORT}/g" /etc/xrdp/xrdp.ini

# Reset sockets, stale locks, and temporary runtimes
rm -rf /var/run/xrdp/* /tmp/.X11-unix/* /tmp/.X* /run/xrdp.pid /run/xrdp-sesman.pid /run/dbus/pid /tmp/runtime-* 2>/dev/null || true
mkdir -p /run/dbus /var/run/dbus /var/run/xrdp /tmp/.X11-unix /etc/xrdp /var/log
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

# D-Bus Machine ID
if [ ! -f /etc/machine-id ] || [ ! -s /etc/machine-id ]; then
    dbus-uuidgen --ensure=/etc/machine-id
fi
mkdir -p /var/lib/dbus
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Start D-Bus system daemon
dbus-daemon --system --fork 2>/dev/null || true

# Start XRDP session manager
/usr/sbin/xrdp-sesman

echo "=========================================================="
echo " 🚀 Debian XRDP Desktop is Ready!"
echo " Listening on Port : ${RDP_PORT}"
echo " Root User         : root (Password: ${PASS})"
echo " Standard User     : debian (Password: debian)"
echo " Supported Backends: Xorg & Xvnc (TigerVNC)"
echo "=========================================================="

# Start XRDP in foreground
exec /usr/sbin/xrdp -nodaemon
EOF
RUN chmod +x /entrypoint.sh

EXPOSE 3389

CMD ["/entrypoint.sh"]
