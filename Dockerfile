FROM lsiobase/alpine:3.9

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="sleele.com version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai

RUN \
    && apk add --no-cache aria2

# copy local files
COPY root/ /

VOLUME /config /downloads

EXPOSE 6800  6881  6881/udp
