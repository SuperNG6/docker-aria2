# 施工中
## docker_aria2的最佳实践

在茫茫多的docker aria2镜像中，一直找不到符合我需求的镜像
# 我之所以构建这个镜像的原因
__当前的镜像或多或少都有以下几点不符合的我的需求__
   
- 没有配置UID和GID
  > 这关系到你下载的文件都权限问题，默认是root权限，很难管理
- 掺杂了不必要的东西
   > 大量aria2 images都包含了webui，我觉得根本没有必要
   > 随便找一个在线的aria2控制台即可
   > 一个容器最好只跑一个服务
 - 端口不全
   > 绝大多数的aria2 images 都只开放了6800端口
   > 下载速度息息相关的BT下载DTH监听端口、BT下载监听端口，需要expose出来
 - 没有自动删除.aria2文件的自动执行脚本
   > aria2建立下载任务后会自动生成.aria2文件，aria2自身提供了api可以触发执行脚本
   
# 本镜像的一些优点
- 做了usermaping，使用你自己的账户权限来运行，这点对于群辉来说尤其重要
- 纯aria2，没有包含多于的服务，镜像大小只有7M不到
- 开放了BT下载DTH监听端口、BT下载监听端口（TCP/UDP 6881），加快下载速度
- 默认开启DHT并且创建了DHT文件，加速下载
- 包含了下载完成后自动删除.aria2文件脚本
- 包含了执行删除文件操作时自动执行删除.aria2文件的脚本
- 内置最优的aria2配置文件


Docker Hub地址：https://hub.docker.com/r/superng6/aria2 

# Document

__执行命令__
````
docker create \
  --name=aria2 \
  -PUID=1026 \
  -PGID=100 \
  -e TZ=Asia/Shanghai \
  -p 6881:6881 \
  -p 6881:6881/udp \
  -p 6800:6800 \
  -v /path/to/appdata/config:/config \
  -v /path/to/downloads:/downloads \
  --restart unless-stopped \
  superng6/aria2
  ````
