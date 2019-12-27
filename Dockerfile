FROM lsiobase/alpine:3.8

# set label
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UpdateTracker=false SECRET=yourtoken

# arg
ARG aria2c_v=1.35.0

# install static aria2c
RUN wget --no-check-certificate https://github.com/q3aql/aria2-static-builds/releases/download/v${aria2c_v}/aria2-${aria2c_v}-linux-gnu-64bit-build1.tar.bz2 \
&&  tar -jxvf aria2-${aria2c_v}-linux-gnu-64bit-build1.tar.bz2 \
&&  cp aria2-${aria2c_v}-linux-gnu-64bit-build1/aria2c /usr/bin/aria2c \
&&  rm -rf aria2-${aria2c_v}-linux-gnu-64bit-build1*

# copy local files
COPY root/ /

# permissions
RUN chmod a+x /usr/bin/aria2c

VOLUME /config /downloads

EXPOSE 6800  6881  6881/udp
