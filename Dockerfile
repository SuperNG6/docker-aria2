FROM lsiobase/alpine:3.11 as builder

# download static aria2c
RUN apk add --no-cache curl \
&& curl -fsSL git.io/aria2c.sh | bash


# install static aria2c
FROM lsiobase/alpine:3.11

# set label
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UpdateTracker=true SECRET=yourtoken CACHE=128M QUIET=true \
RECYCLE=true MOVE=true \
PUID=1026 PGID=100

# copy local files && aria2c
COPY root/ /
COPY --from=builder  /usr/local/bin/aria2c  /usr/local/bin/aria2c

# permissions
RUN chmod a+x /usr/local/bin/aria2c

VOLUME /config /downloads

EXPOSE 6800  6881  6881/udp
