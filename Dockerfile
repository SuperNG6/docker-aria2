FROM superng6/alpine:3.22 AS builder

# download static aria2c && AriaNg AllInOne
RUN apk add --no-cache curl wget unzip \
    && ARIANG_VER=$(wget -qO- https://api.github.com/repos/mayswind/AriaNg/tags | grep 'name' | cut -d\" -f4 | head -1 ) \
    && wget -P /tmp https://github.com/mayswind/AriaNg/releases/download/${ARIANG_VER}/AriaNg-${ARIANG_VER}-AllInOne.zip \
    && unzip /tmp/AriaNg-${ARIANG_VER}-AllInOne.zip -d /tmp \
    && curl -fsSL https://git.io/docker-aria2c.sh | bash \
    && echo "docker-aria2-$(date +"%Y-%m-%d")" > /tmp/build-date \
    && echo "docker-ariang-$ARIANG_VER" >> /tmp/build-date

# install static aria2c
FROM superng6/alpine:3.22

LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UT=true SECRET=yourtoken CACHE=128M QUIET=true \
    SMD=true RUT=true PORT=6800 WEBUI=true WEBUI_PORT=8080 BTPORT=32516 \
    PUID=1026 PGID=100

# copy stable files first
COPY --from=builder /tmp/index.html /www/index.html
COPY --from=builder /tmp/build-date /aria2/build-date
COPY --from=builder /usr/local/bin/aria2c /usr/local/bin/aria2c

# install packages
RUN apk add --no-cache darkhttpd jq findutils \
    && chmod a+x /usr/local/bin/aria2c \
    && rm -rf /var/cache/apk/* /tmp/*

# copy application files
COPY root/ /

VOLUME /config /downloads /www

EXPOSE 8080 6800 32516 32516/udp

