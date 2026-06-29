# CLAUDE.md

本文件为 Claude Code 在本仓库中工作时提供项目级指导。
目标是让 Claude 快速理解 docker-aria2 的架构、约束、常用命令和不能破坏的设计契约。

## 项目概览

`docker-aria2` 是一个运行 **aria2 + AriaNg WebUI** 的 Alpine Linux Docker 镜像，提供两个构建变体：

* `standard`：仅 aria2c
* `a2b`：aria2c + aria2b，用于 BT 流量优化和封禁吸血客户端

变体通过 Dockerfile 中的构建参数选择：

```bash
ARG VARIANT=standard
```

本地构建应优先使用：

```bash
./build.sh
./build.sh a2b
./build.sh all
```

不要手动绕过 `build.sh` 去拼 `VARIANT` / `A2B_DEFAULT`，以免本地构建语义和 CI 不一致。

当前主要重构分支：

```text
dev-refactor-20260521
```

该分支将旧 `aria2b` 分支中的单体脚本结构重构为 `root/aria2/scripts/lib/` 模块化结构。旧 `aria2b` 分支仅作历史参考，不应作为当前实现依据。

## 维护原则

本项目的核心原则：

> 用简单方法完成简单任务，只在真实的不确定边界上增加防护。

### 信任边界

容器内部通信是受控边界，应优先保持直接、可读、少参数：

* aria2 hook 调用 `localhost:${PORT}/jsonrpc`
* aria2b 等待同容器内 aria2c RPC
* AriaNg 访问同容器内 RPC / WebUI

外部网络是不可控边界，需要 timeout / retry / fallback：

* tracker 列表
* GitHub Releases / CDN
* 用户自定义 `CTU`
* cron 触发的外部刷新
* 构建阶段的远程下载

不要机械地给所有本地 RPC、localhost curl、内部服务探测加 timeout/retry。只有当失败会卡住用户流程、cron 堆积、构建挂起或跨越外部网络时，才增加防护。

### 不做“万能修复”

避免引入会增加语义重量但收益不明确的改动，例如：

* 给所有缺失配置 key 自动补齐
* 把 `setting.conf` 选项重新做成环境变量
* 给所有 localhost RPC 机械加 timeout
* 大范围格式化无关文件
* 重写已稳定的启动流程

改动前先判断：这是用户可见问题，还是形式上的“更完备”。

## 上游依赖

本镜像由三个上游组合而成。不要根据旧记忆猜行为，有疑问时查实际代码或 release。

### 基础镜像

基础镜像：

```text
superng6/alpine:3.23
```

来源：

```text
SuperNG6/docker-baseimage-alpine
```

它是 linuxserver/docker-baseimage-alpine 的 fork，使用 **s6-overlay v2.2.0.3**。本项目明确使用 s6 v2，不是 v3。

基础镜像已经提供：

* `bash`
* `curl`
* `wget`
* `ca-certificates`
* `coreutils`
* `procps`
* `shadow`
* `tzdata`
* `abc` 用户
* `/app`
* `/config`
* `/defaults`
* `/usr/bin/with-contenv`

不要在 Dockerfile 中重复安装基础镜像已经稳定提供的核心能力，除非有明确原因。

重要细节：

* `abc` 默认 UID 911
* 主组也是 `abc`
* 附加组为 `users`，GID 1000
* 家目录为 `/config`
* shell 为 `/bin/false`
* `coreutils` 很关键，`lib/files.sh#_CHECK_SPACE` 依赖 GNU `du -b`、`df --output=avail -B1`、`stat -c %d`

基础镜像中的 cont-init 脚本顺序早于本项目脚本：

* `01-envfile`
* `10-adduser`

不要破坏这个顺序假设。

### aria2b

aria2b 来源：

```text
SuperNG6/aria2b
```

仅在 `a2b` 变体中使用。它是 Node.js 脚本，监控 aria2 RPC，并通过 `iptables` + `ipset` 封禁吸血 BT 客户端。

运行要求：

* Linux
* Node.js 22+
* `--cap-add NET_ADMIN`
* 某些主机还需要挂载 `/lib/modules:/lib/modules:ro`

当前要求固定使用：

```text
aria2b >= v2.1.0
```

不要降级到 v2.0.0。v2.0.0 存在严重问题：`scanTimer.unref()` 会导致 Node 进程在扫描后静默退出，在 s6 监管下形成约 10 秒一次的重启循环。

aria2b 从 `/config/aria2.conf` 读取 `ab-` 前缀配置，例如：

* `ab-bt-ban-client-keywords`
* `ab-bt-noprogress-keywords`
* `ab-bt-noprogress-piece`
* `ab-bt-noprogress-wait`
* `ab-bt-scan-interval`
* `ab-bt-ban-timeout`
* `ab-rpc-no-verify`
* `ab-rpc-ca`
* `ab-rpc-cert`
* `ab-rpc-key`

`services.d/aria2b/run` 启动时传入：

```bash
-c /config/aria2.conf
-u http://127.0.0.1:${PORT}/jsonrpc
-s "${SECRET}"
```

默认封禁关键字：

```text
XL,SD,XF,QD,BN
```

默认扫描间隔：

```text
5000ms
```

## 运行时栈

* Init：`/init`
* s6-overlay：v2.2.0.3
* WebUI：`darkhttpd` 服务 `/www`
* aria2 进程用户：`abc`
* aria2 启动方式：`s6-setuidgid abc`
* 配置持久化目录：`/config`
* 下载目录：通常为 `/downloads`

本 Dockerfile 在基础镜像之上添加：

* `darkhttpd`
* `jq`
* `findutils`
* `aria2c`
* AriaNg AllInOne 静态文件
* `root/` overlay

`a2b` 变体额外添加：

* `iptables`
* `iptables-legacy`
* `ipset`
* `nodejs`
* `aria2b`

## s6-overlay v2 约束

本项目使用 s6-overlay v2，不是 v3。

v2 路径：

```text
/etc/cont-init.d/
/etc/services.d/<service>/run
```

不要改成 v3 风格路径：

```text
/etc/s6-overlay/init.d/
/etc/s6-overlay/s6-rc.d/
```

禁用不应运行的服务时使用：

```bash
exec s6-svc -d .
```

这用于 `services.d/aria2b/run` 中 `A2B != true` 的情况。不要改成简单 `exit 0`，否则 s6 会不断重启服务。

## 目录结构

```text
root/
├── aria2/
│   ├── conf/
│   │   ├── aria2.conf.default
│   │   ├── setting.conf
│   │   ├── 文件过滤.conf
│   │   ├── rpc-tracker0
│   │   └── rpc-tracker1
│   └── scripts/
│       ├── lib/
│       │   ├── event.sh
│       │   ├── log.sh
│       │   ├── config.sh
│       │   ├── files.sh
│       │   ├── filter.sh
│       │   ├── torrent.sh
│       │   ├── rpc.sh
│       │   └── tracker.sh
│       ├── completed.sh
│       ├── start.sh
│       ├── stop.sh
│       └── pause.sh
└── etc/
    ├── cont-init.d/
    │   ├── 11-version
    │   ├── 20-config
    │   ├── 30-config
    │   ├── 40-config
    │   ├── 50-config
    │   ├── 90-custom-folders
    │   └── 99-custom-scripts
    └── services.d/
        ├── aria2/run
        └── aria2b/run
```

`90-custom-folders` 和 `99-custom-scripts` 是有意保留的空钩子，不要删除。

## 事件脚本契约

所有事件脚本都应 source：

```bash
lib/event.sh
```

并调用：

```bash
INIT_EVENT <type> "$@"
```

`type` 目前包括：

* `completed`
* `recycle`

`INIT_EVENT` 内部顺序不可随意更改：

```text
GET_BASE_PATH
→ COMPLETED_PATH 或 RECYCLE_PATH
→ GET_RPC_INFO
→ GET_FINAL_PATH
```

`type` 必须在 `GET_FINAL_PATH` 前决定 `TARGET_DIR`。打破顺序会导致路径计算错误。

事件钩子包括：

* `completed.sh`
* `start.sh`
* `stop.sh`
* `pause.sh`

这些脚本用：

```bash
#!/usr/bin/env bash
```

而不是 `with-contenv`。

原因：它们由 aria2c fork-exec，继承 aria2c 环境；aria2c 自身由 `services.d/aria2/run` 通过 `with-contenv` 启动。因此 `PORT`、`SECRET`、`CTU` 等环境变量可以传递给 hook。

## lib 目录规则

### 路径解析

`lib/event.sh` 使用：

```bash
dirname "${BASH_SOURCE[0]}"
```

不要改成 `$0`。这些库文件是被 source 的，使用 `$0` 会解析到调用脚本或 shell，而不是库文件本身。

### 全局变量命名

跨库共享的全局变量必须按用途命名，避免按脚本名命名。

已有约定：

* `SETTING_CONF`：`/config/setting.conf`
* `FILTER_CONF`：`/config/文件过滤.conf`

新增共享全局变量前先检查冲突：

```bash
grep -r '<NAME>' root/aria2/scripts/lib/
```

### 库函数不要随便 exit

事件辅助库应返回非零，并把错误写入 stderr。是否中止应由调用方决定。

例如：

```bash
GET_RPC_INFO || exit 1
```

独立 CLI 式脚本可以直接 exit，例如 `lib/tracker.sh` 的命令入口。

## 配置模型

### `/config/aria2.conf`

`cont-init.d/30-config` 每次启动都会用环境变量重写部分 aria2 配置。

以下 key 会被重写，不要建议用户长期手动编辑这些行：

| aria2.conf key         | 来源                                |
| ---------------------- | --------------------------------- |
| `on-download-stop`     | 硬编码 `/aria2/scripts/stop.sh`      |
| `on-download-complete` | 硬编码 `/aria2/scripts/completed.sh` |
| `on-download-pause`    | 硬编码 `/aria2/scripts/pause.sh`     |
| `on-download-start`    | 硬编码 `/aria2/scripts/start.sh`     |
| `rpc-listen-port`      | `PORT`                            |
| `dht-listen-port`      | `BTPORT`                          |
| `listen-port`          | `BTPORT`                          |
| `bt-save-metadata`     | `SMD`                             |
| `file-allocation`      | `FA`                              |
| `bt-tracker`           | `UT=true` 时由 tracker 更新           |

这些 key 假定存在于默认模板中。`30-config` 使用锚定 sed 替换，不自动追加缺失 key。

如果用户手动删除 key，sed 会 no-op。这是可接受的用户破坏配置场景。不要重新加入 ensure-key 预处理，除非有新的明确需求。

### `/config/setting.conf`

`setting.conf` 是脚本行为设置的唯一真相源。

这些选项不接受环境变量：

| setting.conf key     | 默认值             |
| -------------------- | --------------- |
| `move-task`          | `false`         |
| `remove-task`        | `rmaria`        |
| `content-filter`     | `false`         |
| `delete-empty-dir`   | `true`          |
| `handle-torrent`     | `backup-rename` |
| `remove-repeat-task` | `true`          |
| `move-paused-task`   | `false`         |

不要重新实现 `MOVE` / `RMTASK` / `CF` / `DET` / `TOR` / `RRT` / `MPT` 环境变量 seeding。

历史上曾尝试让这些行为变量首次启动时从 env seed 到 `setting.conf`，后来撤销。原因是“环境变量只在首次创建时生效”的半生效语义会误导用户。

正确做法：

* 用户要改行为：编辑 `/config/setting.conf`
* 或通过 WebUI / 项目提供的配置入口修改
* 不需要重启容器；下一次 hook 执行会重新 LOAD_CONF

### setting.conf 升级策略

`20-config` 处理逻辑：

* 首次启动：复制模板到 `/config/setting.conf`
* 后续启动：

  * 读取现有值
  * 用最新模板生成 `setting.conf.new`
  * 将已知 key 的用户值写回
  * 原子替换旧文件

这样可以保留用户设置，同时拾取新增模板 key。

## 关键环境变量

活跃环境变量：

| 变量                |                    默认值 | 说明                         |
| ----------------- | ---------------------: | -------------------------- |
| `VARIANT`         |             `standard` | 构建变体                       |
| `A2B`             | `false` / a2b 为 `true` | 是否启用 aria2b                |
| `A2B_DISABLE_LOG` |                `false` | 是否屏蔽 aria2b 输出             |
| `SECRET`          |            `yourtoken` | RPC token；默认值有安全风险         |
| `PORT`            |                 `6800` | aria2 RPC 端口               |
| `BTPORT`          |                `32516` | BT / DHT 端口                |
| `WEBUI`           |                 `true` | 是否启用 AriaNg WebUI          |
| `WEBUI_PORT`      |                 `8080` | WebUI 端口                   |
| `UT`              |                 `true` | 启动时更新 tracker 到 aria2.conf |
| `RUT`             |                 `true` | cron 每日经 RPC 更新 tracker    |
| `SMD`             |                 `true` | `bt-save-metadata`         |
| `FA`              |               `falloc` | `file-allocation`          |
| `CACHE`           |                 `128M` | aria2c disk cache          |
| `QUIET`           |                 `true` | aria2c quiet               |
| `CRA2B`           |                   `2h` | aria2b cron 重启间隔           |
| `CTU`             |                      空 | 自定义 tracker URL            |
| `TZ`              |        `Asia/Shanghai` | 时区                         |
| `PUID` / `PGID`   |         `1026` / `100` | 运行用户映射                     |

注意：

* `SECRET=yourtoken` 是公开默认值，`11-version` 会显示警告。
* `QUIET=true` 会同时屏蔽 stdout 和 stderr。调试 aria2c 启动失败时使用：

```bash
-e QUIET=false
```

## cron 规则

`30-config` 将 tracker cron 写入：

```text
/etc/crontabs/root
```

不要把它“修复”为：

```text
/var/spool/cron/crontabs/
```

当前路径在本 Alpine 基础镜像中有效。

`40-config` 使用：

```bash
crontab -l
crontab -
```

注册 aria2b 重启 cron。两个路径在本镜像中可以共存，不冲突。

`30-config` 应始终启动 crond。不要改回仅在 `RUT=true` 时启动，否则 aria2b 重启 cron 和 Alpine periodic 会失效。

## tracker 更新规则

`lib/tracker.sh` 同时支持：

```bash
tracker.sh file
tracker.sh rpc
```

规则：

* `file` 模式写入 `aria2.conf`
* `rpc` 模式通过 JSON-RPC 推送到运行中的 aria2c
* 外部 tracker / CTU 请求必须有 timeout
* RPC 成功判断必须解析 JSON，不要用 `grep OK`

正确成功判断示例：

```bash
jq -e '.result == "OK"'
```

不要用：

```bash
grep -q OK
```

错误响应中可能包含字符串 `OK`。

## 构建规则

CI 通过 `workflow_dispatch` 手动触发。

矩阵：

* variant：`standard`、`a2b`
* platform：`linux/amd64`、`linux/arm/v7`、`linux/arm64`

流程：

```text
build → smoke-test → merge
```

规则：

* build 阶段按 digest 推送
* smoke-test 只在 amd64 runner 上运行
* smoke-test 通过后才 merge 成用户可见 tag
* 失败测试绝不发布用户可见 tag

dev 分支 tag：

```text
standard:
  dev-latest
  dev-<yy-mm-dd>

a2b:
  a2b-dev-latest
  a2b-dev-<yy-mm-dd>
```

buildx 缓存有意禁用。Dockerfile 会通过远程 release 拉最新 AriaNg / aria2c / aria2b；启用 GHA 缓存可能把版本冻结在陈旧层。

不要轻易恢复构建缓存。

## 架构检测

builder 阶段使用：

```bash
uname -m
```

原因：buildx + QEMU 会让 builder 作为目标架构运行，所以 `uname -m` 在这里可靠。

映射：

| `uname -m`          | Aria2-Pro-Core asset               |
| ------------------- | ---------------------------------- |
| `x86_64`            | `aria2-static-linux-x86_64.tar.gz` |
| `aarch64`           | `aria2-static-linux-arm64.tar.gz`  |
| `armv7l` / `armv6l` | `aria2-static-linux-armhf.tar.gz`  |
| `i386` / `i686`     | `aria2-static-linux-i386.tar.gz`   |

不要无理由改成 `ARG TARGETARCH`。

## 测试

### 宿主侧 RPC 集成测试

脚本：

```text
.github/scripts/rpc-integration-test.sh
```

用法：

```bash
.github/scripts/rpc-integration-test.sh <host> <port> <secret> [container-name] [variant]
```

覆盖重点：

* aria2 JSON-RPC 基础能力
* HTTP 下载
* 磁力任务
* torrent 提交
* pause / unpause / remove
* aria2.conf 默认值断言
* tracker RPC 端到端
* MOVE 端到端

注意：`rpc()` helper 通过 stdin 把参数传给 `jq`，用于绕过 Linux 单参数 128KB 限制。不要重构回 `--argjson`，torrent base64 可能超长。

### 容器内 lib 单元测试

脚本：

```text
.github/scripts/in-container-lib-test.sh
```

用法：

```bash
docker cp .github/scripts/in-container-lib-test.sh aria2-local:/tmp/
docker exec aria2-local bash /tmp/in-container-lib-test.sh
```

覆盖重点：

* filter
* move
* delete / recycle / `.aria2`
* torrent 处理
* path 计算
* RRT 重复任务处理
* tracker
* config 升级保留
* version banner
* log demo

该脚本有意不开 `set -u`。不要强行加。部分日志函数依赖 hook 场景中的隐式变量，单元测试无法总是预设。

## 常用命令

### 语法预检

```bash
bash -n .github/scripts/rpc-integration-test.sh
bash -n .github/scripts/in-container-lib-test.sh
bash -n root/aria2/scripts/lib/*.sh
bash -n root/etc/cont-init.d/*-* root/etc/services.d/*/run
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/Build Image.yml'))"
```

### ShellCheck

```bash
shellcheck --severity=warning -x \
  root/aria2/scripts/lib/*.sh \
  root/aria2/scripts/*.sh \
  root/etc/cont-init.d/*-* \
  root/etc/services.d/*/run \
  .github/scripts/*.sh \
  build.sh
```

### 本地构建

```bash
./build.sh
./build.sh a2b
./build.sh all
```

### 触发当前分支 CI

```bash
gh workflow run "Build Image.yml" --ref "$(git rev-parse --abbrev-ref HEAD)"
```

### 查看最新运行

```bash
gh run list --workflow="Build Image.yml" \
  --branch "$(git rev-parse --abbrev-ref HEAD)" \
  --limit 3

gh run view <run-id> --log-failed
```

### 本地 smoke-test：standard

```bash
IMAGE=ghcr.io/superng6/aria2:dev-latest

docker run -d --name aria2-local \
  -p 16800:6800 \
  -p 18080:8080 \
  -e SECRET=smoketoken \
  -e UT=false \
  -e RUT=false \
  "${IMAGE}"

.github/scripts/rpc-integration-test.sh \
  127.0.0.1 16800 smoketoken aria2-local standard

docker cp .github/scripts/in-container-lib-test.sh aria2-local:/tmp/
docker exec aria2-local bash /tmp/in-container-lib-test.sh

docker rm -f aria2-local
```

### 本地 smoke-test：a2b

```bash
docker run -d --name aria2b-local \
  --cap-add NET_ADMIN \
  -v /lib/modules:/lib/modules:ro \
  -p 16801:6800 \
  -p 18081:8080 \
  -e A2B=true \
  -e SECRET=smoketoken \
  -e UT=false \
  -e RUT=false \
  ghcr.io/superng6/aria2:a2b-dev-latest
```

## 修改前 checklist

修改前先判断属于哪一类：

### Dockerfile / 构建

* 是否影响 `standard` 和 `a2b` 两个变体？
* 是否影响 amd64 / arm64 / arm/v7？
* 是否破坏 no-cache 拉最新 release 的设计？
* 是否重复安装基础镜像已有包？
* 是否需要同步 `build.sh` 和 CI matrix？

### s6 / 启动流程

* 是否仍是 s6-overlay v2 路径？
* cont-init.d 数字顺序是否正确？
* 不应运行的服务是否用 `exec s6-svc -d .` 禁用？
* `crond` 是否仍会始终启动？
* `with-contenv` 是否只用于服务入口，而不是 aria2 hook？

### 配置

* 是否误把 `setting.conf` 选项做成环境变量？
* 是否误改 `aria2.conf` 重写 key 的规则？
* 是否引入 ensure-key 之类“自动修复”逻辑？
* 是否保留用户已有 `/config` 配置？

### 事件脚本 / lib

* 是否保持 `INIT_EVENT` 顺序？
* 是否保持 `BASH_SOURCE[0]` 路径解析？
* 库函数是否避免直接 `exit`？
* 新增全局变量是否检查命名冲突？
* 是否保持 hook 继承 aria2c 环境的模型？

### 网络与 timeout

* 外部网络请求是否设置 timeout？
* 本地 localhost RPC 是否被不必要地复杂化？
* cron 路径是否可能因网络卡住而堆积？
* tracker RPC 成功判断是否解析 JSON？

### 测试

* 是否运行 bash 语法检查？
* 是否运行 shellcheck？
* 是否影响 RPC 集成测试？
* 是否影响容器内 lib 测试？
* 是否需要更新 smoke-test？

## 已知且接受的设计

以下事项已评审并接受，不要重复当作 bug 提出：

### `11-version` 中 aria2c 版本字符串可能陈旧

启动横幅中 aria2c 版本字符串可能与实际二进制版本漂移。真实版本可通过：

```bash
aria2c --version
```

获取。

该问题只影响展示，不影响控制流，暂不修复。

### `setting.conf` 不接受 env var

这是有意设计。行为设置以 `/config/setting.conf` 为唯一接口。

### 本地 RPC 不强制 timeout

localhost RPC 属于受控边界，不默认添加复杂 timeout/retry。

### `completed.sh` 后台执行 MOVE_FILE

大跨盘移动不应阻塞 aria2c hook fork。`MOVE_FILE &` 是有意设计。

### cron 路径共存

`/etc/crontabs/root` 和 `crontab -l` / `crontab -` 在本镜像中可以共存，不要强行统一。

## 持久化配置

用户持久化配置位于 `/config`：

```text
/config/aria2.conf
/config/setting.conf
/config/文件过滤.conf
/config/logs/
/config/backup-torrent/
```

升级镜像时必须尽量保留用户已有配置。只有模板新增 key 时，通过既有升级逻辑合并。

## 推荐工作方式

1. 先读相关脚本，不要凭旧印象修改。
2. 小步改动，避免横跨多个子系统。
3. 对启动流程、配置迁移、hook 顺序保持保守。
4. 修改后至少运行语法检查和 shellcheck。
5. 涉及下载、tracker、move、a2b、配置升级时，补充或运行对应 smoke-test。
6. 如果一个改动只是“看起来更完整”，但没有用户可见收益，优先不做。
