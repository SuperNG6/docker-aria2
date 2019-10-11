# Docker Aria2的最佳实践
Docker Hub：https://hub.docker.com/r/superng6/aria2

GitHub：https://www.github.com/SuperNG6/docker_aria2

博客：https://sleele.com/2019/09/27/docker-aria2的最佳实践/

PS：docker hub的用户是无法看到GitHub中的图片，会显示为框框，具体图文详情可以在我的博客上浏览

>在茫茫多的docker aria2镜像中，一直找不到符合我需求的镜像

# 之所以构建这个镜像的原因
__当前的镜像或多或少都有以下几点不符合的我的需求__
   
- 没有配置UID和GID
  > 这关系到你下载的文件的权限问题，默认是root权限，很难管理
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
- 做了usermapping，使用你自己的账户权限来运行，这点对于群辉来说尤其重要
- 纯aria2，没有包含多于的服务
- 开放了BT下载DTH监听端口、BT下载监听端口（TCP/UDP 6881），加快下载速度
- 默认开启DHT并且创建了DHT文件，加速下载
- 包含了下载完成后自动删除.aria2文件脚本
- 包含了执行删除文件操作时自动执行删除.aria2文件的脚本
- 内置最优的aria2配置文件（来自P3TERX/aria2_perfect_config，感谢）
- 默认上海时区 Asia/Shanghai
- 直接设置token，不需要在配置文件里修改


# Document
## 在线webui
我在Gitee上构建了基于ariang主线稳定版的在线webui：
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
![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-10-11_19-45-50.png)

### 2019.10.11日更新静态编译aria2c1.3.5解决报错[WARN] aria2c had to connect to the other side using an unknown T…

~~PS:为什么不在ENV里加入直接修改token?~~

因为我发现直接运行命令``aria2c --rpc-secret=$SECRET``会报很多（在conf文件里写也会报，但是少很多）[WARN] aria2c had to connect to the other side using an unknown T…

> 原因在于``aria2c 1.3.4``b不支持TLS1.3，在你的证书是TLS1.3的情况，下会报错，好消息是10.6号会发布``1.3.5``解决这个问题，国庆结束后我会更新``aria2c 1.3.5``解决这个问题

https://github.com/aria2/aria2/issues/1464

https://github.com/aria2/aria2/issues/1468

## 关于群晖
群晖用户请使用你当前的用户SSH进系统，输入 ``id 你的用户id`` 获取到你的UID和GID并输入进去

![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-09-27_19-17-57.png)
![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-09-27_19-19-02.png)
![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-09-27_19-20-03.png)

## 关于自动更新trackers
我个人是不喜欢这个功能的，Aria2的一些机制，导致Aria2重启带来的问题会很多，比如，已移除的文件他会再下一次等等，所以没事还是不要重启Aria2，而且trackerlist大部分tracker是不会变动的，只有极少数会变动，频繁的自动更新tracker带来的收益极其有限，甚至是负收益

今后可能会添加这个功能作为可选项，但是默认一定会是关闭
## Linux
输入 ``id 你的用户id`` 获取到你的UID和GID，替换命令中的PUID、PGID
__执行命令__
````
docker create \
  --name=aria2 \
  -e PUID=1026 \
  -e PGID=100 \
  -e TZ=Asia/Shanghai \
  -e SECRET=yourtoken \
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
      - SECRET=yourtoken
    volumes:
      - /path/to/appdata/config:/config
      - /path/to/downloads:/downloads
    ports:
      - 6881:6881
      - 6881:6881/udp
      - 6800:6800
    restart: unless-stopped   
````

# Preview
![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-09-27_20-23-40.png)
