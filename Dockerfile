FROM lsiobase/alpine:3.8

# set label
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai SECRET=yourtoken

# arg
ARG aria2-static-builds_VER=1.35.0

# copy local files
COPY root/ /

# install aria2-static
RUN wget --no-check-certificate https://github.com/q3aql/aria2-static-builds/releases/download/${aria2-static-builds_VER}/aria2-${BaiduPbuilds_VERCSGo_VER}-linux-gnu-64bit-build1.tar.bz2 \
&&  tar -jxvf aria2-${BaiduPbuilds_VERCSGo_VER}-linux-gnu-64bit-build1.tar.bz2 \
&&  mv aria2-${BaiduPbuilds_VERCSGo_VER}-linux-gnu-64bit-build1/aria2c /usr/bin/aria2c \
&&  rm -rf aria2-${BaiduPbuilds_VERCSGo_VER}-linux-gnu-64bit-build1  \
&&  chmod a+x /usr/bin/aria2c

# permissions
RUN chmod 755 /usr/bin/aria2c

VOLUME /config /downloads

EXPOSE 6800  6881  6881/udp
