# docker-aria2 产品需求文档（现状）

> 本文从当前代码与测试倒推已实现的产品行为，不表示待开发计划。实现细节与修改约束见 [开发 Spec](DEVELOPMENT_SPEC.md)，部署参数见 [README](../README.md)。

## 1. 产品定位与使用场景

docker-aria2 面向需要在 NAS 或 Linux 主机上持续下载的用户。它提供可持久化的 aria2 下载服务、AriaNg WebUI，以及任务结束后的文件整理能力。用户可将 `/config` 和 `/downloads` 映射到宿主机，并用 `PUID`、`PGID` 控制下载文件的所有者。

镜像有两种变体：`standard` 提供 aria2c 与 WebUI；`a2b` 额外提供可开关的 aria2b，用于识别并封禁部分 BT 客户端。项目的 a2b 部署示例授予 `NET_ADMIN`，并只读挂载主机的 `/lib/modules`。

## 2. 已实现的用户能力

| 能力 | 用户可见行为与条件 |
| --- | --- |
| 下载与管理 | 通过 aria2 JSON-RPC 和 AriaNg 管理任务；WebUI 可关闭。RPC、WebUI、BT/DHT 端口可配置。 |
| 配置持久化 | `/config` 保存 aria2 配置、项目行为设置、过滤规则、会话、DHT 数据和日志；容器重建时可复用。 |
| 完成后整理 | `move-task=true` 时把任务移动到 `/downloads/completed`，保留下载目录内的相对层级；默认 `false` 时不移动内容，只清理 `.aria2` 控制文件，元数据种子仍按种子策略处理。`dmof` 额外跳过根目录单文件。 |
| 内容过滤 | 在完成或暂停触发的移动清理流程中，`content-filter=true` 可按大小、扩展名、关键词和正则删除任务目录中的文件；仅源路径内实际有多个文件时执行。规则若会删光本任务文件，则跳过本次过滤及空目录清理。`move-task=false` 的完成事件不会过滤。 |
| 停止任务处理 | `remove-task=rmaria` 默认保留任务内容并清理 `.aria2`；也可选 `recycle` 移入 `/downloads/recycle`，或 `delete` 永久删除。三种模式都会按种子策略处理存在的元数据 `.torrent`。下载状态为 error 时跳过处理。 |
| 重复任务拦截 | `remove-repeat-task=true` 时，若文件夹任务已有同名完成目录，清理新任务文件并尝试取消新任务；位于子目录的单文件 BT 任务也按文件夹处理，普通单文件任务不参与判断。 |
| 暂停后移动 | `move-paused-task=true` 时，暂停 30 秒后仍为 paused 才移入 completed；恢复任务或期间关闭开关则保留原文件。默认关闭。 |
| 磁力元数据种子 | 保存的 `.torrent` 文件可保留、删除、重命名、备份或重命名并备份；默认 `backup-rename`，仅在对应文件实际存在时处理。 |
| Tracker 更新 | 默认启动时尝试获取 tracker 并写入配置，且每天 05:00 经 RPC 热更新；可分别用 `UT`、`RUT` 关闭，并用 `CTU` 指定自有来源。 |
| BT 客户端封禁 | 仅 a2b 变体可用；`A2B` 控制启用，`CRA2B` 控制定时重启，`A2B_DISABLE_LOG` 控制输出。 |

## 3. 配置入口与默认行为

容器环境变量控制服务端口、RPC token、缓存、WebUI、tracker 和 aria2b；其中 `PORT=6800`、`WEBUI_PORT=8080`、`BTPORT=32516`、`WEBUI=true`、`UT=true`、`RUT=true`、`SMD=true`。项目文件处理选项只从 `/config/setting.conf` 读取，修改后由下一次事件 hook 读取，无需重启；暂停 hook 在等待后还会重新读取。aria2 原生选项在 `/config/aria2.conf`；部分 key 每次启动会由环境变量覆盖。过滤规则位于 `/config/文件过滤.conf`。

首次启动会创建模板配置。升级时，以新版模板为底稿保留 `setting.conf` 中已知选项的旧值，并补入新增选项；旧文件中的额外注释和未知选项不会保留。启动横幅显示配置摘要和 RPC token 安全状态，不输出自定义 token，也不宣称服务已经通过健康检查。

## 4. 边界与已接受的取舍

- 完成后移动在后台执行；RPC 显示任务完成时，文件整理可能尚未结束。跨盘目标空间不足或移动失败时尝试 `/downloads/move-failed`。
- 回收站移动失败会改为永久删除。移动使用 `mv -f`，同名文件或种子备份可能被覆盖；同名非空目录冲突时移动可能失败，并尝试 `move-failed` 退路。
- 暂停后移动可能破坏原路径上的续传；已完成目录与历史任务重名时，开始事件的去重也可能误判。两个开关均可在 `setting.conf` 中关闭。
- 默认 `SECRET=yourtoken` 是公开令牌；对外开放 RPC 前应设置自己的随机 token。空 token 会关闭 RPC 密钥要求。

## 5. 验收依据

[`tests/run.sh`](../tests/run.sh) 的隔离容器场景验证初始化身份、配置热修改与升级、HTTP/BT 完成、过滤、跨盘和失败回退、重复任务、暂停、回收及删除。测试使用本地固定夹具和真实 aria2 hook；完整文件场景在 amd64 运行，其他目标架构由 CI 服务连通检查覆盖。场景操作与预期结果见 [测试说明](../tests/README.md)。
