FROM lsiobase/alpine:3.8

# set label
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UpdateTracker=true SECRET=yourtoken Cache=128M

# arg
ARG aria2c_v=1.35.0

# install static aria2c
COPY aria2c_arm32 /usr/bin/aria2c

# copy local files
COPY root/ /

# permissions
RUN chmod a+x /usr/bin/aria2c

VOLUME /config /downloads

EXPOSE 6800  6881  6881/udp
