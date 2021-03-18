FROM lsiobase/alpine:3.13 as builder

# download static aria2c
RUN apk add --no-cache curl \
&& curl -fsSL https://git.io/docker-aria2c.sh | bash

# install static aria2c
FROM lsiobase/alpine:3.13

# set label
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UT=true SECRET=yourtoken CACHE=128M QUIET=true \
SMD=true RUT=true PORT=6800 \
PUID=1026 PGID=100

# copy local files && aria2c
COPY root/ /
COPY --from=builder /usr/local/bin/aria2c /usr/local/bin/aria2c

# permissions
RUN apk add --no-cache curl jq findutils \
&& chmod a+x /usr/local/bin/aria2c \
&& rm -rf /var/cache/apk/* /tmp/*

VOLUME /config /downloads

EXPOSE 6800  6881  6881/udp
