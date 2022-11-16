![](https://img.shields.io/docker/pulls/superng6/aria2) ![GitHub last commit](https://img.shields.io/github/last-commit/superng6/docker-aria2) ![Docker Image Size (tag)](https://img.shields.io/docker/image-size/superng6/aria2/latest) ![Docker Automated build](https://img.shields.io/docker/automated/superng6/aria2) ![](https://img.shields.io/github/issues-closed/superng6/docker-aria2) ![](https://img.shields.io/github/issues/superng6/docker-aria2) ![GitHub stars](https://img.shields.io/github/stars/superng6/docker-aria2) ![GitHub forks](https://img.shields.io/github/forks/superng6/docker-aria2)

# Docker Aria2的最佳实践
Docker Hub：https://hub.docker.com/r/superng6/aria2

GitHub：https://www.github.com/SuperNG6/docker-aria2

博客：https://sleele.com/2019/09/27/docker-aria2的最佳实践/  

>在茫茫多的docker aria2镜像中，一直找不到符合我需求的镜像

# 之所以构建这个镜像的原因
__当前的镜像或多或少都有以下几点不符合的我的需求__
   
- 没有配置UID和GID
  > 这关系到你下载的文件的权限问题，默认是root权限，很难管理
 - 端口不全
   > 绝大多数的aria2 images 都只开放了6800端口
   > 下载速度息息相关的BT下载DTH监听端口、BT下载监听端口，需要expose出来
   > 支持修改`DHT网络监听端口`和`BT监听端口`，部分网络6881端口已被封禁，建议修改
 - 没有自动删除.aria2文件的自动执行脚本
   > aria2建立下载任务后会自动生成.aria2文件，aria2自身提供了api可以触发执行脚本
 - 没有回收站
   > 不小心删除文件后无法找回，现在有了回收站，再也不用担心误删了
 - 没有任务转移功能
   > NAS下载，建议使用SSD盘，减少硬盘噪音，下载完成后自动保留目录结构转移到HDD硬盘中
 - 不能保存在保存磁力链接为种子文件时更名
   > aria2虽然可以保存磁力链接为种子，但是种子名为随机字符串，本镜像可以将种子命名为正确名称
 - 无法检测是否下载过的任务
   > aria2只能够在持续运行期间检查是否为重复任务，重启后再建立相同任务则会覆盖，本镜像支持持久化检查重复任务
   > 支持检测到重复任务自动删除新创立的重复任务
 - 不能够暂停任务后结束/移动文件
   > BT任务有个特点，就说很容易卡在一个进度就不动了，如果主要文件已下载完成可以执行其他操作就好了
   > 本镜像支持暂停任务后清理垃圾文件，并移动到已完成目录，并结束该任务
# 本镜像的一些优点
- 全平台架构`x86-64`、`arm64`、`armhf`,统一latest tag
- 做了usermapping，使用你自己的账户权限来运行，这点对于群辉来说尤其重要
- 纯aria2，没有包含多于的服务
- 超小镜像体积 10.77 MB
- 可以自定义任意二级目录
- 开放了BT下载DTH监听端口、BT下载监听端口（TCP/UDP 6881），加快下载速度
- 默认开启DHT并且创建了DHT文件，加速下载
- 包含了下载完成后自动删除.aria2文件脚本
- 包含了执行删除正在下载任务事时自动执行删除文件（删除已完成的任务不会删除文件，请放心）和aria2文件的脚本
- 内置最优的aria2配置文件（修改自[P3TERX/aria2.conf](https://github.com/P3TERX/aria2.conf)，感谢）
- 内置400多条最新trackers（来自[XIU2 / TrackersListCollection](https://github.com/XIU2/TrackersListCollection)，感谢）
- 每天自动更新trackers，不需要重启aria2即可生效（来自[P3TERX/aria2.conf](https://github.com/P3TERX/aria2.conf)，感谢）
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

#### webui-latest (default aria2 with webui ariang)
docker pull superng6/aria2:webui-latest  

| Architecture | Tag            |
| ------------ | -------------- |
| x86-64       | webui-latest         |
| arm64        | webui-latest         |
| armhf        | webui-latest         |


## 往后所有新增功能设置选项均在`/config/setting.conf`
### 额外补充文章  
群晖 DS918+扩展 – M.2 NVMe SSD 缓存变储存空间  
https://sleele.com/2021/09/04/synology-nas-m2nvme-ssd-cache-change-to-storage-pool/  
NAS SSD临时下载盘，Aria2+qbittorrent配置教程  
https://sleele.com/2021/09/04/nas-ssd-aria2-qbittorrent/

# Changelogs
## 2022/11/16

      1、没写更新日志，但是ariang一直在更新，且保持在最新版本

## 2022/5/15

      1、更新ariang v1.2.4

## 2021/10/25

      1、更新ariang v1.2.3

## 2021/09/10

      1、增加启动容器时显示正在运行的docker-aria2版本提示
      2、合并普通版和WEBUI版，增加选项`是否启用WEBUI` `-e WEBUI=true`,默认启用，端口8080

## 2021/09/09

      1、支持修改`BT监听端口`和`DHT网络监听端口`，默认`BTPORT=32516`
      2、增强程序健壮性，"/config/setting.conf"的参数误删除也会使用默认参数
      3、下个版本可能会合并webui版和普通版，二者资源占用上几乎没有区别，不想再多维护一个版本了
      4、docker-compose 事例说明中加入host模式写法，推荐使用host模式，性能更好
      5、"/config/setting.conf"的`自定义tracker地址`功能，变更至docker环境变量中,| `-e CTU=` |启动容器时更新自定义trackes地址中的trackes|

## 2021/08/24

      1、更新 aria2 1.36.0
      
## 2021/08/14

      1、添加WEBUI_PORT设置，默认`WEBUI_PORT=8080`

## 2021/07/28

      1、自定义tracker地址变更至`/config/setting.conf`
         现在无需重启容器也能方便修改自定义tracker了

<details>
   <summary>Change Log History</summary>

## 2021/07/08

      1、更新：P3TERX Aria2脚本
      2、更新：webui-AriaNg 1.2.2
      3、新增：正则表达式文件过滤功能。感谢 @hereisderek
      4、新增：支持自定义多个 tracker 列表 感谢 @hereisderek；ENV：CUSTOM_TRACKER_URL=

## 2021/03/18

      1、控制台任务信息显示支持中文
      2、默认开启保存磁力链接为种子文件，并开启重命名备份，种子备份位于`/config/backup-torrent`

## 2021/03/17

      1、变更：日志文件地址变更为`/config/logs`
      2、修复：任务类型为文件夹内的单文件BT下载任务会出现移动文件后文件夹保留的情况
      3、修复：修复部分磁力链接保存为种子文件并重命名失败的情况
      4、更新：更新webui至AriaNg v1.2.1

## 2021/02/15

      1、新增：任务暂停后移动文件，部分任务下载至百分之99时无法下载，可以启动本选项，具体请查看`/config/setting.conf`中的详细说明
      2、更新AriaNg 1.2.0(Add dark theme)

## 2021/01/31

      1、文件过滤：新增关键词过滤，具体请参照`/config/文件过滤.conf`

## 2021/01/29

      1、新增检测重复任务功能，若已完成目录有当前任务，则取消下载，并删除任务文件，默认开启
      2、参考P3TERX大佬的配置文件，检测任务的方式由递归变更为RPC，把aria2的官方文档啃了一遍，收获颇多
      3、新增种子文件文件备份、重命名功能，具体请查看`/config/setting.conf`中的详细说明
      4、自动更新新功能至`/config/setting.conf`
      5、更强的稳定性，绝大部分可能会出现的状况都考虑到了
      6、更多功能请自行体验

## 2021/01/24
- **破坏性更新**
   - 1、重构脚本，减少维护工作量，方便后续扩展功能
   - 2、核心功能选项单独列出，方便设置
   - 3、新增`setting.conf`，docker aria2 扩展功能设置
   - 4、`MOVE`、`内容过滤`、`删除空文件夹`、`回收站`等选项，移至`/config/setting.conf`，建议删除容器重新配置

2、可以自定义任意二级目录，不用像之前那样手动预设二级目录了（后处理脚本正确运行）  
3、如果有特殊需要，想使用大改版前的版本，可以使用`stable-21-01-23`版，`docker pull superng6/aria2:stable-21-01-23`  
4、新增历史版本，请在docker hub tags中查阅  

## 2021/01/16

      1、新增可选项`移动文件前，删除该下载的任务中的空文件夹`--`DET=true`，开启该选项需要同时开启`CF=true`、`MOVE=true`或`MOVE=dmof`
        本选项隶属于文件过滤的附加选项

## 2020/09/25

      1、新增任务文件过滤，由于aria2自身限制，只能在下载后才能移出文件
         请在/config/文件过滤.conf中设置
         开关`CF=true`，在同时开启下载后移动文件选项时生效

## 2020/07/27

      1、新增支持rpc的方式更新trackers（来自P3TERX）
      2、可选是否每天自动更新trackers(不需要重启aria2) `RUT=true`
      3、参数更改`UpdateTracker`变为`UT`

## 2020/06/18

      1、新增设置下载文件预分配磁盘模式选择，部分arm设备系统可能需要选择为`FA=none`
         不过好像aria2即便把`file-allocation=none`，也会使用`prealloc`，导致磁盘预分配时间大大加长
         能够使用`file-allocation=falloc`就使用这个，大部分操作系统都支持

## 2020/06/02

      1、aria2-with-webui分支添加aria2 webui ariang（真不知道有啥用，但是好多人就是喜欢容器里也有webui）
      2、内置AriaNg-1.1.6-AllInOne，如果想替换为其他webui或其他版本ariang，挂载`/www`，把webui扔进去就可以了
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

## 自行构建webui
在docker上部署最新版ariang  
https://sleele.com/2020/06/03/tiny-docker-ariang/  
https://github.com/SuperNG6/docker-ariang  
https://hub.docker.com/r/superng6/ariang  

## 挂载路径
``/config`` ``/downloads``
## 默认关闭SSL，如需要请手动开启
之所以默认关闭SSL(建议开启)，是因为如果开启，又没有配置证书，会导致aria2启动失败，所以如果需要开启请手动编辑aria2.conf
证书请放在``/config/ssl``目录下
删掉24,26,28行的``#``号
![IknUvK](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/IknUvK.jpg)

## 修改RPC token
填写你自己的token,越长越好，建议使用生成的UUID
![ByRMgP](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/ByRMgP.jpg)


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
| `-e PORT=6800` | RPC通讯端口 |
| `-e WEBUI=true` | 启用WEBUI |
| `-e WEBUI_PORT=8080` | WEBUI端口 |
| `-e BTPORT=32516` | DHT和BT监听端口 |
| `-e UT=true` |启动容器时更新trackers|
| `-e CTU=` |启动容器时更新自定义trackes地址|
| `-e RUT=true` |每天凌晨3点更新trackers|
| `-e SMD=true` |保存磁力链接为种子文件|
| `-e FA=` |磁盘预分配模式`none`,`falloc`,`trunc`,`prealloc`|
| `-p 6800:6800` |Aria2 RPC连接端口|
| `-p 6881:6881` |Aria2 tcp下载端口|
| `-p 6881:6881/udp` |Aria2 p2p udp下载端口|
| `--restart unless-stopped` |自动重启容器|

### 自定义tracker地址
CTU="https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/best_aria2.txt"

### `/config/setting.conf` 配置说明(推荐使用)
推荐使用`setting.conf`进行本镜像附加功能选项设置
````
## docker aria2 功能设置 ##
# 配置文件为本项目的自定义设置选项
# 重置配置文件：删除本文件后重启容器
# 所有设置无需重启容器,即刻生效

# 删除任务，`delete`为删除任务后删除文件，`recycle`为删除文件至回收站，`rmaria`为只删除.aria2文件
remove-task=rmaria

# 下载完成后执行操作选项，默认`false`
# `true`，下载完成后保留目录结构移动
# `dmof`非自定义目录任务，单文件，不执行移动操作。自定义目录、单文件，保留目录结构移动（推荐）
move-task=false

# 文件过滤，任务下载完成后删除不需要的文件内容，`false`、`true`
# 由于aria2自身限制，无法在下载前取消不需要的文件（只能在任务完成后删除文件）
content-filter=false

# 下载完成后删除空文件夹，默认`true`，需要开启文件过滤功能才能生效
# 开启内容过滤后，可能会产生空文件夹，开启`DET`选项后可以删除当前任务中的空文件夹
delete-empty-dir=true

# 对磁力链接生成的种子文件进行操作
# 在开启`SMD`选项后生效，上传的种子无法更名、移动、删除，仅对通过磁力链接保存的种子生效
# 默认保留`retain`,可选删除`delete`，备份种子文件`backup`、重命名种子文件`rename`，重命名种子文件并备份`backup-rename`
# 种子备份位于`/config/backup-torrent`
handle-torrent=backup-rename

# 删除重复任务，检测已完成文件夹，如果有该任务文件，则删除任务，并删除文件，仅针对文件数量大于1的任务生效
# 默认`true`，可选`false`关闭该功能
remove-repeat-task=true

# 任务暂停后移动文件，部分任务下载至百分之99时无法下载，可以启动本选项
# 建议仅在需要时开启该功能，使用完后请记得关闭
# 默认`false`，可选`true`开启该功能
move-paused-task=false

````

### `/config/文件过滤.conf` 配置说明

````
## 文件过滤设置(全局) ##

# 仅 BT 多文件下载时有效，用于过滤无用文件。
# 可自定义；如需启用请删除对应行的注释 # 

# 排除小文件。低于此大小的文件将在下载完成后被删除。
#min-size=10M

# 保留文件类型。其它文件类型将在下载完成后被删除。
#include-file=mp4|mkv|rmvb|mov|avi|srt|ass

# 排除文件类型。排除的文件类型将在下载完成后被删除。
#exclude-file=html|url|lnk|txt|jpg|png

# 按关键词排除。包含以下关键字的文件将在下载完成后被删除。
#keyword-file=广告1|广告2|广告3

# 保留文件(正则表达式)。其它文件类型将在下载完成后被删除。
#include-file-regex=

# 排除文件(正则表达式)。排除的文件类型将在下载完成后被删除。
# 示例为排除比特彗星的 padding file
#exclude-file-regex="(.*/)_+(padding)(_*)(file)(.*)(_+)"

````

## Linux

输入 ``id 你的用户id`` 获取到你的UID和GID，替换命令中的PUID、PGID

__执行命令__
```bash
docker run -d \
  --name=aria2 \
  -e PUID=1026 \
  -e PGID=100 \
  -e TZ=Asia/Shanghai \
  -e SECRET=yourtoken \
  -e CACHE=512M \
  -e PORT=6800 \
  -e BTPORT=32516 \
  -e WEBUI=true \
  -e WEBUI_PORT=8080 \
  -e UT=true \
  -e RUT=true \
  -e FA=falloc \
  -e QUIET=true \
  -e SMD=true \
  -p 32516:32516 \
  -p 32516:32516/udp \
  -p 6800:6800 \
  -p 8080:8080 \
  -v $PWD/config:/config \
  -v $PWD/downloads:/downloads \
  --restart unless-stopped \
  superng6/aria2:webui-latest
  ```
docker-compose  
  ```yml
version: "3.1"
services:
  aria2:
    image: superng6/aria2:webui-latest
    container_name: aria2
    network_mode: host
    environment:
      - PUID=1026
      - PGID=100
      - TZ=Asia/Shanghai
      - SECRET=yourtoken
      - CACHE=512M
      - PORT=6800
      - WEBUI=true
      - WEBUI_PORT=8080
      - BTPORT=32516
      - UT=true
      - QUIET=true
      - SMD=true
    volumes:
      - $PWD/config:/config
      - $PWD/downloads:/downloads
    restart: unless-stopped   
```

# Preview
![N94s7q](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/N94s7q.jpg)
![Hq0pXW](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/Hq0pXW.jpg)
![Xnip2020-05-11_15-43-56](https://cdn.jsdelivr.net/gh/SuperNG6/pic@master/uPic/Xnip2020-05-11_15-43-56.png)
