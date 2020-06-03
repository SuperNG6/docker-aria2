# Docker Aria2的最佳实践
Docker Hub：https://hub.docker.com/r/superng6/aria2

GitHub：https://www.github.com/SuperNG6/docker-aria2

博客：https://sleele.com/2019/09/27/docker-aria2的最佳实践/  

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
 - 没有回收站
   > 不小心删除文件后无法找回，现在有了回收站，再也不用担心误删了
# 本镜像的一些优点
- 全平台架构`x86-64`、`arm64`、`armhf`,统一latest tag
- 做了usermapping，使用你自己的账户权限来运行，这点对于群辉来说尤其重要
- 纯aria2，没有包含多于的服务
- 超小镜像体积 10.77 MB
- 开放了BT下载DTH监听端口、BT下载监听端口（TCP/UDP 6881），加快下载速度
- 默认开启DHT并且创建了DHT文件，加速下载
- 包含了下载完成后自动删除.aria2文件脚本
- 包含了执行删除正在下载任务事时自动执行删除文件（删除已完成的任务不会删除文件，请放心）和aria2文件的脚本
- 内置最优的aria2配置文件（来自[P3TERX/aria2.conf](https://github.com/P3TERX/aria2.conf)，感谢）
- 内置400多条最新trackers（来自[XIU2 / TrackersListCollection](https://github.com/XIU2/TrackersListCollection)，感谢）
- 默认上海时区 Asia/Shanghai
- 直接设置token，不需要在配置文件里修改
- 最新静态编译版的aria2c1.3.5（来自[P3TERX/aria2-builder](https://github.com/P3TERX/aria2-builder)，感谢）
- 解除aria2c下载线程限制
- 支持自动更新tracker，每次启动容器时会自动更新tracker
- 手动设置磁盘缓存`CACHE`，默认参数`128M`
- 可选则开启回收站，删除文件后移动至回收站，防止丢失文件
- 可选下载任务完成后，保留目录结构移动文件
- 相对来说最完善的任务处理脚本
- 更多可手动调节参数，大量选项不需要修改conf文件
- 全平台镜像统一tag

# Architecture
### 全平台镜像统一Tag

#### latest (default none webui)
docker pull superng6/aria2:latest  

| Architecture | Tag            |
| ------------ | -------------- |
| x86-64       | latest         |
| arm64        | latest         |
| armhf        | latest         |

#### webui-latest (default webui ariang)
docker pull superng6/aria2:webui-latest  

| Architecture | Tag            |
| ------------ | -------------- |
| x86-64       | webui-latest         |
| arm64        | webui-latest         |
| armhf        | webui-latest         |


# Changelogs
## 2020/06/02

      1、aria2-with-webui分支添加aria2 webui ariang（真不知道有啥用，但是好多人就是喜欢容器里也有webui）
      2、内置AriaNg-1.1.6-AllInOne，如果想替换为其他webui或其他版本ariang，挂载`/www`，把weibui扔进去就可以了
      3、使用darkhttpd，轻量化网页服务器，默认webui端口为`80`

## 2020/05/20

      1、调整`dmof`逻辑，下载任务为单文件且路径为自定义路径则保留目录结构移动
      2、完善删除脚本与回收脚本对于自定义路径中文件任务单执行逻辑

## 2020/05/18

      1、增加自定义二级目录功能`CUSDIR=cusdir`-->`/download/cusdir` （ENV中只能添加一个CUS）
      2、预设的三个目录`动画片->ANIDIR`,`电影->MOVDIR`,`电视->TVDIR`，可根据自己喜好修改预设分类目录名称
        详见《环境变量说明》
      3、完善了单文件任务中包含多级目录的移动机制
      4、进一步完善脚本

<details>
   <summary>Change Log History</summary>

## 2020/05/12

      1、调整了回收站脚本、下载完成后移动文件脚本、删除文件和删除.aria2文件脚本的执行逻辑
      2、重点事项说明，由于aria2自身的限制，BT任务如果自身包含多文件夹，需要注意文件归类目录的问题
        1.如果像我一样，下载文件喜欢归类；如任务类型为电影，归类在`/downloads/movies`，需要注意归类目录名称
        2.其实大部分下载任务不需要注意下载路径，只有在BT任务包含多文件夹的情况才需要注意
        3.目前我已经提前设定了3个归类路径`/downloads/movies`,`/downloads/tv`,`/downloads/ani`
          如需归类，请按照以上路径进行归类（如果在BT任务不包含多文件夹则路径选择哪都无所谓）
      3、基本没什么可改的了（有些地方受限于aria2自身，我也无能为力），大部分情况的我都写了判断，aria2还是少更新的好。
         重启aria2后DHT重建，对下载速度影响极大，下载别人的DHT文件也无任何意义，感兴趣的可以去了解一下DHT是什么

## 2020/05/11

      1、修复`动画片种子中，种子文件包含多文件夹`下的文件夹移动、回收失败问题，如果需要下载归类的话，动画片请务必设置目录为`/downloads/ani`
      2、增加`movies`,`tv`,`ani`文件夹，推荐下载任务时选择对应的文件夹，防止文件移动，删除失败（说真的也就动画片的文件夹会这么复杂）
      3、调整`dmof`策略，不移动无文件夹的单文件
      4、优化删除文件和删除.aria2文件脚本执行逻辑

## 2020/05/08

      1、步子迈的太大，扯到了。完善回收站脚本、完善移动文件脚本
      2、现在，回收站和已完成任务文件夹可以保持完整的目录结构了
        例[source_path:/downloads/movies/date/Justice/Justice.mkv]->[recycle_path:/downloads/recycle/movies/date/Justice/Justice.mkv]
      3、添加文件数量等于1时不移动选项，默认关闭`-e MOVE=dmof`
      4、有qBittorrent的7成功力了

## 2020/05/07

      1、添加回收站功能，默认关闭`-e RECYCLE=false`，可选择开启,/downloads/recycle（修改脚本自[P3TERX/aria2.conf](https://github.com/P3TERX/aria2.conf)，感谢）
      2、下载完文件后自动移动到/downloads/completed,默认关闭`-e MOVE=false`，可选择开启（修改脚本自[P3TERX/aria2.conf](https://github.com/P3TERX/aria2.conf)，感谢）
      3、更换ariac静态编译版本，解除aria2c线程限制（来自[P3TERX/aria2-builder](https://github.com/P3TERX/aria2-builder)，感谢）
      4、本次更新的两个选项（回收站，下载完成后移动到completed文件夹）均可手动开关，极大的提升了aria2的使用体验
      5、更新base imgae `lsiobase/alpine:3.11`
      6、优化启动脚本
      7、增加是否保存磁力链接为种子选项，默认关闭(bt-save-metadata=false) `SMD=false`
      8、默认force-save=false && save-session-interval=1，重启容器后不重复下载已完成和已删除的任务
         这个我纠结了很久，我个人是不建议关闭force-save的，我有UPS，几乎不存在断电情况，关闭这个选项，意味着，重启容器后会丢失已完成和删除的任务列表
         save-session-interval的频率太高也也会影响性能，但是新版本加入了回收站和自动移动下载完成文件，如果不调整这两个参数，重启容器会重复下载，并且因为文件位置已移动的缘故
         allow-overwrite=true几乎等同于失效，所以新版本，调整了这两个参数
      9、默认设置auto-save-interval=60，这个不能太低，否则会非常吃硬盘
    

## 2020/04/17

      1、使用jsdelivr cdn加速下载trackers，但是会出现缓存导致的不是最新版本

## 2020/03/02

      1、更新base image lsiobase/alpine:3.10
      2、增加了静默下载功能，默认下载不输出到console --quiet[=true|false]

## 2020/02/22

      1、update delete.sh & delete.aria2.sh 现在可以删除自定义目录的`.aria2`文件和文件夹了
         至此，`.aria2`删除和`文件/目录`删除功能已完善
      2、增加了`downloads1`、`downloads2`、`downloads3`、`downloads4`、`downloads5`目录
         方便多磁盘用户的多磁盘下载，权限修复
      
## 2020/01/15

      1、update delete.sh & delete.aria2.sh
      
## 2020/01/10

      1、增加arm64v8、arm32v7平台镜像
      2、针对arm平台设备ram小的情况，增加配置下载缓存大小设置
      3、进一步压缩镜像体积，现在只有10.77 MB
      
## 2019/12/27

      1、新增自动更新tracker，默认开启，每次启动容器时会自动检查并更新tracker列表
           
      
## 2019/12/19

      1、回退脚本，新版脚本会在删除已完成任务时会删除下载任务指定的二级目录
      
## 2019/12/04

      1、更新了P3TERX/P3TERX/aria2.conf及触发脚本
      2、更新trackers(XIU2 / TrackersListCollection )
      3、梳理、优化了文件结构
      4、本次更新请手动删除你的Aria2配置文件（可以直接删除配置目录）
      5、改善 delete.sh、delete.aria2.sh 路径判断逻辑，增加删除空目录功能
      6、重启Aria2后不会重复下载已完成的任务

</details>

# Document
## 在线webui

我在Gitee上构建了基于ariang主线稳定版的在线webui:  
仅https https://sleele.gitee.io/#!/downloading  
http  http://sleele.gitee.io/ariang/#!/downloading  

## 挂载路径
``/config`` ``/downloads``
## 默认关闭SSL，如需需要请手动开启
之所以默认关闭SSL(建议开启)，是因为如果开启，又没有配置证书，会导致aria2启动失败，所以如果需要开启请手动编辑aria2.conf
证书请放在``/config/ssl``目录下
删掉24,26,28行的``#``号
![IknUvK](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/IknUvK.jpg)
## 修改RPC token
填写你自己的token,越长越好，建议使用生成的UUID
![ByRMgP](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/ByRMgP.jpg)

<details>
   <summary>2019.10.11更新日志及用户须知</summary>
   
### 2019.10.11日更新静态编译aria2c1.3.5解决报错[WARN] aria2c had to connect to the other side using an unknown T…

~~PS:为什么不在ENV里加入直接修改token?~~

因为我发现直接运行命令``aria2c --rpc-secret=$SECRET``会报很多（在conf文件里写也会报，但是少很多）[WARN] aria2c had to connect to the other side using an unknown T…

> 原因在于``aria2c 1.3.4``不支持TLS1.3，在你的证书是TLS1.3的情况，下会报错，好消息是10.6号会发布``1.3.5``解决这个问题，国庆结束后我会更新``aria2c 1.3.5``解决这个问题


https://github.com/aria2/aria2/issues/1464

https://github.com/aria2/aria2/issues/1468

### 使用2019.10.11日前版本的用户，更新时请删除conf文件的第十七行
token现在不用写在配置文件里了，使用2019.10.11日前版本的用户，请删除第十七行，否则会报错，无法启动
![](https://github.com/SuperNG6/pic/blob/master/aria2/Xnip2019-10-11_21-44-59.png)

## 关于自动更新trackers
我个人是不喜欢这个功能的，Aria2的一些机制，导致Aria2重启带来的问题会很多，比如，已移除的文件他会再下一次等等，所以没事还是不要重启Aria2，而且trackerlist大部分tracker是不会变动的，只有极少数会变动，频繁的自动更新tracker带来的收益极其有限，甚至是负收益

~~今后可能会添加这个功能作为可选项，但是默认一定会是关闭~~，之所以打脸，默认开启是因为，我想到一个更巧妙的法子，Aria2需要重启才能够读取到conf文件改变的内容，所以就意味着，为了更新tracker而去重启Aria2，其所带来负面影响，比如导致dht文件失效从新收集信息，任务重新下载等，是不值当的。如果放弃使用定时更新这种形式，改为每次启动容器时更新tracker，那么就一举两得的解决了这个问题，不重启不更新，重启时在Aria2启动前自动更新tracker，做到完全无感知，并且没有任何负面效果，如果能做到这种效果，添加默认自动更新tracker则是值得的

</details>


## 关于群晖

群晖用户请使用你当前的用户SSH进系统，输入 ``id 你的用户id`` 获取到你的UID和GID并输入进去

![nwmkxT](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/nwmkxT.jpg)
![1d5oD8](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/1d5oD8.jpg)
![JiGtJA](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/JiGtJA.jpg)

### 权限管理设置
对你的``docker配置文件夹的根目录``进行如图操作，``你的下载文件夹的根目录``进行相似操作，去掉``管理``这个权限，只给``写入``,``读取``权限
![r4dsfV](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/r4dsfV.jpg)

## 环境变量说明
|参数|说明|
|-|:-|
| `--name=aria2` |容器名设置为aria2|
| `-v 本地文件夹1:/downloads` |Aria2下载位置|
| `-v 本地文件夹2:/config` |Aria2配置文件位置|
| `-e PUID=1026` |Linux用户UID|
| `-e PGID=100` |Linux用户GID|
| `-e SECRET=yourtoken` |Aria2 token|
| `-e CACHE=1024M` |Aria2磁盘缓存配置|
| `-e UpdateTracker=true` |启动容器时更新Trackers|
| `-e RECYCLE=true` |启用回收站|
| `-e MOVE=true` |下载完成文件后移动文件或文件夹|
| `-e MOVE=dmof` |下载任务为单个文件则不移动，若为文件夹则移动|
| `-e SMD=true` |保存磁力链接为种子文件|
| `-e ANIDIR=ani` |动画片分类目录名称(支持中文名称)|
| `-e MOVDIR=movies` |电影分类目录名称(支持中文名称)|
| `-e TVDIR=tv` |电视分类目录名称(支持中文名称)|
| `-e CUSDIR=cusdir` |自定义分类目录名称(支持中文名称)|
| `-p 6800:6800` |Aria2 RPC连接端口|
| `-p 6881:6881` |Aria2 tcp下载端口|
| `-p 6881:6881/udp` |Aria2 p2p udp下载端口|
| `--restart unless-stopped` |自动重启容器|


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
  -e CACHE=512M \
  -e UpdateTracker=true \
  -e QUIET=true \
  -e RECYCLE=true \
  -e MOVE=true \
  -e SMD=false \
  -e ANIDIR=ani \
  -e MOVDIR=movies \
  -e TVDIR=tv \
  -e CUSDIR=cusdir \
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
version: "3"

services:
  aria2:
    image: superng6/aria2
    container_name: aria2
    environment:
      - PUID=1026
      - PGID=100
      - TZ=Asia/Shanghai
      - SECRET=yourtoken
      - CACHE=512M
      - UpdateTracker=true
      - QUIET=true
      - RECYCLE=true
      - MOVE=true
      - SMD=false
      - ANIDIR=ani
      - MOVDIR=movies
      - TVDIR=tv
      - CUSDIR=cusdir
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
![N94s7q](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/N94s7q.jpg)
![Hq0pXW](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/Hq0pXW.jpg)
![Xnip2020-05-11_15-43-56](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/Xnip2020-05-11_15-43-56.png)
