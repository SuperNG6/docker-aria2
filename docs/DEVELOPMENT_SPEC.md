# docker-aria2 开发 Spec（当前实现）

> 本文记录代码装配、运行契约和验证方式；用户可见行为见 [PRD](PRD.md)。改动前以目标代码和对应测试核实本文件。本文不定义未来版本计划。

## 1. 系统边界与源码位置

仓库负责装配 aria2c、AriaNg 与可选 aria2b，并实现启动配置、tracker 更新和 aria2 事件后处理。下载协议、BT 算法及 RPC 服务来自 aria2c；WebUI 页面来自 AriaNg；客户端识别与封禁来自 aria2b。

| 位置 | 职责 |
| --- | --- |
| [`Dockerfile`](../Dockerfile)、[`build.sh`](../build.sh) | 变体构建、上游制品和本地镜像标签 |
| [`root/etc/cont-init.d/`](../root/etc/cont-init.d) | 启动横幅、配置初始化、cron 与权限 |
| [`root/etc/services.d/`](../root/etc/services.d) | s6 监管 aria2c、WebUI 和可选 aria2b |
| [`root/aria2/conf/`](../root/aria2/conf) | 首次启动的 aria2、行为、过滤及 cron 模板 |
| [`root/aria2/scripts/`](../root/aria2/scripts) | 四个事件入口及 `lib/` 公共函数 |
| [`tests/`](../tests) | Bash 静态检查、库测试、真实容器场景及变异验证 |

## 2. 构建产物与依赖

builder 和最终镜像均基于 `superng6/alpine:3.23`。仓库没有固定基础镜像 digest，也未在 Dockerfile 中安装 `bash`、`curl`、`wget` 或 s6：构建与启动依赖基础镜像提供这些命令、`/init`、`with-contenv`、`s6-setuidgid`、`s6-svc` 和 `abc` 用户。脚本还调用 `chown`、`crond`、`crontab`、`realpath`、`stat`、`du`、`df`、`awk`、`sed`、`sort` 等工具；跨盘空间检查需要 `du -sb`、`df --output=avail -B1` 和 `stat -c %d` 的实现。Dockerfile 默认 `PUID=1026`、`PGID=100`；`40-config` 将 `/config`、`/www`、`/downloads` 递归授权给 `abc`。基础镜像的具体包版本和预设 UID/GID 不由本仓库锁定。

builder 额外安装 `unzip`，从最新 release 下载 Aria2-Pro-Core 静态 aria2c 和 AriaNg AllInOne。最终镜像额外安装 `darkhttpd`、`jq`、`findutils`。`VARIANT=a2b` 再增加 `iptables`、`iptables-legacy`、`ipset`、`nodejs` 和 aria2b；`standard` 删除 aria2b 服务目录。`A2B_DEFAULT` 与变体配套，供运行时默认开关使用。仓库的 compose 示例和 CI 为 a2b 提供 `NET_ADMIN`，并在可用时只读挂载 `/lib/modules`；a2b 启动脚本将 `/config/aria2.conf` 路径传给 aria2b。

builder 在目标架构环境运行，按 `uname -m` 选择资产：`x86_64 → x86_64`、`aarch64 → arm64`、`armv7l/armv6l → armhf`、`i386/i686 → i386`；未知架构构建失败。本地使用 `./build.sh [standard|a2b|all]` 同时设置 `VARIANT` 与 `A2B_DEFAULT`。默认 `--no-cache`，使最新上游 release 在重建时重新下载。

## 3. 启动顺序与服务监管

项目使用基础镜像的 s6 初始化机制；仓库内编号脚本依序运行，基础镜像自身的初始化逻辑不在本仓库维护。项目脚本顺序为：

```text
11-version  展示本次启动配置；不把横幅当健康检查
20-config   创建 /config 与 /downloads 子目录，复制或合并模板
30-config   覆盖 aria2 配置、可选更新 tracker、写 cron、启动 crond
40-config   授权 abc，注册符合条件的 aria2b 重启 cron
90 / 99     保留的自定义初始化钩子
services.d  由 s6 监管 aria2c、webui、aria2b
```

[`services.d/aria2/run`](../root/etc/services.d/aria2/run) 用 `s6-setuidgid abc` 启动 aria2c，传入配置文件、磁盘缓存、静默开关和非空 RPC secret。[`webui/run`](../root/etc/services.d/webui/run) 以前台 darkhttpd 服务 `/www`，访问日志写 `/dev/null`；[`aria2b/run`](../root/etc/services.d/aria2b/run) 从有效 `rpc-secure=true` 选择 HTTP/HTTPS，最多探测本地 RPC 30 次，然后传入配置路径、RPC URL 和 secret；探测超时也会尝试启动。可选服务关闭时执行 `s6-svc -d .`，避免退出后重启循环。事件 hook 使用普通 Bash shebang，继承 aria2c 经 `with-contenv` 获得的环境。

## 4. 配置与数据契约

| 路径 | 所有权与更新规则 |
| --- | --- |
| `/config/aria2.conf` | 首次复制模板；后续保留用户配置，但 `30-config` 每次启动重写四个 `on-download-*`、RPC/BT 端口、`bt-save-metadata`、`file-allocation`，`UT=true` 时更新 `bt-tracker`。锚定 `sed` 只替换已有 key，不补齐缺行。 |
| `/config/setting.conf` | 文件处理行为的唯一接口；每次 hook 通过 [`lib/config.sh`](../root/aria2/scripts/lib/config.sh) 重新加载。重启时以新版模板创建 `.new`，填入旧文件中已知 key 的值，再原子替换；未知 key 和旧注释不保留。 |
| `/config/文件过滤.conf` | 执行过滤时由 [`lib/filter.sh`](../root/aria2/scripts/lib/filter.sh) 读取。 |
| `/config/aria2.session`、`dht.dat` | aria2 会话与 DHT 数据。 |
| `/config/logs/`、`backup-torrent/` | 文件操作日志与磁力元数据种子备份。 |
| `/downloads` | 原始任务；`completed`、`recycle` 为共享目录，`move-failed` 按需创建。 |

`setting.conf` 的七个 key 为 `remove-task=rmaria`、`move-task=false`、`content-filter=false`、`delete-empty-dir=true`、`handle-torrent=backup-rename`、`remove-repeat-task=true`、`move-paused-task=false`；对应共享变量依次为 `RMTASK`、`MOVE`、`CF`、`DET`、`TOR`、`RRT`、`MPT`。缺 key 使用默认值，这些选项不接受环境变量首次写入。`FA` 仅接受 `falloc`、`trunc`、`prealloc`、`none`，其他值回退 `falloc`。`SECRET`、`CACHE`、`QUIET` 由 aria2c 命令行传入。

## 5. 下载事件处理

`start.sh`、`pause.sh`、`stop.sh`、`completed.sh` 均加载 [`lib/event.sh`](../root/aria2/scripts/lib/event.sh)。aria2 传入 GID、文件数和第一个文件路径；事件初始化依次执行 **公共路径 → completed/recycle 目标 → [`lib/rpc.sh`](../root/aria2/scripts/lib/rpc.sh) 查询任务 → 计算源与目标路径**。目标目录必须先于路径计算确定。库以 `${BASH_SOURCE[0]}` 找到自身；事件辅助函数以返回码和 stderr 报错，由入口决定是否退出。

RPC 用 `jq` 构造 JSON，请求先试本地 HTTP，失败再试 HTTPS 并允许自签证书。`tellStatus` 提供状态、下载目录、infoHash；非 BT 的 `infoHash=null` 是正常结果。磁力任务在尚无文件路径或文件数为零时跳过文件操作。

路径规则是删除和移动的安全边界：多文件任务，以及位于任务下载目录子目录中的 BT 任务，取首层任务目录整体处理；单文件 HTTP/FTP 和根目录单文件 BT 只处理文件本身，以保留共享分类目录中的其他文件。目标保留 `/downloads` 内相对路径。规范化后拒绝 `/downloads` 根目录、其外部路径，以及 `completed`、`recycle`、`move-failed` 三个共享目录本身。只有文件夹任务计算 `COMPLETED_DIR`，用于开始事件的去重。

| 入口 | 主要分支 |
| --- | --- |
| `start.sh` | `RRT=true`、推算出文件夹任务的 `COMPLETED_DIR`、该目录已存在且状态非 error 时，清理新任务文件/种子，等待内部状态更新后尝试 RPC 移除；失败记警告。 |
| `pause.sh` | `MPT=true` 时后台等待 30 秒，重新加载开关与 RPC 状态；仍 paused 才强制移动。 |
| `stop.sh` | 源文件存在且状态非 error 时，按 `RMTASK` 保留内容、回收或删除；三种已知模式均处理可用的元数据种子并清理 `.aria2`，未知值全部不处理。 |
| `completed.sh` | `MOVE_FILE` 后台处理大文件移动，种子操作在前台；等待 BT 做种结束后的 complete 事件。 |

[`lib/files.sh`](../root/aria2/scripts/lib/files.sh) 在 `MOVE=false` 或 `dmof` 跳过移动时只清理 `.aria2`；真正移动时先执行 `CLEAN_UP`，再仅对跨文件系统移动比较源大小与目标可用空间。空间不足或主移动失败时尝试 `/downloads/move-failed`。回收站移动失败转永久删除；`mv -f` 可能覆盖同名文件，遇到同名非空目录则可能失败。过滤仅在任务源路径内实际存在多个文件、且进入移动清理流程时运行，暂停 hook 强制移动时也会运行：[`lib/filter.sh`](../root/aria2/scripts/lib/filter.sh) 用同一规则预览与删除，NUL 分隔并去重；全部文件将被匹配时跳过本次过滤和空目录清理。种子处理位于 [`lib/torrent.sh`](../root/aria2/scripts/lib/torrent.sh)，仅在推算出的 `.torrent` 存在时按 `TOR` 执行。

## 6. Tracker 与 cron

[`lib/tracker.sh`](../root/aria2/scripts/lib/tracker.sh) 的 `file` 模式在启动时更新 `aria2.conf`；`rpc` 模式通过 `aria2.changeGlobalOption` 热更新，并要求响应 JSON 的 `.result == "OK"`。默认按主源、CDN、代理顺序获取；`CTU` 可指定多个 URL 并去重。tracker 拉取请求设置超时和重试，默认源之间另有回退；cron 的 RPC 调用设时间上限以防任务累积。事件 hook 的本地 RPC 请求没有对应超时和重试设置。

`RUT=true` 将 [`rpc-tracker1`](../root/aria2/conf/rpc-tracker1) 写入 `/etc/crontabs/root`，每天 05:00 更新；否则使用 [`rpc-tracker0`](../root/aria2/conf/rpc-tracker0)。`crond` 始终启动。`40-config` 仅在 `A2B=true` 且 aria2b 实际存在时，经 `crontab -l/-` 注册 `s6-svc -r /var/run/s6/services/aria2b`；`CRA2B=false` 关闭，非法间隔回退两小时。两种 cron 写入方式在当前镜像中共存。

## 7. 验证与发布

[`tests/lint.sh`](../tests/lint.sh) 运行 `bash -n`、ShellCheck、测试工具自检和 `git diff --check`。[`tests/run.sh`](../tests/run.sh) 为每个场景建独立容器与匿名卷，以 `abc` 运行库或生命周期测试；配置升级场景复用同一卷并重启。真实生命周期测试通过 aria2 RPC、正式 hook 和本地固定夹具验证结果，不直接 source 生产库或手写其全局变量；异步结果使用有上限的条件轮询。[`tests/mutate.sh`](../tests/mutate.sh) 在专用容器注入故障以验证关键断言。场景清单见 [测试说明](../tests/README.md)。

[构建工作流](../.github/workflows/Build%20Image.yml) 手动触发，覆盖 `standard`、`a2b` 两种变体与 `linux/amd64`、`linux/arm/v7`、`linux/arm64` 三种平台，共六种组合。单架构镜像先按 digest 推送，再做服务连通 smoke-test；amd64 额外运行完整行为测试，a2b 完整就绪也只在 amd64 验证。构建矩阵和 smoke-test 均成功后才合并 manifest，并发布 `dev-*`、`a2b-dev-*` 到 Docker Hub 与 GHCR。[Shell Lint 工作流](../.github/workflows/Shell%20Lint.yml) 对相关 PR/push 运行 ShellCheck 与 actionlint。

```bash
bash tests/lint.sh
./build.sh standard
bash tests/run.sh superng6/aria2:dev-latest standard
./build.sh a2b
bash tests/run.sh superng6/aria2:a2b-dev-latest a2b
```
