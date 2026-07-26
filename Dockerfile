FROM superng6/alpine:3.23 AS builder

RUN apk add --no-cache unzip

RUN case "$(uname -m)" in \
         x86_64)        ARCH=x86_64 ;; \
         aarch64)       ARCH=arm64 ;; \
         armv7l|armv6l) ARCH=armhf ;; \
         i386|i686)     ARCH=i386 ;; \
         *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/aria2.tar.gz \
       "https://github.com/SuperNG6/Aria2-Pro-Core/releases/latest/download/aria2-static-linux-${ARCH}.tar.gz" \
    && tar -xzf /tmp/aria2.tar.gz -C /usr/local/bin \
    && rm -f /tmp/aria2.tar.gz

RUN LATEST_URL=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
             https://github.com/SuperNG6/AriaNg/releases/latest) \
    && VER=${LATEST_URL##*/} \
    && [ -n "${VER}" ] \
    && curl -fsSL -o /tmp/ariang.zip \
       "https://github.com/SuperNG6/AriaNg/releases/download/${VER}/AriaNg-${VER}-AllInOne.zip" \
    && unzip -o /tmp/ariang.zip -d /tmp \
    && echo "${VER}" > /tmp/ariang.ver


FROM superng6/alpine:3.23

ARG VARIANT=standard
ARG A2B_DEFAULT=false

LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UT=true SECRET=yourtoken CACHE=128M QUIET=true \
    SMD=true RUT=true PORT=6800 WEBUI=true WEBUI_PORT=8080 BTPORT=32516 \
    PUID=1026 PGID=100 CRA2B=2h A2B_DISABLE_LOG=false
ENV A2B=${A2B_DEFAULT}

COPY root/ /
COPY --from=builder /tmp/index.html       /www/index.html
COPY --from=builder /tmp/ariang.ver       /tmp/ariang.ver
COPY --from=builder /usr/local/bin/aria2c /usr/local/bin/aria2c

# 公共依赖：curl/wget 由基础镜像提供，此处只补基础镜像没有的包
RUN apk add --no-cache darkhttpd jq findutils \
    && chmod a+x /usr/local/bin/aria2c

# a2b 变体：装额外包 + 拉 aria2b 二进制；standard 直接删空服务目录
RUN if [ "${VARIANT}" = "a2b" ]; then \
        apk add --no-cache iptables iptables-legacy ipset nodejs && \
        LATEST_URL=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
          https://github.com/SuperNG6/aria2b/releases/latest) && \
        A2B_VER=${LATEST_URL##*/} && \
        [ -n "${A2B_VER}" ] && \
        curl -fsSL "https://github.com/SuperNG6/aria2b/releases/download/${A2B_VER}/aria2b" -o /usr/local/bin/aria2b && \
        chmod a+x /usr/local/bin/aria2b && \
        echo "${A2B_VER}" > /tmp/a2b.ver; \
    else \
        rm -rf /etc/services.d/aria2b; \
    fi

# 版本戳 + 清理
RUN { \
        echo "docker-aria2-$(date +%Y-%m-%d)"; \
        echo "docker-ariang-$(cat /tmp/ariang.ver)"; \
        if [ -f /tmp/a2b.ver ]; then echo "docker-aria2b-$(cat /tmp/a2b.ver)"; fi; \
    } > /aria2/build-date \
    && rm -rf /var/cache/apk/* /tmp/*

VOLUME /config /downloads

EXPOSE 8080 6800 32516 32516/udp
