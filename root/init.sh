#!/bin/sh
set -e

UID=`id -u`
GID=`id -g`

echo
echo "UID: $UID"
echo "GID: $GID"
echo

echo "Setting conf"

mkdir /config/ssl
mkdir /aria2_sh
cp /root/aria2_delete.sh /aria2_sh
cp /root/autoremove.sh /aria2_sh

if [[ ! -e /config/aria2.conf ]]
then
  cp /aria2.conf.default /config/aria2.conf
fi

if [[ ! -e /config/aria2.session ]]
then
  touch /config/aria2.session
fi

if [[ ! -e /config/dht.dat ]]
then
  touch /config/dht.dat
fi

echo "[DONE]"

echo "Setting owner and permissions"

chown -R $UID:$GID /config
find /config -type d -exec chmod 755 {} +
find /config -type f -exec chmod 644 {} +

chown -R $UID:$GID /aria2_sh
find /aria2_sh -type d -exec chmod 777 {} +
find /aria2_sh -type f -exec chmod 777 {} +

#设置时区
ln -sf /usr/share/zoneinfo/$TZ   /etc/localtime 
echo $TZ > /etc/timezone

echo "[DONE]"

echo "Starting aria2c"

exec aria2c \
    --conf-path=/config/aria2.conf \
  > /dev/stdout \
  2 > /dev/stderr

echo 'Exiting aria2'
