# docker_aria2的最佳实践
Docker Hub地址：https://hub.docker.com/r/superng6/aria2 

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
- 纯aria2，没有包含多于的服务
- 开放了BT下载DTH监听端口、BT下载监听端口（TCP/UDP 6881），加快下载速度
- 默认开启DHT并且创建了DHT文件，加速下载
- 包含了下载完成后自动删除.aria2文件脚本
- 包含了执行删除文件操作时自动执行删除.aria2文件的脚本
- 内置最优的aria2配置文件


# Document
## 在线webui
我在gitee上构建了基于ariang主线稳定版的在线webui：
https://sleele.gitee.io/#!/downloading
## 挂载路径
``/config`` ``/downloads``
## 默认关闭SSL，如需需要请手动开启
之所以默认关闭SSL(建议开启)，是因为如果开启，又没有配置证书，会导致arai2启动失败，所以如果需要开启请手动编辑aria2.conf
证书请放在``/config/ssl``目录下
删掉24,26,28行的``#``号
![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-09-27_19-35-32.png)
## 修改RPC token
填写你自己的token,越长越好，建议使用生成的UUID
![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-09-27_19-40-40.png)

## 关于群晖
群晖用户请用你当前用户SSH进系统，输入 ``id`` 获取到你的UID和GID并输入进去

![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-09-27_19-17-57.png)
![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-09-27_19-19-02.png)
![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-09-27_19-20-03.png)

## Linux
输入 ``id`` 获取到你的UID和GID，替换命令中的PUID、PGID
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
docker-compose  
  ````
  version: "2"
services:
  aria2:
    image: superng6/aria2
    container_name: aria2
    environment:
      - PUID=1026
      - PGID=100
      - TZ=Asia/Shanghai
    volumes:
      - /path/to/appdata/config:/config
      - /path/to/downloads:/downloads
    ports:
      - 6881:6881
      - 6881:6881/udp
      - 6800:6800
    restart: unless-stopped   
````
