FROM superng6/alpine:3.20 AS builder

# download static aria2c && AriaNg AllInOne
RUN apk add --no-cache wget unzip curl \
    && wget -qO- https://api.github.com/repos/mayswind/AriaNg/releases/latest \
    | grep '"tag_name":' \
    | cut -d'"' -f4 \
    | xargs -I {} wget -P /tmp https://github.com/mayswind/AriaNg/releases/download/{}/AriaNg-{}-AllInOne.zip \
    && unzip /tmp/AriaNg-*-AllInOne.zip -d /tmp \
    && curl -fsSL https://raw.githubusercontent.com/SuperNG6/docker-aria2/refs/heads/master/install.sh | bash

# install static aria2c
FROM superng6/alpine:3.20

# set label
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UT=true SECRET=yourtoken CACHE=128M QUIET=true \
    SMD=true RUT=true PORT=6800 WEBUI=true WEBUI_PORT=8080 BTPORT=32516 \
    PUID=1026 PGID=100

# copy local files && aria2c
COPY root/ /
COPY darkhttpd/ /etc/cont-init.d/
COPY --from=builder /tmp/index.html /www/index.html
COPY --from=builder /usr/local/bin/aria2c /usr/local/bin/aria2c

# install
RUN apk add --no-cache darkhttpd curl jq findutils \
    && chmod a+x /usr/local/bin/aria2c \
    && ARIANG_VER=$(wget -qO- https://api.github.com/repos/mayswind/AriaNg/tags | grep 'name' | cut -d\" -f4 | head -1 ) \
    && echo "docker-aria2-$(date +"%Y-%m-%d")" > /aria2/build-date \
    && echo "docker-ariang-$ARIANG_VER" >> /aria2/build-date \
    && rm -rf /var/cache/apk/* /tmp/*

# volume
VOLUME /config /downloads /www

EXPOSE 8080 6800 32516 32516/udp
