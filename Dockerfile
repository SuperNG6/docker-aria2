FROM alpine:latest
MAINTAINER AUTHOR=NG6<ng6@aria2.com>

COPY root/ /

RUN set -xe \
    && apk add --no-cache aria2 \
    && chmod +x /init.sh

VOLUME /config /downloads

EXPOSE 6800  6881  6881/udp

ENTRYPOINT ["/init.sh"]
