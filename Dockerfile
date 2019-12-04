FROM lsiobase/alpine:3.8

# set label
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai SECRET=yourtoken

# copy local files
COPY root/ /
COPY aria2c /usr/bin

# permissions
RUN chmod 755 /usr/bin/aria2c

VOLUME /config /downloads

EXPOSE 6800  6881  6881/udp
