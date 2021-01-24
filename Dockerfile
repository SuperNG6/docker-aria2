FROM lsiobase/alpine:3.12 as builder

COPY install.sh /qbittorrent/
# download static aria2c
RUN apk add --no-cache curl \
&& curl -fsSL https://raw.githubusercontent.com/SuperNG6/docker-aria2/master/download.sh | bash

# install static aria2c
FROM lsiobase/alpine:3.12

# set label
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UT=true SECRET=yourtoken CACHE=128M QUIET=true \
SMD=false RUT=true ADDRESS=127.0.0.1 PORT=6800 \
PUID=1026 PGID=100

# copy local files && aria2c
COPY root/ /
COPY --from=builder  /root/aria2c  /usr/local/bin/aria2c

# permissions
RUN apk add --no-cache curl findutils \
&& chmod a+x /usr/local/bin/aria2c \
&& rm -rf /var/cache/apk/* /tmp/*

VOLUME /config /downloads

EXPOSE 6800  6881  6881/udp
