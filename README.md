# 施工中
## docker_aria2的最佳实践

在茫茫多的docker aria2镜像中，一直找不到我想要的那个镜像
原因有以下几点

    1、没有配置UID和GID（这关系到你下载的文件都权限问题，默认是root权限，很难管理）
    2、掺杂了不必要的东西（大量aria2 images都包含了webui，我觉得根本没有必要
    本身也是通过rpc通信，webui不保存任何信息，根本没必要放在一起
       2.1 随便找一个在线的aria2控制台即可，还不需要输入端口好，明显更好更方便
       2.2 放在一起也破坏了docker的一个容器只跑一个进程的宗旨
    3、端口不全（绝大多数的aria2 images 都只开放了6800端口
    而和下载速度息息相关的BT下载DTH监听端口、BT下载监听端口，绝大部份都没有expose出来）
    4、conf文件的配置问题，这里要感谢的P3TERX的aria2_perfect_config项目
    5、SSL配置问题，这个比较简单，就不详细说明了
    
    
    
Docker Hub地址：https://hub.docker.com/r/superng6/aria2    

````
docker create \
  --name=aria2 \
  -u=1026:100
  -e TZ=Asia/Shanghai \
  -p 6881:6881 \
  -p 6881:6881/udp \
  -p 6800:6800 \
  -v /path/to/appdata/config:/config \
  -v /path/to/downloads:/downloads \
  --restart unless-stopped \
  superng6/aria2
  ````
