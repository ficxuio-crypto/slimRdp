FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PORT=3389 \
    ROOT_PASSWORD=root

# ── 1. Packages ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    xrdp \
    tigervnc-standalone-server \
    tigervnc-common \
    xfce4 \
    xfce4-terminal \
    dbus \
    dbus-x11 \
    policykit-1 \
    sudo \
    openssl \
    locales \
    ca-certificates \
    curl \
    wget \
    nano \
    procps \
    net-tools \
    python3 \
    fonts-dejavu-core \
    firefox-esr \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── 2. Locale ─────────────────────────────────────────────────────────────────
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8

# ── 3. XRDP config — written fresh, no sed on existing files ─────────────────
RUN adduser xrdp ssl-cert 2>/dev/null || true

RUN cat > /etc/xrdp/xrdp.ini << 'XRDPINI'
[Globals]
ini_version=1
fork=yes
port=3389
tcp_send_buffer_bytes=32768
authentication_info_required=yes
use_vsock=false
security_layer=rdp
crypt_level=low
certificate=
key_file=
channel_code=1
max_bpp=32
xserverbpp=16
new_cursors=yes
use_fastpath=both
use_compression=yes

[Xvnc]
name=Xvnc
lib=libvnc.so
username=ask
password=ask
ip=127.0.0.1
port=-1
XRDPINI

RUN cat > /etc/xrdp/sesman.ini << 'SESINI'
[Globals]
ListenAddress=127.0.0.1
ListenPort=3350
EnableUserWindowManager=1
UserWindowManager=startwm.sh
DefaultWindowManager=startwm.sh
[Security]
AllowRootLogin=true
MaxLoginRetry=4
TerminalServerUsers=tsusers
TerminalServerAdmins=tsadmins
[Sessions]
MaxSessions=50
KillDisconnected=false
IdleTimeLimit=0
DisconnectedTimeLimit=0
[Logging]
LogFile=/var/log/xrdp-sesman.log
LogLevel=INFO
EnableSyslog=false
[X11DisplayOffset]
X11DisplayOffset=10
MaxDisplays=50
SESINI

# ── 4. PAM — remove systemd/loginuid modules that crash in containers ─────────
RUN if [ -f /etc/pam.d/xrdp-sesman ]; then \
      grep -v 'pam_systemd\|pam_loginuid' /etc/pam.d/xrdp-sesman > /tmp/p \
      && mv /tmp/p /etc/pam.d/xrdp-sesman; \
    fi

# ── 5. Session launcher ───────────────────────────────────────────────────────
RUN cat > /etc/xrdp/startwm.sh << 'STARTWM'
#!/bin/sh
if [ -z "$USER" ]; then USER="$(id -un)"; fi
if [ -z "$HOME" ]; then HOME="$(getent passwd "$USER" | cut -d: -f6)"; fi
export USER HOME
export XDG_RUNTIME_DIR="/tmp/run-${USER}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
export XDG_CONFIG_DIRS=/etc/xdg
unset DBUS_SESSION_BUS_ADDRESS SESSION_MANAGER
exec dbus-run-session -- xfce4-session
STARTWM
RUN chmod +x /etc/xrdp/startwm.sh

# ── 6. XFCE: disable compositor ──────────────────────────────────────────────
RUN mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml \
             /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml

RUN cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'XFWM'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="box_resize" type="bool" value="true"/>
    <property name="box_move" type="bool" value="true"/>
  </property>
</channel>
XFWM

RUN cp /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml \
       /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml

# ── 7. Entrypoint ─────────────────────────────────────────────────────────────
RUN cat > /entrypoint.sh << 'ENTRY'
#!/bin/sh
set -e

echo "root:${ROOT_PASSWORD:-root}" | chpasswd

RDP_PORT="${PORT:-3389}"
python3 -c "
import re
path='/etc/xrdp/xrdp.ini'
txt=open(path).read()
txt=re.sub(r'^port\s*=\s*\S+','port=$RDP_PORT',txt,flags=re.MULTILINE)
open(path,'w').write(txt)
"

rm -rf /var/run/xrdp /tmp/.X11-unix /tmp/.X* /tmp/run-* /run/dbus/pid 2>/dev/null || true
mkdir -p /run/dbus /var/run/dbus /var/run/xrdp /tmp/.X11-unix /var/log
chmod 1777 /tmp/.X11-unix

if [ ! -s /etc/xrdp/cert.pem ]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem \
        -days 3650 -subj "/CN=rdp" 2>/dev/null
    chmod 600 /etc/xrdp/key.pem && chmod 644 /etc/xrdp/cert.pem
    chown root:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem 2>/dev/null || true
fi

dbus-uuidgen --ensure=/etc/machine-id
mkdir -p /var/lib/dbus
ln -sf /etc/machine-id /var/lib/dbus/machine-id
dbus-daemon --system --fork 2>/dev/null || true

/usr/sbin/xrdp-sesman &
sleep 1

echo "===================================="
echo "  XRDP ready  port=${RDP_PORT}"
echo "  Login: root / ${ROOT_PASSWORD:-root}"
echo "===================================="

exec /usr/sbin/xrdp --nodaemon
ENTRY
RUN chmod +x /entrypoint.sh

EXPOSE 3389
CMD ["/entrypoint.sh"]
