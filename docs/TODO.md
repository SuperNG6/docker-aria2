## aria2-dev 对齐 docker-aria2 的功能待办

本文对比原项目 `docker-aria2` 与重构目录 `aria2-dev` 的配置、脚本与运行逻辑，给出已覆盖能力与待补齐项，并附实施建议与验收标准。

### 已覆盖功能（功能等价/改进）
- 事件回调统一：已将 on-download-start/complete/pause/stop 对齐到 `aria2-dev/root/aria2/scripts/handlers/*`，实现与原项目相同的行为。
- 任务后处理能力：
  - 下载完成移动（MOVE=true/dmof/false）、内容过滤（content-filter）、删除空目录（delete-empty-dir）、回收站（remove-task=recycle）、删除（remove-task=delete）、仅删.aria2（remove-task=rmaria）。
  - 暂停即移动（move-paused-task）。
  - 重复任务检测与移除（remove-repeat-task）。
- 种子文件处理：按 setting.conf 的 handle-torrent=retain/delete/rename/backup/backup-rename 处理 .torrent 文件。
- Tracker 更新：
  - 容器启动时按 UT=true 更新 `bt-tracker` 到 `/config/aria2.conf`。
  - 按 RUT=true 每日 05:00 通过 RPC 动态更新（无需重启 aria2）。
  - 支持自定义 Tracker 源 CTU（逗号分隔多源，去重合并）。
- 运行时参数：
  - `PORT/BTPORT/SMD/FA/CACHE/QUIET/WEBUI/WEBUI_PORT` 等环境变量均已写回或作用于 aria2 运行/配置。
  - WebUI（AriaNg + darkhttpd）与可选端口，支持挂载 `/www` 覆盖界面。
- 初始化与权限：
  - 自动生成 `/config` 与 `/downloads` 必要目录、session/dht/logs 文件。
  - 统一日志与启动面板（11-banner）。
  - 权限与可执行位处理（PUID/PGID 基于基础镜像内置用户 abc）。
- 最新依赖：
  - 通过 GitHub API 拉取 AriaNg AllInOne 最新版。
  - 使用静态编译 aria2c，可与原项目一致。

### 待补齐功能（来自原项目但重构中缺失）
1) setting.conf 的“缺省回填/容错回写”（原项目 SED_CONF 逻辑）
   - 缺失现状：`aria2-dev` 已提供 `lib/config.sh` 内的 `config_apply_setting_defaults`，但当前未在初始化阶段调用；若用户误删 setting.conf 部分键，运行期可能读取到空值。
   - 实施建议：
  - 在 `root/etc/cont-init.d/20-config` 中，当检测到 `/config/setting.conf` 已存在时，调用 `config_apply_setting_defaults`，实现“复制模板 → 覆盖用户值 → 为缺失键填默认值 → 原子替换”。
   - 验收标准：
     - 手工删除 setting.conf 任意键后重启容器，文件被自动补齐为完整可用版本，且保留用户已设置的值。
   - 状态：已实现（见 `root/etc/cont-init.d/20-config` 末尾调用）。

2) 文档与样例对齐
   - docker-compose 示例：原项目示例包含 `network_mode: host`（并建议使用）与 A2B 模式的能力声明；`aria2-dev` 目前仅以显式端口映射演示。
   - 实施建议：
     - 增补一份 `docker-compose.host.yml` 样例；在 README 或本 TODO 链接处说明 Host 模式的利弊与使用场景。
  - （本次重构不纳入 A2B，故略）
   - 验收标准：
     - 两种 compose 模式均可一键运行并通过 AriaNg/RPC 正常访问。

### 可选优化（非阻塞）
- 运行输出：明确重定向到控制台不纳入本次重构；当前使用 s6/exec 默认转发即可。
- Cron 时间可配置：如需自定义 RUT 时间点，可新增 ENV（如 `RUT_AT="5:00"`）并在 `40-tracker` 解析写入 crontab。

---

## 执行清单（Action Items）
- [x] setting.conf 初始化回填逻辑：在 `20-config` 调用 `config_apply_setting_defaults`
- [ ] 文档与 compose 样例补充（host 模式示例）

## 参考位置（证据链）
- 原项目
  - `docker-aria2/root/etc/cont-init.d/30-config`、`40-config`（事件钩子、端口、SMD、FA、UT/RUT）
  - `docker-aria2/root/aria2/script/*`（start/stop/completed/pause、setting、core、tracker、rpc_tracker）
  - README 中的 A2B/CRA2B/A2B_DISABLE_LOG、CTU、RUT/UT、功能说明
- 重构目录
  - `aria2-dev/root/etc/cont-init.d/*`（11-banner、20-config、30-aria2-conf、40-tracker、50-darkhttpd、60-permissions）
  - `aria2-dev/root/aria2/scripts/*`（handlers、lib、utils/tracker.sh）

## 备注
- 基础镜像 `superng6/alpine:3.22` 与静态 aria2c/AriaNg 获取逻辑与原项目保持一致；A2B 为可选增强，默认关闭不影响现有流程。
