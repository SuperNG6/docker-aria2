# 环境变量参考

本文汇总容器支持的环境变量、默认值与作用范围，便于在 docker-compose 或运行参数中自定义。

提示
- 未显式设置时，脚本会使用“默认值”。
- 路径类变量均支持覆盖；请确保挂载卷与之匹配，避免写入容器内部临时层。

## 通用运行与权限
- TZ
  - 作用：时区，仅影响日志/面板显示。
  - 默认：Asia/Shanghai
  - 使用处：11-banner
- PUID / PGID
  - 作用：基础镜像内置用户 abc 的 UID/GID。用于宿主权限对齐（由基础镜像处理）。
  - 默认：PUID=1026、PGID=100（镜像 ENV）；未在脚本显式使用。
- DEBUG
  - 作用：开启额外调试输出（仅少量函数使用）。
  - 默认：未设置（关闭）

## 路径与文件（可覆盖）
- DOWNLOAD_PATH
  - 作用：下载根目录。
  - 默认：/downloads
  - 使用处：path.sh、handlers、file_ops 等
- CONFIG_DIR
  - 作用：配置根目录。
  - 默认：/config
- LOG_DIR
  - 作用：日志目录。
  - 默认：/config/logs
- SETTING_FILE
  - 作用：脚本行为配置（key=value）。
  - 默认：/config/setting.conf
  - 使用处：config.sh（读取与缺省回填）
- ARIA2_CONF
  - 作用：aria2 主配置。
  - 默认：/config/aria2.conf
  - 使用处：30-aria2-conf、tracker.sh 等
- FILTER_FILE
  - 作用：内容过滤规则。
  - 默认：/config/文件过滤.conf
  - 使用处：file_ops.sh
- SESSION_FILE
  - 作用：aria2 会话文件。
  - 默认：/config/aria2.session
  - 使用处：20-config 初始化空文件
- DHT_FILE
  - 作用：aria2 DHT 数据文件。
  - 默认：/config/dht.dat
  - 使用处：20-config 初始化空文件
- CF_LOG / MOVE_LOG / DELETE_LOG / RECYCLE_LOG
  - 作用：分别记录内容过滤、移动、删除、回收站操作日志。
  - 默认：/config/logs/文件过滤日志.log、/config/logs/move.log、/config/logs/delete.log、/config/logs/recycle.log
- BAK_TORRENT_DIR
  - 作用：种子备份目录（含重命名逻辑）。
  - 默认：/config/backup-torrent
  - 使用处：torrent.sh

## 端口与运行参数
- PORT
  - 作用：aria2 RPC 端口；写入 aria2.conf。
  - 默认：6800
  - 使用处：30-aria2-conf、rpc.sh、aria2b/run
- BTPORT
  - 作用：BT 监听端口（TCP/UDP 同值）；写入 aria2.conf。
  - 默认：32516
- SECRET
  - 作用：aria2 RPC 令牌；用于 JSON-RPC 与服务启动参数。
  - 默认：未设置（无鉴权）
  - 使用处：services.d/aria2/run、rpc.sh、aria2b/run
- CACHE
  - 作用：aria2 磁盘缓存。
  - 默认：128M（Dockerfile ENV）
  - 使用处：services.d/aria2/run
- QUIET
  - 作用：aria2 静默模式（减少输出）。
  - 默认：true
  - 使用处：services.d/aria2/run
- SMD
  - 作用：是否启用 bt-save-metadata。
  - 默认：true（写入 aria2.conf）
  - 使用处：30-aria2-conf
- FA
  - 作用：file-allocation 策略。
  - 可选：falloc | trunc | prealloc | none
  - 默认：falloc（非法输入回退为 falloc）
  - 使用处：30-aria2-conf

## Tracker 相关
- UT
  - 作用：容器启动时更新 bt-tracker 到 aria2.conf。
  - 默认：true
  - 使用处：40-tracker（调用 tracker.sh）
- RUT
  - 作用：每日定时（05:00）通过 RPC 更新 bt-tracker。
  - 默认：true
  - 使用处：40-tracker（写入 crontab 并启动 crond）
- CTU
  - 作用：自定义 tracker 源列表，逗号分隔多个 URL；会去重合并。
  - 默认：未设置（使用内置公共源）
  - 使用处：tracker.sh
- TRACKER_SHOW
  - 作用：控制 tracker.sh 控制台输出模式。
  - 取值：count（默认，仅输出“获取到 N 条”）、list（打印完整列表；或在 DEBUG=1 时也会打印）
  - 使用处：tracker.sh

## Web UI（AriaNg + darkhttpd）
- WEBUI
  - 作用：是否启动内置 AriaNg Web 服务。
  - 默认：true
  - 使用处：50-darkhttpd、11-banner
- WEBUI_PORT
  - 作用：Web UI 端口。
  - 默认：8080

## Aria2B（可选功能）
- A2B
  - 作用：是否启用 aria2b 辅助进程。
  - 默认：false（若使用带 A2B 的镜像/构建，可能默认开启）
  - 使用处：aria2b/run、cron-restart-a2b.sh、11-banner
- A2B_DISABLE_LOG
  - 作用：静默运行 aria2b（抑制日志输出）。
  - 默认：false
  - 使用处：aria2b/run
- CRA2B
  - 作用：定时重启 aria2b 的周期。
  - 取值：false 或 "Nh"（N=1..24）
  - 默认：2h（非法取值自动回退到 2h）
  - 使用处：cron-restart-a2b.sh（写 crontab）

## 使用示例（docker-compose 片段）
```yaml
services:
  aria2:
    image: superng6/aria2:a2b-latest
    network_mode: host
    environment:
      - TZ=Asia/Shanghai
      - SECRET=yourtoken
      - PORT=6800
      - BTPORT=32516
      - CACHE=512M
      - QUIET=true
      - WEBUI=true
      - WEBUI_PORT=8080
      - UT=true
      - RUT=true
      - SMD=true
      - FA=falloc
      - A2B=false
      - CRA2B=2h
      - A2B_DISABLE_LOG=false
      # 路径类（如需自定义）：
      # - DOWNLOAD_PATH=/data/downloads
      # - CONFIG_DIR=/data/config
```
