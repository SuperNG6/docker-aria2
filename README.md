# 施工中
docker_aria2的最佳实践
````
docker create \
  --name=aria2 \
  -u 1026:100
  -e TZ=Asia/Shanghai \
  -p 6881:6881 \
  -p 6881:6881/udp \
  -p 6800:6800 \
  -v /path/to/appdata/config:/config \
  -v /path/to/downloads:/downloads \
  --restart unless-stopped \
  superng6/aria2
  ````
