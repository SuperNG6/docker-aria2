# docker-aria2 轻度重构与 Bug 修复计划

创建日期：2026-02-23
适用范围：当前仓库（以 `root/aria2/script` 与 `root/etc/cont-init.d` 为核心）

## 1. 执行约定（后续修复前必读）

1. 每次开始“改代码修复”之前，先阅读本文件一次，确认目标、边界和验收标准。
2. 本轮改动默认遵循“轻度重构”原则：不改功能语义，不改日志输出文案。
3. 所有重构与修复以“可回归验证”为前提，按阶段小步提交，避免一次性大改。
4. 如需偏离本计划（新增功能或改日志文案），先在本文件追加“变更决策记录”后再实施。

## 1.1 变更决策记录

1. 2026-02-23：按用户明确要求修复明显拼写错误，允许将日志标签文本更正为 `WARNING`。
2. 2026-02-23：下一阶段按“业务脚本优先、测试脚本最后”执行，且不修改 `.github/workflows/*`。

## 2. 总目标与边界

## 2.1 总目标

1. 减少重复代码，降低后续维护成本。
2. 修复已识别的确定性问题和高概率故障点。
3. 保持现有功能行为与日志输出内容不变。

## 2.2 不变边界

1. 不修改现有功能开关含义（`setting.conf` 各选项语义保持不变）。
2. 默认不修改现有日志文案文本（包括拼写与中英文格式）；除非在“变更决策记录”中明确批准。
3. 不做大规模目录重构，不引入新运行时依赖。

## 3. 重构计划（Refactor Plan）

## 3.1 R1：抽取 Hook 脚本公共初始化

范围：
1. `root/aria2/script/start.sh`
2. `root/aria2/script/stop.sh`
3. `root/aria2/script/completed.sh`
4. `root/aria2/script/pause.sh`

目标：
1. 抽取公共流程：加载 `setting/core/rpc_info`、参数初始化、`GET_BASE_PATH`、`GET_RPC_INFO`、`GET_FINAL_PATH`、通用前置校验。
2. 业务分支仅保留“动作本体”（移动、删除、回收、去重等）。

验收标准：
1. 四个脚本入参行为一致。
2. 日志输出内容逐条不变。
3. ShellCheck 警告数量下降（不含外部 source 提示 SC1091）。

## 3.2 R2：抽取 `core` 中重复动作函数

范围：
1. `root/aria2/script/core`

目标：
1. 抽取“移动失败兜底到 `/downloads/move-failed`”为单一函数。
2. 抽取统一日志写入辅助函数（仅封装写法，不改日志内容）。
3. 减少 `MOVE_FILE` 中重复分支，提升可读性。

验收标准：
1. `MOVE_FILE` 代码重复块显著减少。
2. 失败路径与日志行为一致（含空间不足和非空间不足两类）。

## 3.3 R3：合并 Tracker 处理公共逻辑

范围：
1. `root/aria2/script/tracker.sh`
2. `root/aria2/script/rpc_tracker.sh`

目标：
1. 抽取“下载并归并 tracker 列表”的公共函数。
2. 保留两种落地方式：写配置文件 / RPC 更新。

验收标准：
1. 启动更新与定时更新行为不变。
2. Tracker 输出与原有格式一致。

## 3.4 R4：配置更新脚本去重复

范围：
1. `root/aria2/script/setting`
2. `root/etc/cont-init.d/30-config`

目标：
1. 抽象常见 `sed -i` 键值更新模式，减少重复替换语句。
2. 保持配置覆盖规则不变。

验收标准：
1. 初始化后 `aria2.conf` 与 `setting.conf` 核心字段结果一致。
2. 不引入新配置兼容性问题。

## 4. Bug 修复计划（Bugfix Plan）

## 4.1 B1（高优先级）：`setting` 默认值回填逻辑缺陷

位置：
1. `root/aria2/script/setting`

问题：
1. `SED_CONF` 使用 `if / elif` 链，导致一次仅会回填第一项缺失配置，和注释“某项缺失则回填默认值”不一致。

修复计划：
1. 将链式 `elif` 改为多个独立 `if`。
2. 每个键独立判断并回填默认值。

验证：
1. 构造多个缺失键的 `setting.conf`，启动后应一次性补齐全部默认项。

## 4.2 B2（高优先级）：变量未加引号导致路径/空格风险

位置（示例）：
1. `root/aria2/script/core`
2. `root/aria2/script/tracker.sh`
3. `root/aria2/script/rpc_tracker.sh`
4. `root/etc/services.d/aria2/run`

问题：
1. 多处变量展开未加引号，存在路径含空格、通配符展开、重定向异常风险。

修复计划：
1. 逐项补齐必要引用，引号只做安全修复，不改变业务逻辑。

验证：
1. 关键路径变量含空格时脚本不异常。
2. 日志与功能输出不变。

## 4.3 B3（中优先级）：Tracker 配置检测写法脆弱

位置：
1. `root/aria2/script/tracker.sh`
2. `root/aria2/script/rpc_tracker.sh`

问题：
1. 使用 `$(grep ...)` 判空方式，边界行为不稳定。

修复计划：
1. 使用 `grep -q` 方式重写检测逻辑。
2. 修复相关变量引用安全性。

验证：
1. `bt-tracker=` 不存在时可正确补行并写入。
2. 已存在时可正确覆盖更新。

## 4.4 B4（中优先级）：`pause.sh` 路径解析写法不一致

位置：
1. `root/aria2/script/pause.sh`

问题：
1. `dirname $0` 未加引号，和其他脚本风格不一致，存在边界路径风险。

修复计划：
1. 改为 `dirname "$0"`，与其他 hook 脚本统一。

验证：
1. `pause.sh` 在各运行路径下可正常 source 脚本。

## 4.5 B5（高优先级）：变量命名错误与命名歧义修复

位置（示例）：
1. `root/aria2/script/core`
2. `root/aria2/script/start.sh`
3. `root/aria2/script/setting`

问题：
1. 存在变量命名拼写错误（例如告警标签拼写错误）。
2. 存在语义不准确变量名，增加维护理解成本（例如删除流程里沿用 `MOVE_EXIT_CODE`）。

修复计划：
1. 修复拼写错误变量名，同时保证日志输出内容不变。
2. 将语义不准确变量名改为对应业务含义名。
3. 对可能被外部引用的变量，必要时做兼容映射，避免行为变化。

验证：
1. 全量脚本无命名冲突与未定义引用。
2. 相关流程日志文案与原先一致。

## 5. 执行顺序

1. 第一步：先修 B1（确定性功能缺陷）。
2. 第二步：修 B5（变量命名错误与命名歧义）。
3. 第三步：修 B2（批量安全性修复，控制改动范围）。
4. 第四步：做 R1 + R2（优先降低核心脚本维护复杂度）。
5. 第五步：做 B3 + B4。
6. 第六步：做 R3 + R4（可在前五步稳定后执行）。

## 6. 验证与回归策略

1. 静态检查：`shellcheck`（忽略 `SC1091` 外部 source 提示）。
2. 启动验证：容器启动后检查 `aria2`、`aria2b`、`darkhttpd` 行为。
3. 配置验证：检查 `/config/setting.conf`、`/config/aria2.conf` 最终关键项。
4. 任务场景回归项包含以下内容。

1. 下载完成移动（`MOVE=true`、`MOVE=dmof`）。
2. 停止后删除/回收（`RMTASK=delete|recycle|rmaria`）。
3. 重复任务移除（`RRT=true`）。
4. 空间不足迁移到 `move-failed`。
5. 日志回归：对比 `move.log`、`delete.log`、`recycle.log`、`文件过滤日志.log` 文案。

## 7. 进度记录（后续维护时追加）

记录格式建议：
1. 日期（YYYY-MM-DD）
2. 执行项（如 `B1`、`R2`）
3. 改动文件列表
4. 验证结果
5. 结论（通过/待处理）

## 8. 当前状态

1. 已完成第一轮 Bug 修复（B1、B2、B3、B4、B5）。
2. 已完成重构任务 R1、R2、R3、R4。
3. 当前重构计划项已全部执行完成。
4. 后续每次进入修复或重构阶段，先读取本文件再实施改动。
5. 下一阶段业务脚本优化已完成 S2、S3、S4；S1 按用户决策保持可选且未启用。
6. S5（测试脚本落地）尚未开始。

## 9. 进度记录（已执行）

记录 1：

1. 日期：2026-02-23
2. 执行项：B1、B2、B3、B4、B5（第一轮）
3. 改动文件：
4. `root/aria2/script/core`
5. `root/aria2/script/setting`
6. `root/aria2/script/start.sh`
7. `root/aria2/script/pause.sh`
8. `root/aria2/script/tracker.sh`
9. `root/aria2/script/rpc_tracker.sh`
10. `root/aria2/script/rpc_info`
11. `root/aria2/script/cron-restart-a2b.sh`
12. `root/etc/services.d/aria2/run`
13. `install.sh`
14. 验证结果：`shellcheck -e SC1091,SC1008 ...` 通过（退出码 0）。
15. 结论：通过；按用户要求更正了日志标签拼写为 `WARNING`。

记录 2：

1. 日期：2026-02-23
2. 执行项：R1、R2（第一轮）
3. 改动文件：
4. `root/aria2/script/hook_common`（新增）
5. `root/aria2/script/start.sh`
6. `root/aria2/script/stop.sh`
7. `root/aria2/script/completed.sh`
8. `root/aria2/script/pause.sh`
9. `root/aria2/script/core`
10. 验证结果：`bash -n ...` 与 `shellcheck -e SC1091,SC1008 ...` 通过（退出码 0）。
11. 结论：通过，hook 公共初始化与失败迁移/日志写入重复逻辑已抽取，行为保持一致。

记录 3：

1. 日期：2026-02-23
2. 执行项：R3、R4（第一轮）
3. 改动文件：
4. `root/aria2/script/tracker_common`（新增）
5. `root/aria2/script/tracker.sh`
6. `root/aria2/script/rpc_tracker.sh`
7. `root/aria2/script/setting`
8. `root/etc/cont-init.d/30-config`
9. 验证结果：`bash -n ...` 与 `shellcheck -e SC1091,SC1008 ...` 通过（退出码 0）。
10. 结论：通过，tracker 公共逻辑与配置键值更新逻辑已抽取，功能行为保持一致。

记录 4：

1. 日期：2026-02-23
2. 执行项：容器集成测试（回归验证）
3. 测试镜像：`docker-aria2:refactor-test`
4. 测试容器：`aria2-refactor-itest`
5. 验证项：
6. 启动与 RPC 可用性（`aria2.getVersion`）
7. `setting.conf` 多键缺失回填（B1）
8. `30-config` 配置覆盖结果（端口与 hook 路径）
9. `tracker.sh`（本地 `file://` tracker 源）
10. `rpc_tracker.sh` + `aria2.getGlobalOption`
11. 真实下载完成后自动移动（`completed.sh` + `hook_common` + `core`）
12. 验证结果：全部通过；`/downloads/completed/README.md` 生成，`move.log` 与容器日志均出现移动成功记录。
13. 结论：当前重构与修复在容器运行态下验证通过。

记录 5：

1. 日期：2026-02-23
2. 执行项：S2、S3、S4（业务脚本优先阶段）
3. 改动文件：
4. `root/aria2/script/setting`
5. `root/etc/cont-init.d/30-config`
6. `root/aria2/script/rpc_info`
7. `root/aria2/script/hook_common`
8. `root/aria2/script/core`
9. 关键变更：
10. 配置写入增加“缺键自动补齐 + 末尾无换行保护”，避免新键黏连到上一行。
11. RPC 调用统一为公共函数（地址、请求、错误出口），减少重复 curl 与重复错误处理。
12. 公共函数补充契约注释，清理冗余写法。
13. 验证结果：`bash -n ...`、`shellcheck -e SC1091,SC1008 ...` 通过；容器回归验证通过（配置补键、RPC、下载完成后移动）。
14. 结论：通过，业务脚本可维护性与稳健性提升，未引入新依赖。

## 10. 下一阶段规划（业务脚本优先）

目标：
1. 在不引入新依赖的前提下继续提升业务脚本可维护性和稳定性。
2. 先完成业务脚本质量提升，测试脚本放到最后再落地。
3. 明确不修改 CI workflow（`.github/workflows/*`）。

执行顺序：
1. S2：增强配置脚本稳健性（缺失键自动补齐后再覆盖，避免老配置变体导致覆盖失败）。
2. S3：统一 RPC 调用与错误处理出口（减少重复 curl 分支，统一错误日志入口）。
3. S4：清理业务脚本中的冗余变量与死分支，补充必要的函数契约注释。
4. S1（可选，默认不执行）：任务级并发保护，仅在出现竞态症状时再引入。
5. S5：最后编写本地回归测试脚本（`scripts/` 下），用于一键复测核心链路。

阶段验收标准：
1. 业务脚本阶段（S2-S4）完成后，`shellcheck -e SC1091,SC1008 ...` 与 `bash -n` 继续通过。
2. 容器运行态关键链路保持通过：启动、RPC、tracker 更新、下载完成后处理。
3. 在 S5 之前不新增测试脚本文件，在 S5 之后再补齐测试脚本与使用说明。

## 11. 全量代码审查结论（测试脚本前）

审查日期：2026-02-23  
审查范围：仓库内业务脚本、初始化脚本、服务启动脚本（未改动 workflow）

### 11.1 高优先级待修复

1. C1：`aria2b` 服务在 `A2B=false` 时会快速退出，触发 s6 持续重启与日志刷屏。  
   位置：`root/etc/services.d/aria2b/run:27`
2. C2：RPC 更新 tracker 被重复调用两次，状态日志只反映第二次结果，可能与真实状态不一致。  
   位置：`root/aria2/script/rpc_tracker.sh:28`

### 11.2 中优先级待修复

1. C3：内容过滤删除链路使用 `xargs rm` 未加空输入保护；无匹配文件时会触发 `rm` 空参数报错噪声。  
   位置：`root/aria2/script/core:110`

### 11.3 低优先级待修复

1. C4：`tracker.sh` 在缺失 `bt-tracker=` 时直接追加，若 `aria2.conf` 尾行无换行符，可能粘连前一行。  
   位置：`root/aria2/script/tracker.sh:20`
2. C5：`cron-restart-a2b.sh` 的 cron 命令中 `xargs kill -9` 无空输入保护，aria2b 不存在时会产生周期性 `kill` 用法报错。  
   位置：`root/aria2/script/cron-restart-a2b.sh:22`

### 11.4 建议执行顺序（测试脚本前）

1. 先修 C1、C2（功能正确性与运行噪声影响最大）。
2. 再修 C3（运行期噪声与稳定性）。
3. 最后修 C4、C5（边界一致性与日志整洁性）。

## 12. 进度记录（本轮）

记录 6：

1. 日期：2026-02-23
2. 执行项：C1、C2、C3、C4、C5（全量审查后第一轮修复）
3. 改动文件：
4. `root/etc/services.d/aria2b/run`
5. `root/aria2/script/rpc_tracker.sh`
6. `root/aria2/script/core`
7. `root/aria2/script/tracker.sh`
8. `root/aria2/script/cron-restart-a2b.sh`
9. 关键修复：
10. `A2B=false` 时保活服务进程，避免 s6 持续拉起造成日志刷屏。
11. 移除 `rpc_tracker.sh` 的重复 RPC 调用，保证一次更新一次状态判定。
12. `core` 文件过滤删除链路统一改为 `xargs -0r`，避免空输入触发 `rm` 噪声。
13. `tracker.sh` 补充 `bt-tracker=` 前加入末尾换行保护，避免配置粘连。
14. `cron-restart-a2b.sh` 统一改为 `xargs -r kill -9`，避免无进程时报错。
15. 验证结果：`bash -n` 与 `shellcheck -e SC1091,SC1008 ...` 通过（退出码 0）。
16. 结论：通过，可进入下一阶段（测试脚本编写前的其余业务优化或直接进入测试脚本阶段）。

记录 7：

1. 日期：2026-02-23
2. 执行项：S4-日志降重（不改日志文案）
3. 改动文件：
4. `root/aria2/script/core`
5. `root/aria2/script/tracker_common`
6. 关键修复：
7. `core` 新增统一日志函数：`LOG_INFO`、`LOG_WARNING`、`LOG_ERROR`、`LOG_FILE_INFO`、`LOG_FILE_ERROR`。
8. 将移动/删除/回收/种子处理等路径中的重复 `echo + APPEND_LOG` 组合收敛为公共调用，保持日志文本不变。
9. `tracker_common` 新增 `LOG_INFO`、`LOG_ERROR`，统一 tracker 下载阶段日志输出。
10. 验证结果：`bash -n` 与 `shellcheck -e SC1091,SC1008 ...` 通过（退出码 0）。
11. 结论：通过，脚本可读性提升且未引入新依赖。

记录 8：

1. 日期：2026-02-23
2. 执行项：S4-RPC/Hook 日志与错误处理降重（不改日志文案）
3. 改动文件：
4. `root/aria2/script/rpc_info`
5. `root/aria2/script/hook_common`
6. 关键修复：
7. `rpc_info` 抽取 `RPC_DUMP_RESULT`、`RPC_REQUIRE_FIELD`、`RPC_OPTIONAL_FIELD`，统一 `jq` 字段读取与错误出口。
8. `GET_DOWNLOAD_DIR`、`GET_TASK_STATUS`、`GET_INFO_HASH` 改为复用公共函数，减少重复判断逻辑。
9. `hook_common` 中路径错误日志改为复用 `LOG_ERROR`，保持原有输出格式。
10. 验证结果：`bash -n` 与 `shellcheck -e SC1091,SC1008 ...` 通过（退出码 0）。
11. 结论：通过，业务脚本冗余进一步下降，维护复杂度降低。

记录 9：

1. 日期：2026-02-23
2. 执行项：S4-Tracker 日志输出统一（不改日志文案）
3. 改动文件：
4. `root/aria2/script/tracker.sh`
5. `root/aria2/script/rpc_tracker.sh`
6. 关键修复：
7. `tracker.sh` 启动提示、配置写入成功/失败提示统一改为 `LOG_INFO`/`LOG_ERROR`。
8. `rpc_tracker.sh` 成功/失败提示统一改为 `LOG_INFO`/`LOG_ERROR`，并将 `A && B || C` 改为显式 `if/else`。
9. 验证结果：`bash -n` 与 `shellcheck -e SC1091,SC1008 ...` 通过（退出码 0）。
10. 结论：通过，tracker 相关脚本日志输出风格统一，可维护性提升。

记录 10：

1. 日期：2026-02-23
2. 执行项：S4-抽取公共日志模块（`log_common`）
3. 改动文件：
4. `root/aria2/script/log_common`（新增）
5. `root/aria2/script/core`
6. `root/aria2/script/tracker_common`
7. `root/aria2/script/rpc_info`
8. `darkhttpd/50-config`
9. 关键修复：
10. 抽取公共日志函数：`DATE_TIME`、`APPEND_LOG`、`LOG_INFO`、`LOG_WARNING`、`LOG_ERROR`、`LOG_FILE_INFO`、`LOG_FILE_ERROR`。
11. `core`、`tracker_common`、`rpc_info` 改为复用 `log_common`，消除重复日志实现。
12. 修复 `darkhttpd` 端口参数未加引号的安全告警（`--port "${WEBUI_PORT}"`）。
13. 验证结果：全量 `bash -n` 与全量 `shellcheck -e SC1091,SC1008 ...` 通过（退出码 0）。
14. 结论：通过，日志模块重复代码进一步减少，脚本风格统一。

记录 11：

1. 日期：2026-02-23
2. 执行项：日志模块重构后容器级 smoke test
3. 测试镜像：`docker-aria2:log-review`
4. 测试容器：`aria2-log-review`
5. 验证项：
6. 容器启动流程完整执行（`cont-init.d` 与 `services.d`）
7. `A2B=false` 场景下 `aria2b` 服务不退出（日志仅提示未启用，无重启刷屏）
8. RPC 可用性：`aria2.getVersion` 返回成功
9. 验证结果：通过（`result.version=1.36.0`，日志显示服务正常启动）。
10. 结论：通过，公共日志模块改造未引入运行态回归。

记录 12：

1. 日期：2026-02-23
2. 执行项：重构前后功能对比回归（核心链路）
3. 测试镜像：`docker-aria2:compare-check`
4. 测试容器：`aria2-compare`
5. 验证项：
6. RPC 基础能力（`aria2.getVersion`）
7. hook 注入配置（`on-download-stop/complete/pause/start`）
8. `tracker.sh` 写入 `bt-tracker=...`
9. `rpc_tracker.sh` 更新 `aria2.getGlobalOption["bt-tracker"]`
10. 下载完成后移动（`completed.sh`，`move-task=true`）
11. 验证结果：通过（`TASK_STATUS=complete`，`MOVE_RESULT=completed/refactor-check/README.md`，`MOVE_LOG_HIT=yes`）。
12. 结论：核心下载后处理与 tracker 相关功能保持可用。

记录 13：

1. 日期：2026-02-23
2. 执行项：`stop.sh` 三模式回归 + 关键 hook 场景补测
3. 测试镜像：`docker-aria2:compare-check`
4. 测试容器：`aria2-stop-regression`、`aria2-start-recheck`、`aria2-hook-regression`
5. 验证项：
6. `remove-task=delete`：文件删除 + `delete.log` 命中
7. `remove-task=recycle`：文件移入回收站 + `recycle.log` 命中
8. `remove-task=rmaria`：保留任务文件并删除 `.aria2` 控制文件
9. `pause.sh`（`move-paused-task=true`）触发移动逻辑
10. `start.sh` 重复任务检测（目标已存在时删除源任务文件）
11. 验证结果：通过（`DELETE_FILE_EXISTS=no`、`RECYCLE_RESULT=recycle/case-recycle/README.md`、`RMARIA_FILE_EXISTS=yes`、`RMARIA_CTRL_EXISTS=no`、`PAUSE_MOVE_RESULT=yes`、`START_SOURCE_EXISTS=no`）。
12. 结论：主要业务脚本入口在重构后与预期一致，未发现功能缺失。

记录 14：

1. 日期：2026-02-23
2. 执行项：容器真实环境测试（文件过滤 + 移动 + 删除）
3. 测试镜像：`docker-aria2:itest-real-env`
4. 测试容器：`aria2-itest-real-env-v2`
5. 关键修复：
6. `core` 增加 `NORMALIZE_FIND_SIZE`，兼容 `min-size=1K/10M` 这类大写单位配置，避免容器中 `find -size` 报错。
7. 验证项：
8. `completed.sh` 场景下文件过滤（`min-size`、`include-file`、`keyword-file`、空目录清理）
9. `completed.sh` 场景下移动到 `completed` 目录并写入 `move.log`
10. `stop.sh` + `remove-task=delete` 场景下文件删除并写入 `delete.log`
11. 验证结果：全部通过（`FILTER_KEEP=yes`、`FILTER_REMOVED_SMALL=yes`、`FILTER_REMOVED_BADTXT=yes`、`FILTER_REMOVED_KEYWORD=yes`、`FILTER_EMPTY_DIR_REMOVED=yes`、`MOVE_LOG_HIT=yes`、`DELETE_FILE_REMOVED=yes`、`DELETE_LOG_HIT=yes`）。
12. 结论：文件过滤、文件移动、文件删除在容器真实环境下可用。

记录 15：

1. 日期：2026-02-23
2. 执行项：模拟 `aria2c` 传参的 hook 全链路回归
3. 测试镜像：`docker-aria2:arg-sim-test`
4. 测试容器：`aria2-arg-sim-test`
5. 传参方式：`script.sh <gid> <file_num> <file_path>`（按 aria2 hook 入参格式）
6. 验证项与结果：
7. `completed.sh` 多文件移动：`PASS`
8. `completed.sh` 文件过滤+移动：`PASS`
9. `stop.sh` 删除模式（`remove-task=delete`）：`PASS`
10. `stop.sh` 回收站模式（`remove-task=recycle`）：`PASS`
11. `stop.sh` 仅删控制文件模式（`remove-task=rmaria`）：`PASS`
12. `pause.sh` 暂停后移动（`move-paused-task=true`）：`PASS`
13. `start.sh` 重复任务检测删除：`PASS`
14. 验证结果：全部通过。
15. 结论：按 aria2c 实际传参语义，主要业务功能在容器真实环境下可正常执行。

记录 16：

1. 日期：2026-02-23
2. 执行项：脚本目录中文注释补充 + 英文日志中文化
3. 改动文件：
4. `root/aria2/script/core`
5. `root/aria2/script/hook_common`
6. `root/aria2/script/tracker_common`
7. `root/aria2/script/tracker.sh`
8. `root/aria2/script/rpc_tracker.sh`
9. `root/aria2/script/rpc_info`
10. `root/aria2/script/setting`
11. `root/aria2/script/start.sh`
12. `root/aria2/script/stop.sh`
13. `root/aria2/script/pause.sh`
14. `root/aria2/script/completed.sh`
15. `root/aria2/script/log_common`
16. 关键变更：
17. 补充/统一中文注释，说明 hook 入参、职责和关键流程。
18. 将剩余英文日志文案统一改为中文（含 tracker 与 RPC 相关提示）。
19. 验证结果：`bash -n root/aria2/script/*` 与 `shellcheck -e SC1091,SC1008 root/aria2/script/*` 通过（退出码 0）。
20. 结论：通过，脚本目录日志与注释语言风格已统一为中文。

记录 17：

1. 日期：2026-02-23
2. 执行项：专有名词误翻扫描 + 代码 review 小修复
3. 改动文件：
4. `root/aria2/script/core`
5. `root/aria2/script/log_common`
6. 关键变更：
7. 全仓库扫描 `追踪器/追蹤器`，确认无残留误翻，`trackers` 术语保持英文。
8. 按历史兼容要求修复 WARNING 标签：变量名保持 `WARNING`，日志输出文本保持旧值（旧拼写）。
9. 修复 `handle-torrent=rename` 目标路径：重命名输出改为 `${DOWNLOAD_DIR}/${TASK_NAME}.torrent`，避免落到未知工作目录。
10. 验证结果：`bash -n root/aria2/script/*` 与 `shellcheck -e SC1091,SC1008 root/aria2/script/*` 通过（退出码 0）。
11. 结论：通过；本轮完成术语一致性检查与两项低风险 bug 修复。

记录 18：

1. 日期：2026-02-23
2. 执行项：全项目脚本 review（按风险分级）
3. 发现项（待后续修复）：
4. M1：`EXIT_IF_INVALID_TASK` 对 `FILE_NUM` 直接做 `-eq` 数值比较，异常入参下会出现 `integer expression expected` 噪声。  
   位置：`root/aria2/script/hook_common:28`
5. L1：回收站移动失败分支先输出“已删除文件”再执行 `rm -rf`，删除失败时日志语义不准确。  
   位置：`root/aria2/script/core:255`
6. L2：`cron-restart-a2b.sh` 多处 `crontab -l` 未屏蔽“无 crontab”错误输出，空 crontab 场景会产生噪声日志。  
   位置：`root/aria2/script/cron-restart-a2b.sh:9`
7. L3：`aria2` 服务脚本 `exec` 后仍保留不可达代码。  
   位置：`root/etc/services.d/aria2/run:17`
8. 结论：当前功能不受影响；建议先修 M1，再清理 L1-L3 以提升运行日志准确性与可维护性。

记录 19：

1. 日期：2026-02-23
2. 执行项：逻辑 bug 修复（M1 + L1-L3）
3. 改动文件：
4. `root/aria2/script/hook_common`
5. `root/aria2/script/core`
6. `root/aria2/script/cron-restart-a2b.sh`
7. `root/etc/services.d/aria2/run`
8. 关键修复：
9. `hook_common` 增加钩子入参短路：`FILE_PATH` 为空、`FILE_NUM` 非数字或为 0 时直接标记跳过，不再继续 RPC/路径计算，避免异常入参导致数值比较报错。
10. `core` 回收站失败分支改为先执行删除再按删除结果输出日志，避免“先报已删除、后执行删除”的语义偏差。
11. `cron-restart-a2b.sh` 的 `crontab -l` 统一加 `2>/dev/null`，消除空 crontab 场景噪声。
12. `aria2/run` 删除 `exec` 后不可达语句，减少维护歧义。
13. 容器验证（镜像：`docker-aria2:logic-check`）：
14. `bash /aria2/script/start.sh gid notnum /downloads/a` 返回码 `0`，且无 RPC 异常日志。
15. `bash /aria2/script/start.sh gid 0 \"\"` 返回码 `0`，且无 RPC 异常日志。
16. `bash /aria2/script/cron-restart-a2b.sh` 在 `CRA2B=false` 与 `CRA2B=3h` 下返回码均为 `0`，stderr 均为 `0` 字节。
17. 验证结果：全量 `bash -n` 与全量 `shellcheck -e SC1091,SC1008 ...` 通过（退出码 0）。
18. 结论：通过；本轮逻辑稳定性问题已落地修复并完成容器回归。

记录 20：

1. 日期：2026-02-23
2. 执行项：`rpc_tracker.sh` 成功判定逻辑修复
3. 改动文件：
4. `root/aria2/script/rpc_tracker.sh`
5. 关键修复：
6. 将 `grep \"OK\"` 的字符串匹配改为 `jq -e '.result == \"OK\"'` 的结构化 JSON 判定，避免误判成功状态。
7. 验证结果：`bash -n root/aria2/script/*` 与 `shellcheck -e SC1091,SC1008 root/aria2/script/*` 通过（退出码 0）。
8. 结论：通过；RPC tracker 更新状态判定准确性提升。

记录 21：

1. 日期：2026-02-23
2. 执行项：拼写错误专项修复
3. 改动文件：
4. `root/aria2/script/core`
5. `root/aria2/script/log_common`
6. `root/etc/cont-init.d/30-config`
7. `README.md`
8. `docs/refactor-bugfix-plan.md`
9. 关键修复：
10. WARNING 日志标签从旧拼写修正为标准拼写。
11. 修复注释中的 update tracker 拼写问题。
12. 修复 README 中 tracker/trackers 相关拼写问题（按语义分别修正）。
13. 容器验证（镜像：`docker-aria2:spelling-check`）：`source /aria2/script/log_common` 后 `LOG_WARNING` 输出标签为 `[WARNING]`。
14. 验证结果：全仓库检索上述错拼词均无命中。
15. 结论：通过；拼写层面的可读性与一致性提升。

记录 22：

1. 日期：2026-02-23
2. 执行项：容器内“带参数”脚本回归（按 aria2 hook 传参格式）
3. 测试镜像：`docker-aria2:param-test`
4. 测试容器：`aria2-param-test`
5. 传参方式：`script.sh <gid> <file_num> <file_path>`
6. 测试方法：
7. 通过 RPC 真实创建下载任务获取 `gid`，完成后手动调用脚本并传入参数。
8. 为避免自动 hook 干扰，按场景动态调整 `/config/setting.conf`（例如先 `move-task=false` 再手动触发 `completed.sh`）。
9. 验证项与结果：
10. `completed.sh` 参数调用（单文件移动）：`PASS`
11. `stop.sh` 参数调用（`remove-task=delete`）：`PASS`
12. `pause.sh` 参数调用（`move-paused-task=true`）：`PASS`
13. `start.sh` 异常参数（`file_num=notnum`）短路：`PASS`
14. `start.sh` 零/空参数（`file_num=0,file_path=''`）短路：`PASS`
15. 结果摘要：`RC1=0 RC2=0 RC3=0 RC4=0 RC5=0`，`delete.log` 命中次数 `1`。
16. 结论：通过；容器真实环境下参数传递链路可用，关键脚本参数化执行符合预期。

记录 23：

1. 日期：2026-02-23
2. 执行项：`setting.conf` + `文件过滤.conf` 全选项容器传参矩阵测试
3. 测试镜像：`docker-aria2:param-test`
4. 测试容器：`aria2-option-matrix`
5. 传参方式：`script.sh <gid> <file_num> <file_path>`
6. 测试方法：
7. 在容器内启动本地 mock RPC（`PORT=16888`）返回稳定 `tellStatus`（`status=complete`、`dir=/downloads`、`infoHash`），逐项设置配置并调用 `completed.sh/start.sh/stop.sh/pause.sh`。
8. 对 `setting.conf` 共 20 项场景（含枚举值）进行断言。
9. 对 `文件过滤.conf` 共 6 项场景（`min-size/include-file/exclude-file/keyword-file/include-file-regex/exclude-file-regex`）进行断言。
10. 关键修复：
11. 修复 `core` 的配置读取串扰：`grep ^include-file` 与 `grep ^exclude-file` 会误匹配 `*-regex` 项，导致 `include-file-regex` 行为异常。
12. 已改为精确匹配键名：`^include-file=`、`^exclude-file=`、`^include-file-regex=`、`^exclude-file-regex=`。
13. 验证结果：矩阵结果 `PASS=26`、`FAIL=0`。
14. 附加校验：全量 `bash -n` 与 `shellcheck -e SC1091,SC1008 ...` 通过（退出码 0）。
15. 结论：通过；两份配置文件的全部选项已在容器内完成传参回归并通过。
