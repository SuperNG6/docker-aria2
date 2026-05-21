FROM superng6/alpine:3.22 AS builder

# download static aria2c && AriaNg AllInOne
RUN apk add --no-cache curl wget unzip \
    && ARIANG_VER=$(wget -qO- https://api.github.com/repos/mayswind/AriaNg/tags | grep 'name' | cut -d\" -f4 | head -1 ) \
    && wget -P /tmp https://github.com/mayswind/AriaNg/releases/download/${ARIANG_VER}/AriaNg-${ARIANG_VER}-AllInOne.zip \
    && unzip /tmp/AriaNg-${ARIANG_VER}-AllInOne.zip -d /tmp \
    && curl -fsSL https://git.io/docker-aria2c.sh | bash

FROM superng6/alpine:3.22

ARG VARIANT=standard
ARG A2B_DEFAULT=false

LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UT=true SECRET=yourtoken CACHE=128M QUIET=true \
    SMD=true RUT=true PORT=6800 WEBUI=true WEBUI_PORT=8080 BTPORT=32516 \
    PUID=1026 PGID=100 CRA2B=2h A2B_DISABLE_LOG=false
ENV A2B=${A2B_DEFAULT}

COPY root/ /
COPY --from=builder /tmp/index.html /www/index.html
COPY --from=builder /usr/local/bin/aria2c /usr/local/bin/aria2c

RUN apk add --no-cache darkhttpd curl jq findutils \
    && chmod a+x /usr/local/bin/aria2c \
    && if [ "${VARIANT}" = "a2b" ]; then \
         apk add --no-cache iptables ip6tables ipset nodejs && \
         A2B_VER=$(curl -fsSL https://api.github.com/repos/makeding/aria2b/tags | grep 'name' | cut -d\" -f4 | head -1) && \
         curl -fsSL "https://github.com/makeding/aria2b/releases/download/${A2B_VER}/aria2b" -o /usr/local/bin/aria2b && \
         chmod a+x /usr/local/bin/aria2b; \
       else \
         rm -rf /etc/services.d/aria2b; \
       fi \
    && ARIANG_VER=$(curl -fsSL https://api.github.com/repos/mayswind/AriaNg/tags | grep 'name' | cut -d\" -f4 | head -1) \
    && echo "docker-aria2-$(date +"%Y-%m-%d")" > /aria2/build-date \
    && echo "docker-ariang-${ARIANG_VER}" >> /aria2/build-date \
    && if [ "${VARIANT}" = "a2b" ]; then echo "docker-aria2b-${A2B_VER}" >> /aria2/build-date; fi \
    && rm -rf /var/cache/apk/* /tmp/*

VOLUME /config /downloads

EXPOSE 8080 6800 32516 32516/udp
