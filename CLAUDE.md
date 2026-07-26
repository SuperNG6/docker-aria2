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

除“已知且接受的设计”中明确列出的 Dockerfile GitHub 下载外，外部网络是不可控边界，需要 timeout / retry / fallback：

* tracker 列表
* 用户自定义 `CTU`
* cron 触发的外部刷新

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

本镜像由四个上游组合而成。不要根据旧记忆猜行为，有疑问时查实际代码或 release。

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

`services.d/aria2b/run` 从 `/config/aria2.conf` 的有效 `rpc-secure=true`
选择本地 RPC 协议；注释行或其他值使用 HTTP，启用时使用 HTTPS。启动时传入：

```bash
-c /config/aria2.conf
-u <http|https>://127.0.0.1:${PORT}/jsonrpc
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

> 本镜像在基础镜像上额外安装哪些包、`a2b` 变体额外加什么，参见 `Dockerfile`，不在此复述。

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

这用于可选服务：

* `services.d/aria2b/run`：`A2B != true`
* `services.d/webui/run`：`WEBUI != true`

不要改成简单 `exit 0`，否则 s6 会不断重启服务。

WebUI 的 `darkhttpd` 必须以前台模式运行，由 s6 直接监管；不要添加 `--daemon`，
也不要重新放回 `cont-init.d` 后台启动。

## 目录结构

仓库根下分 `root/`（容器 overlay：`aria2/` 脚本与配置、`etc/` s6 启动钩子）两层；完整文件树可由 `find root -type f` 重建，不在此罗列。

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

`IS_TASK_SOURCE_PATH` 除拒绝 `/downloads` 根目录外，还必须拒绝项目共享目录本身：

* `/downloads/completed`
* `/downloads/recycle`
* `/downloads/move-failed`

多文件 BT 根目录可能与这些名称撞名，不能把共享目录中的历史内容当成本次任务整体移动或删除。

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

### 内容过滤保护

内容过滤只在任务源路径内实际存在多个文件时运行。执行删除前必须用相同规则预判
所有待删除路径，并对多条规则重复命中的文件去重。

如果规则组合会删除当前任务的全部文件，本次过滤和空目录清理都必须跳过，
原任务文件继续按正常的完成任务流程保留或移动。不要改回先删除再判断。

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

## 启动信息横幅

`cont-init.d/11-version` 在项目配置初始化前展示本次启动信息。

数据来源按是否会在后续初始化阶段变化区分：

* `PORT`、`BTPORT`、`WEBUI`、`WEBUI_PORT`、`CACHE`、`QUIET`、`UT`、
  `RUT`、`CTU`、`SMD`、`FA`、`A2B` 等显示本次环境变量的预期生效值。
* RPC HTTPS 状态只读取已存在的 `/config/aria2.conf`，首次配置使用默认 HTTP。
* 移动、停止任务处理、过滤、种子处理、重复任务和暂停移动只读取已存在的
  `/config/setting.conf`。
* `setting.conf` 不存在时不逐项展示模板默认值，只提示本次将使用项目默认配置。
* Aria2 版本通过 `aria2c --version` 获取；AriaNg、aria2b 和镜像版本读取
  `/aria2/build-date`。
* standard / a2b 变体通过 `/usr/local/bin/aria2b` 是否存在判断，不依赖构建期 ARG。
* RPC token 只展示未配置、默认令牌或已配置状态，绝不输出自定义 token。

横幅展示的是初始化配置，不代表 aria2c、WebUI 或 aria2b 已完成健康检查，因此文案不得写成
“服务启动成功”。

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

`40-config` 仅在 `A2B=true` 且 `/usr/local/bin/aria2b` 实际存在时使用：

```bash
crontab -l
crontab -
```

注册 aria2b 重启 cron。aria2b v2.2.0 的实际进程是 Node.js，不能用
`pkill -x aria2b`；定时任务必须通过
`s6-svc -r /var/run/s6/services/aria2b` 重启 s6 服务。两个 cron 路径在本镜像中
可以共存，不冲突。standard 镜像即使被用户误设 `A2B=true`，也不得注册
指向不存在服务目录的 aria2b cron。

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
* 所有架构都运行启动与服务连通 smoke-test
* 真实容器场景测试和容器内库级回归测试仅在 amd64 运行
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

## 测试设计

测试目标不是堆积断言数量，而是用最低层级准确覆盖项目自己维护的行为。

### 测试层级

1. 静态检查：

   * `bash -n`
   * ShellCheck
   * YAML / actionlint
   * `git diff --check`

2. 库级回归测试：`.github/scripts/in-container-lib-test.sh`

   只覆盖适合直接调用的确定性逻辑，例如过滤匹配、路径计算、种子处理模式、
   tracker JSON 判断和启动信息格式。脚本必须通过以下方式以正式运行用户执行：

   ```bash
   docker exec --user abc <container> bash /tmp/in-container-lib-test.sh
   ```

   该脚本有意不开 `set -u`；项目库依赖 hook 上下文中的隐式变量。

3. 真实容器场景测试：`.github/scripts/rpc-integration-test.sh`

   覆盖 `/init`、配置文件、aria2 RPC、正式 `on-download-*` hook、异步移动、
   文件系统结果、日志和 UID/GID。当前使用本地 AriaNg HTTP 和一个 12 字节的
   固定多文件 torrent，不依赖公网下载或 tracker。

### 测试编写约束

* 用户可见流程必须优先写真实容器场景，不能只补直接 source 库的测试。
* 真实场景不得 source `lib/*.sh`，不得手写 `SOURCE_PATH`、`TASK_STATUS`、
  `INFO_HASH` 等生产全局变量，也不得在测试里复制 `start.sh` / `stop.sh` /
  `completed.sh` 的条件分支。
* 真实场景应通过 aria2 RPC、容器重启或正式脚本入口触发行为，只断言用户可观察结果：
  RPC 状态、最终文件、日志、服务状态和 UID/GID。
* aria2 hook 权限相关场景必须由以 `abc` 运行的 aria2c 触发；不能用 root
  直接调用库函数代替。
* 配置升级必须至少经过一次真实容器重启并复用同一 `/config`，不能只调用
  `SED_CONF` 后声称升级流程已覆盖。
* 异步行为使用有上限的条件轮询，不使用固定 `sleep` 作为成功判定。
* 测试数据优先使用本地固定夹具，避免把 GitHub、公共 tracker 或外部站点波动
  当成项目测试失败。
* 每个场景开始前显式准备自己的配置和路径，结束后清理自己的 GID 与文件；
  不依赖上一个场景遗留的全局变量或文件。
* 不允许为了增加 PASS 数量，把同一场景中的字段断言包装成多个“测试”。
  汇总数字表示独立测试组或真实场景，不表示内部断言数量。
* 不允许静默跳过关键测试。真实场景缺少容器名、RPC 或必要服务时应直接失败。
* standard 与 a2b 的共享逻辑不机械重复设计两套测试；两变体都运行同一场景是为了
  验证镜像装配一致性，a2b 专属行为另行增加场景。
* arm64 / arm/v7 在 QEMU 下继续只跑启动和服务连通 smoke-test；完整文件场景由
  amd64 覆盖，避免把仿真限制误判为项目问题。
* 不重复验证 aria2 协议栈的下载性能、BT 算法或 RPC 原生语义。固定 torrent
  只作为触发本项目多文件 hook 的载体。

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
* 这是纯函数契约，还是必须经过真实容器/hook 的用户流程？
* 是否错误地在测试里复制了生产分支或手写生产全局变量？
* hook 场景是否由 abc 用户和真实 aria2 RPC 触发？
* 是否使用本地固定夹具并通过条件轮询等待异步结果？
* 是否影响真实容器场景、库级回归或跨架构 smoke-test？

## 已知且接受的设计

以下事项已评审并接受，不要重复当作 bug 提出：

### `setting.conf` 不接受 env var

这是有意设计。行为设置以 `/config/setting.conf` 为唯一接口。

### 本地 RPC 不强制 timeout

localhost RPC 属于受控边界，不默认添加复杂 timeout/retry。

### `completed.sh` 后台执行 MOVE_FILE

大跨盘移动不应阻塞 aria2c hook fork。`MOVE_FILE &` 是有意设计。

### cron 路径共存

`/etc/crontabs/root` 和 `crontab -l` / `crontab -` 在本镜像中可以共存，不要强行统一。

### 回收失败后直接删除

`RMTASK=recycle` 时，移动到回收站失败会降级为永久删除。这是维护者接受的个人项目语义，不改成保留源文件。

### 同名目标允许覆盖

任务文件移动和种子备份继续使用 `mv -f`。同名文件或 `${TASK_NAME}.torrent` 被覆盖属于接受行为，不增加重命名或防碰撞策略。

### 构建阶段 GitHub 下载不强制 timeout

Dockerfile 中 aria2c、AriaNg、aria2b 都从维护者掌控的 GitHub 项目下载。维护者接受等待行为，不为这些 `curl` 增加 timeout / retry。

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
