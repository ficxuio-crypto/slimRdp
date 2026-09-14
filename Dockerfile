FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PORT=3389 \
    ROOT_PASSWORD=root

RUN apt-get update && apt-get install -y \
    xrdp \
    xorgxrdp \
    xfce4 \
    xfce4-goodies \
    xorg \
    dbus-x11 \
    sudo \
    curl \
    wget \
    nano \
    net-tools \
    procps \
    policykit-1 \
    pulseaudio \
    firefox-esr \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN echo "root:root" | chpasswd

RUN mkdir -p /etc/X11 \
    && echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

RUN echo "startxfce4" > /root/.xsession && chmod 700 /root/.xsession

RUN mkdir -p /var/run/dbus && dbus-uuidgen > /var/lib/dbus/machine-id

RUN echo "exec startxfce4" > /etc/xrdp/startwm.sh \
    && chmod +x /etc/xrdp/startwm.sh

RUN adduser xrdp ssl-cert 2>/dev/null || true

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 3389

CMD ["/start.sh"]
