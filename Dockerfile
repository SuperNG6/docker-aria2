FROM superng6/alpine:3.23 AS builder

# download static aria2c (SuperNG6/Aria2-Pro-Core) && AriaNg AllInOne
# 用 uname -m 检测构建环境的 CPU 架构（buildx with QEMU 时构建器本身就是目标架构）
RUN apk add --no-cache curl wget unzip \
    && ARIANG_VER=$(wget -qO- https://api.github.com/repos/mayswind/AriaNg/tags | grep 'name' | cut -d\" -f4 | head -1 ) \
    && wget -P /tmp https://github.com/mayswind/AriaNg/releases/download/${ARIANG_VER}/AriaNg-${ARIANG_VER}-AllInOne.zip \
    && unzip /tmp/AriaNg-${ARIANG_VER}-AllInOne.zip -d /tmp \
    && case "$(uname -m)" in \
         x86_64)        ARIA2_ARCH=x86_64 ;; \
         aarch64)       ARIA2_ARCH=arm64 ;; \
         armv7l|armv6l) ARIA2_ARCH=armhf ;; \
         i386|i686)     ARIA2_ARCH=i386 ;; \
         *) echo "unsupported arch: $(uname -m)"; exit 1 ;; \
       esac \
    && ARIA2_REL=$(wget -qO- https://api.github.com/repos/SuperNG6/Aria2-Pro-Core/releases/latest | grep '"tag_name"' | cut -d\" -f4) \
    && wget -O /tmp/aria2.tar.gz "https://github.com/SuperNG6/Aria2-Pro-Core/releases/download/${ARIA2_REL}/aria2-static-linux-${ARIA2_ARCH}.tar.gz" \
    && tar -xzf /tmp/aria2.tar.gz -C /usr/local/bin

FROM superng6/alpine:3.23

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
         A2B_VER=$(curl -fsSL https://api.github.com/repos/SuperNG6/aria2b/tags | grep 'name' | cut -d\" -f4 | head -1) && \
         curl -fsSL "https://github.com/SuperNG6/aria2b/releases/download/${A2B_VER}/aria2b" -o /usr/local/bin/aria2b && \
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
