FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PORT=3389 \
    ROOT_PASSWORD=root

# 1. Install desktop packages, Xorg backend, XRDP, and system utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    xrdp \
    xorgxrdp \
    xorg \
    xfce4 \
    xfce4-goodies \
    xfce4-terminal \
    dbus-x11 \
    policykit-1 \
    sudo \
    curl \
    wget \
    nano \
    net-tools \
    procps \
    ca-certificates \
    locales \
    fonts-dejavu-core \
    firefox-esr \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 2. Configure locale
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# 3. Allow non-console users to start X server
RUN mkdir -p /etc/X11 \
    && echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

# 4. Create root session configuration
RUN echo "startxfce4" > /root/.xsession && chmod 700 /root/.xsession

# 5. Prepare dbus machine-id
RUN mkdir -p /var/run/dbus && dbus-uuidgen > /var/lib/dbus/machine-id

# 6. Configure XRDP settings
RUN sed -i 's/crypt_level=high/crypt_level=low/' /etc/xrdp/xrdp.ini \
    && sed -i 's/security_layer=negotiate/security_layer=rdp/' /etc/xrdp/xrdp.ini \
    && echo "exec startxfce4" > /etc/xrdp/startwm.sh \
    && chmod +x /etc/xrdp/startwm.sh

# 7. Add xrdp user to ssl-cert group
RUN adduser xrdp ssl-cert 2>/dev/null || true

# 8. Copy start.sh script
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 3389

CMD ["/start.sh"]
