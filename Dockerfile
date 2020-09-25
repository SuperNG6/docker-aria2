FROM lsiobase/alpine:3.12 as builder
# ARIANG_VER
ARG ARIANG_VER=1.1.6
# download static aria2c && AriaNg AllInOne
RUN apk add --no-cache curl unzip \
&& wget -P /tmp https://github.com/mayswind/AriaNg/releases/download/${ARIANG_VER}/AriaNg-${ARIANG_VER}-AllInOne.zip \
&& unzip /tmp/AriaNg-${ARIANG_VER}-AllInOne.zip -d /tmp \
&& curl -fsSL git.io/aria2c.sh | bash

# install static aria2c
FROM lsiobase/alpine:3.12

# set label
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UT=true SECRET=yourtoken CACHE=128M QUIET=true \
RECYCLE=false MOVE=false SMD=false FA=falloc CF=false \
ANIDIR=ani MOVDIR=movies TVDIR=tv \
RUT=true ADDRESS=127.0.0.1 PORT=6800 \
CUSDIR=cusdir \
PUID=1026 PGID=100

# copy local files && aria2c
COPY root/ /
COPY --from=builder /tmp/index.html /www/index.html
COPY --from=builder /usr/local/bin/aria2c /usr/local/bin/aria2c
# install darkhttpd
RUN apk add --no-cache darkhttpd curl findutils
# permissions
RUN chmod a+x /usr/local/bin/aria2c
# volume
VOLUME /config /downloads /www

EXPOSE 80  6881  6881/udp
