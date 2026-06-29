---
name: refactor-guide
description: docker-aria2 项目的修改操作手册。当用户需要修改 root/、Dockerfile、CI workflow、测试脚本，或评审/讨论项目设计时调用。提供代码风格正反例、改哪个文件加哪类测试的映射、绝不能动的设计契约、反模式查表。项目架构、上游依赖、配置语义、环境变量等契约见 CLAUDE.md（always-on 加载），本 skill 不重复，只补充操作层与评审层细节。
disable-model-invocation: false
---

# docker-aria2 修改操作手册

本 skill 是 CLAUDE.md 的操作层补充，不重复 CLAUDE.md 已覆盖的架构、上游依赖、配置语义、环境变量、关键命令。使用前默认 CLAUDE.md 已在上下文中。

分工：

- **CLAUDE.md**：项目是什么、契约是什么、不能动什么、修改前 checklist（always-on）
- **本 skill**：怎么改、怎么写代码、改哪加哪类测试、评审反模式查表、建议输出格式（按需调用）

## 1. 修改前先定位

收到改动需求时，先判断属于哪类，再决定读哪些现状：

| 改动类型 | 先读 | 配套测试 |
|----------|------|----------|
| `lib/*.sh` 函数行为 | 目标 lib + 调用方 hook | lib-test 用例（§5.2） |
| cont-init.d 启动流程 | 目标 init 脚本 + 受影响的 conf | RPC 集成测试（§5.3） |
| services.d 服务 | `aria2/run` 或 `aria2b/run` | 手动 smoke-test |
| Dockerfile / 构建 | Dockerfile + `build.sh` + CI matrix | CI 全量 build |
| aria2.conf 重写规则 | `30-config` + `aria2.conf.default` | conf 断言（§5.3） |
| tracker / CTU | `lib/tracker.sh` | tracker 用例（§5.2） |

读现状的标准动作：

```bash
grep -rn <pattern> root/          # 找所有相关位置
git show origin/aria2b:root/aria2/script/<file>  # 看重构前老版怎么做的（仅历史参考）
```

## 2. 代码风格（正反例）

### 2.1 注释一律中文，写"为什么"不写"做什么"

```bash
# ✓ 写为什么
# RPC 返回 .result 才算真成功；.error 字段是 aria2 拒绝（如 secret 错）
[ -n "$(echo "${result}" | jq -r '.result // empty')" ]

# ✗ 写做什么（代码本身就说了）
# 检查 result 是否非空
[ -n "$(echo "${result}" | jq -r '.result // empty')" ]

# ✗ 用英文注释
# Check result is non-empty
```

### 2.2 库函数不 exit，顶层脚本可以 exit

- **库函数**（`lib/*.sh`）：return 非零，错误写 stderr，**绝不 exit**
- **顶层脚本**（事件钩子、cont-init、`tracker.sh` main）：可以 exit
- 例外：`lib/event.sh#INIT_EVENT` 里 `GET_RPC_INFO || exit 1` —— 它本质是顶层初始化的延伸

### 2.3 JSON 构造一律 jq -nc（防注入）

```bash
# ✓ 正确
payload=$(jq -nc --arg secret "${SECRET}" --arg gid "${TASK_GID}" \
    '{jsonrpc:"2.0",method:"aria2.tellStatus",id:"NG6",
      params:(if $secret == "" then [$gid] else ["token:" + $secret, $gid] end)}')

# ✗ 错误：SECRET 含 " \ 换行会破坏 JSON（注入向量）
payload='{"jsonrpc":"2.0","method":"aria2.tellStatus","params":["token:'${SECRET}'","'${TASK_GID}'"]}'
```

大 payload（含 base64 torrent）参数走 stdin 给 jq，不要走 argv，否则触发 Linux `MAX_ARG_STRLEN` (128KB)：

```bash
printf '%s' "$params" | jq -nc --arg m "$method" 'input as $p | {..., params: ([token] + $p)}'
```

> `rpc-integration-test.sh` 的 `rpc()` helper 已用此模式绕过 128KB 限制，不要重构回 `--argjson`。

### 2.4 sed 必须锚定 + 转义元字符

```bash
# ✓ 锚定行首，只改值不动 key，不误匹配注释
sed -i "s|^\(${key}=\).*|\1${escaped}|" "${conf}"

# ✗ 通配匹配会改注释行
sed -i "s|.*${key}.*|${key}=${value}|" "${conf}"

# replacement 中的 \ & 分隔符必须转义
escaped=$(printf '%s' "${value}" | sed -e 's/[\&|]/\\&/g')
```

### 2.5 grep 必须用 ^key= 精确锚定（防前缀污染）

```bash
# ✓ 用 = 作精确边界
grep -q "^bt-tracker=" "${conf}"
INCLUDE_FILE="$(grep '^include-file=' "${FILTER_CONF}" | cut -d= -f2-)"

# ✗ 只锚 ^key 会误匹配前缀同名的 key
grep '^include-file'   # 会同时命中 include-file-regex= 行
grep "bt-tracker="     # 会匹配 #bt-tracker= 注释行
```

**前缀污染陷阱**（2026-06 修复的 filter.sh bug）：`include-file` 是 `include-file-regex` 的前缀，`grep ^include-file` 会把 regex 行的值也吞进 `INCLUDE_FILE`，中间夹换行，拼进 `find -iregex` 后正则破碎、过滤静默失效。凡是配置文件里存在 `X` 与 `X-regex`（或 `X-xxx`）这类前缀同名 key，grep 必须用 `^X=` 精确锚定。

### 2.6 curl timeout 按信任边界，不是所有 curl 都加

```bash
# ✓ 跨外部边界：必须加 timeout
curl -fsS --max-time 15 --connect-timeout 5 "${url}"   # tracker 源 / CTU / GitHub / CDN

# ✓ 容器内部 localhost：保持简单，不加
curl "${RPC_ADDRESS}" -fsSd "${payload}"               # lib/rpc.sh 调 localhost:${PORT}/jsonrpc
```

**规则**（与 CLAUDE.md 信任边界对齐）：

- 外部网络（tracker 列表、GitHub/CDN、用户 CTU、cron 外部刷新、构建期远程下载）→ 必须 `--connect-timeout` + `--max-time`
- 容器内部（`lib/rpc.sh` 调 localhost RPC、aria2b poll 同容器 aria2c、AriaNg 访问本地 WebUI）→ 不加，机械加 timeout 会让简单同步契约更难推理且引入新失败语义

> 老版本 skill 写的"所有 curl 必须有超时"已废弃，以本节为准。

### 2.7 变量必须引号

```bash
# ✓
mv -f "${SOURCE_PATH}" "${TARGET_PATH}"

# ✗ 路径含空格会破
mv -f ${SOURCE_PATH} ${TARGET_PATH}
```

### 2.8 多参数用 bash array

```bash
# ✓
ARGS=(s6-setuidgid abc aria2c --conf-path=/config/aria2.conf)
[ -n "$SECRET" ] && ARGS+=(--rpc-secret="$SECRET")
exec "${ARGS[@]}"

# ✗ 变量未引号会被词法分割（SECRET 含空格就炸）
SECRET_TOKEN="--rpc-secret=${SECRET}"
exec aria2c --conf=... $SECRET_TOKEN
```

## 3. 代码品味准则

§2 是"不出错"的语法底线，本节是"有品味"的判断准则。品味 ≠ 过度抽象，与项目"用简单方法完成简单任务"一致：只在该抽象处抽象，只在该降级处降级。每条都配项目里真实存在的好代码作正面范例，模仿这些范例而非套用口号。

### 3.1 数据驱动优先于控制流堆叠

用数组/表驱动配置项，避免 if/elif 链硬编码 key。新增配置只改数据结构，不动控制流。

```bash
# ✓ CONFIG_ITEMS 一个数组同时驱动 LOAD_CONF 和 SED_CONF（lib/config.sh）
declare -a CONFIG_ITEMS=(
    "remove-task:RMTASK:rmaria"
    "move-task:MOVE:false"
    ...
)
# 新增配置项只在数组追加一行，LOAD_CONF/SED_CONF 自动处理

# ✗ 老 setting#SED_CONF 用 elif 链逐个 key 判空填默认，只有第一个空 key 命中
```

### 3.2 抽 helper 消除同构重复（YAGNI 红线：重复 ≥3 次或逻辑同构才抽）

```bash
# ✓ 6 个 find|rm|tee 管道同构，抽成 _filter_rule（lib/filter.sh）
_filter_rule() {
    find "${SOURCE_PATH}" -type f "$@" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
}
DELETE_EXCLUDE_FILE() {
    [ -n "${MIN_SIZE}" ] && _filter_rule -size "-${MIN_SIZE}"
    [ -n "${EXCLUDE_FILE}" ] && _filter_rule -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})"
    ...
}

# ✓ 多字段提取同构，抽 _jq_field（lib/rpc.sh）
GET_DOWNLOAD_DIR() { DOWNLOAD_DIR=$(_jq_field dir); }
GET_TASK_STATUS()  { TASK_STATUS=$(_jq_field status); }

# ✗ 只用一次的逻辑硬造 helper / 为未来"可能"的扩展造框架
```

### 3.3 命名约定一致，按用途命名

- 谓词函数（返回布尔语义）：`IS_`/`HAS_` 前缀 → `IS_TASK_SOURCE_PATH`
- 私有 helper：`_` 开头 → `_jq_field`、`_CHECK_SPACE`、`_filter_rule`、`_MOVE_TO_FAILED`
- 全局变量：全大写 → `SETTING_CONF`、`INCLUDE_FILE`、`RPC_RESULT`
- 配置路径全局：加 `_CONF` 后缀，**按用途命名不按脚本名** → `SETTING_CONF`（不叫 `SCRIPT_CONF`，避免库间命名空间冲突）
- 新增全局前先查冲突：`grep -r '<NAME>' root/aria2/scripts/lib/`

### 3.4 给魔法值赋予语义

颜色码、返回码这类裸值必须集中定义并注释规约，调用方按语义分支而非按数字。

```bash
# ✓ 颜色规约集中注释（lib/files.sh 头部）
# 绿色 LIGHT_GREEN：正常路径（SOURCE_PATH / TARGET_PATH / 数值）
# 黄色 YELLOW：警示路径（move-failed 退路目录、未知值）
# 紫色 LIGHT_PURPLE：种子相关（与 TASK_INFO 紫色字段一致）

# ✓ 返回码三态语义化（lib/rpc.sh#GET_INFO_HASH）
#   0 - BT 任务且 infoHash 有效
#   1 - 非 BT 任务（HTTP/FTP），infoHash=null（正常路径）
#   2 - 解析失败（致命错误）
GET_INFO_HASH() {
    ...
    [ "${INFO_HASH}" = "null" ] && return 1
    ...
}
GET_RPC_INFO() {
    GET_INFO_HASH
    [ $? -eq 2 ] && return 1   # 按语义分支，不按数字猜
}
```

### 3.5 关注点分离

| 分离维度 | 一侧 | 另一侧 |
|----------|------|--------|
| 输出通道 | `echo` 带色 → docker logs（面向人实时看） | `log_line` 无 ANSI → /config/logs（面向持久化排查） |
| 失败处理 | 库函数 `return` 非零（决策权交调用方） | 顶层脚本 `exit`（执行中止） |
| 路径安全 | `IS_TASK_SOURCE_PATH` 守卫（判越界） | `REMOVE_SOURCE_PATH`/`MOVE_SOURCE_PATH`（执行 rm/mv） |
| 配置读写 | `LOAD_CONF`（读入全局） | `SED_CONF`（写回模板） |

### 3.6 优雅降级链：失败不裸奔，按代价升序回退

```bash
# ✓ MOVE_FILE 三级回退（lib/files.sh）
# 1. 跨盘空间不足 → 移到 /downloads/move-failed（保留文件）
# 2. 主路径 mv 失败 → 移到 move-failed
# 3. MOVE_RECYCLE 移回收站失败 → 降级为删除（避免滞留下载目录）
# 每级都 echo + log_line，失败可见
```

降级原则：先尝试代价更小、可逆性更强的回退；每级都要有日志，不能静默吞掉失败。

### 3.7 错误信息面向人

错误输出要让用户看 docker logs / log 文件就能定位，四要素：时间戳 + 上下文 + 严重度颜色 + 可读消息。

```bash
# ✓
echo -e "$(DATE_TIME) ${ERROR} 目标磁盘空间不足！需 ${LIGHT_GREEN_FONT_PREFIX}${required_gb}${FONT_COLOR_SUFFIX} GB，可用 ${LIGHT_GREEN_FONT_PREFIX}${available_gb}${FONT_COLOR_SUFFIX} GB" >&2
log_line "${MOVE_LOG}" ERROR "目标磁盘空间不足。需:${required_gb}G 可用:${available_gb}G 源:${src} -> 目标:${dst}"

# ✗ 裸报错，无时间无上下文
echo "error" >&2
```

### 3.8 注释写"为什么"，且只在非显而易见处写

注释解释决策、约束、业务语义——这些代码本身说不清。显而易见的赋值/流程不注释，也是品味（冗余注释 = 噪音）。

```bash
# ✓ 解释业务约束（lib/event.sh#GET_FINAL_PATH）
# 单文件 HTTP/FTP 任务 → SOURCE_PATH = 文件本身（只移文件）
#   语义：HTTP 单文件没有"自带文件夹"概念，--out=sub/foo.mp4 中的 sub 是用户分类目录
#         可能被多个任务共享；只移文件可避免误整窝端走未完成的兄弟任务

# ✗ 复述代码（废话注释）
SOURCE_PATH="${FILE_PATH}"   # 设置 SOURCE_PATH 为 FILE_PATH
```

**品味总纲**：同构逻辑不重复 + 魔法值有语义 + 失败有降级 + 信息面向人 + 注释说为什么。不等于过度抽象——只用一次的逻辑直接写，别造框架。

## 4. 绝不能动的设计（动了一定会出 bug）

| 设计 | 位置 | 原因 |
|------|------|------|
| `_LIB=$(dirname "${BASH_SOURCE[0]}")` | `lib/event.sh` | 必须用 `BASH_SOURCE[0]` 不是 `$0`，因为这文件总是被 source |
| `setting.conf` 不接受 env var seed | `20-config` / `lib/config.sh` | setting.conf 是行为配置唯一接口；半生效的一次性 env seed 会误导用户 |
| `MOVE_FILE &` 后台化 | `completed.sh` | 大文件跨盘 cp 阻塞 aria2c hook fork；后台化释放 aria2c，s6/PID-1 收尸孤儿 |
| `tracker.sh` source guard | `lib/tracker.sh` 末尾 | 让测试能 source-and-call 内部函数而不触发 main |
| `aria2b/run` poll RPC 替代 sleep | `services.d/aria2b/run` | 固定 sleep 10 在慢启动时抢跑 |
| `cron-restart-a2b` 用 `pkill -x` | `40-config` 内嵌 | 精确匹配，不误杀 aria2b-helper 之类 |
| `crond` 总是启动 | `30-config` | RUT=false 时 aria2b 重启 cron 和 Alpine periodic 都靠它 |
| `INIT_EVENT` 调用顺序 | `lib/event.sh` | path 函数必须在 RPC 之前，否则 GET_FINAL_PATH 用错 TARGET_DIR |
| cron 路径不统一 | `30-config` vs `40-config` | `/etc/crontabs/root` 与 `crontab -l`/`-` 在本镜像共存，不要强行统一 |
| 不做 aria2.conf ensure-key 兜底 | `30-config` | 9 个覆盖 key 在模板里都有；用户删 key 属于自找，sed no-op 可接受 |
| tracker RPC 成功判定用 `jq -e '.result == "OK"'` | `lib/tracker.sh#_update_rpc` | 错误响应里可能含 "OK" 字符串，`grep -q OK` 会被骗 |
| 架构检测用 `uname -m` | Dockerfile builder | buildx+QEMU 让 builder 作为目标架构运行，`uname` 可靠，不要改 `ARG TARGETARCH` |
| buildx 缓存禁用 | CI | Dockerfile 拉 latest release，GHA 缓存会冻结版本在陈旧层 |

## 5. 测试范式

### 5.1 改前本地预检

```bash
bash -n root/aria2/scripts/lib/*.sh
bash -n root/etc/cont-init.d/*-* root/etc/services.d/*/run
bash -n .github/scripts/*.sh
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/Build Image.yml'))"
shellcheck --severity=warning -x root/aria2/scripts/lib/*.sh root/aria2/scripts/*.sh root/etc/cont-init.d/*-* root/etc/services.d/*/run .github/scripts/*.sh build.sh
```

### 5.2 改 lib 必加 lib-test 用例

位置：`.github/scripts/in-container-lib-test.sh`（容器内运行，50 用例，有意不开 `set -u`）

改哪个 lib 加哪类用例：

| 改的 lib | 加的用例 |
|----------|----------|
| `lib/files.sh#MOVE_FILE` | `t_move_<scenario>`（设 FILE_PATH 让 TASK_INFO 横幅非空） |
| `lib/filter.sh` | `t_filter_<rule>` |
| `lib/torrent.sh` | `t_torrent_<mode>` |
| `lib/config.sh` | `t_sedconf_*` |
| `lib/tracker.sh` | `t_tracker_*` |

约定：

- 每个测试函数后清理副作用（恢复 setting.conf、删测试目录）
- 走真实 `LOAD_FILTER_CONF`/`LOAD_CONF` 的用例要构造临时配置文件，不要只给全局变量赋值（否则覆盖不到配置解析层，前缀污染类 bug 测不出来）
- `rpc-integration-test.sh` 可用 `set -uo pipefail`，lib-test 不要加 `set -u`

### 5.3 改 cont-init / 启动流程加 RPC 集成测试

位置：`.github/scripts/rpc-integration-test.sh`（宿主侧，16 用例）

- 改 `30-config` 写 aria2.conf 的逻辑 → 加 `docker exec` 验证 conf 文件（参考现有 file-allocation/bt-save-metadata/listen-port 断言）
- 改 hook 默认行为 → 加 E2E（提交任务 → 等完成 → 验证副作用，参考现有 MOVE E2E）

### 5.4 CI 顺序保证发布安全

```
build → smoke-test → merge
```

失败时 `:dev-latest` 不更新，用户始终拉到上一次过的版本。smoke-test 只在 amd64 runner 跑，arm 变体靠 build 成功验证。

## 6. 反模式查表（重构历史沉淀，不要在新代码复活）

这些是重构期间修复或后续 review 发现的 bug，评审时按类别排查：

### sed / grep 锚定类
- `30-config` 用 `.*on-download-pause.*` 匹配注释 → 改 `^\(key=\).*`
- `tracker.sh` 用 `[ -z $(grep "bt-tracker=" conf) ]` 无锚定 → 改 `grep -q "^bt-tracker="`
- `filter.sh` 用 `grep ^include-file` 误吞 `include-file-regex` 值 → 改 `^include-file=`（2026-06 修）

### 服务/s6 类
- `aria2b/run` 用 `echo`+退出禁用服务 → s6 狂重启 → 改 `exec s6-svc -d .`
- `aria2/run` `$SECRET_TOKEN` 未引号 → SECRET 含空格被词法分割 → 改 bash array
- `cron-restart-a2b.sh` 用 `ps -ef | grep aria2b | xargs kill -9` → 误杀 aria2b* → 改 `pkill -x aria2b`
- `30-config` 仅 `RUT=true` 时启 crond → aria2b 重启 cron 和 periodic 静默失效 → 改成总启

### JSON / 配置类
- `rpc_info` JSON 字符串拼接 → SECRET 含特殊字符破坏 payload（注入向量）→ 改 `jq -nc --arg`
- `setting#SED_CONF` 用 elif 链填默认 → 只有第一个空 key 命中 → 改 per-key 循环
- `30-config` FA 未设时落 `*) FA_VAL=none` → 覆盖 aria2.conf 默认 falloc → 改回退 falloc
- `tracker._update_rpc` 用 `grep -q OK` → 错误响应含 "OK" 被误判成功 → 改 `jq -e '.result == "OK"'`
- `tracker._update_rpc` curl 无 timeout → 外部网络停滞 cron 堆积 → 加 timeout

### 钩子业务类
- `core#HANDLE_TORRENT rename` 没指定目标目录 → 落到 aria2c cwd → 加 `${DOWNLOAD_DIR}/` 前缀
- `core#HANDLE_TORRENT rename` echo "已删除种子文件" 但实际重命名 → 误导日志 → 改 echo "重命名种子文件"
- `start.sh` RRT 删除前不处理 .torrent → 磁力保存的种子残留可能再触发 → 加 CHECK_TORRENT
- `start.sh` 调 REMOVE_REPEAT_TASK 不检查返回 → 本地删了但 aria2c 继续下载 → 加失败警告
- 拼写 `WARRING` → `WARNING`

## 7. 已知且接受、勿重复提出的设计

以下已评审并接受，评审时不要当 bug 提（与 CLAUDE.md "已知且接受的设计" 对齐）：

- **`11-version` aria2c 版本字符串可能陈旧**：横幅硬编码版本可能与实际二进制漂移，真实版本用 `aria2c --version` 获取。仅展示，不影响控制流，不修。
- **`setting.conf` 不接受 env var**：有意设计，行为配置以 setting.conf 为唯一接口。
- **本地 RPC 不强制 timeout**：localhost RPC 属受控边界，不默认加 timeout/retry。
- **`completed.sh` 后台执行 MOVE_FILE**：大跨盘移动不阻塞 aria2c hook fork，`MOVE_FILE &` 有意设计。失败信息仍经继承的 fd 进 docker logs + 写 move.log，可见性不丢。
- **cron 路径共存**：`/etc/crontabs/root` 与 `crontab -l`/`crontab -` 在本镜像共存，不强行统一。

## 8. 评审/列建议时的输出格式

讨论改动方案时，按此格式逐条列，实施前问用户哪几条要做：

```
**[类别]** 短标题
- 现状：当前代码是什么样
- 问题：具体痛点（性能 / 健壮性 / 可读性 / 安全）
- 建议：最小改动是什么
- 测试影响：要加/改哪些用例（§5.2 / §5.3）
- 风险：none | low | medium（medium 必须解释）
```

## 9. 工作流程

1. **明确范围**：用户要改什么？影响哪些子系统（§1 表）？
2. **读现状**：`grep -rn` 找相关位置；`git show aria2b:<file>` 看老版（仅历史参考）
3. **查规范**：§2 代码风格；§3 品味准则；§4 绝不能动；CLAUDE.md 修改前 checklist
4. **改代码**：单一职责，中文注释解释为什么
5. **加测试**：§5 范式；覆盖正常路径 + 边界 + 失败回退
6. **本地预检**：§5.1 命令
7. **提交触发**：`gh workflow run "Build Image.yml" --ref <branch>`，监控到全绿
8. **失败时**：`gh run view <id> --log-failed` 看具体哪步、哪个用例
