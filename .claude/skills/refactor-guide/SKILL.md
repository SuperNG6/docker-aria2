---
name: refactor-guide
description: docker-aria2 项目的重构、修改、新增功能指南。当用户需要修改 root/、Dockerfile、CI workflow、测试脚本，或者讨论项目设计时调用。包含项目架构、上游依赖、配置语义、代码规范、已知陷阱清单。
disable-model-invocation: false
---

# docker-aria2 项目重构与维护指南

## 1. 项目目标与价值主张

docker-aria2 是 [SuperNG6/docker-aria2](https://github.com/SuperNG6/docker-aria2) 的 Alpine 镜像，把 aria2c + AriaNg WebUI 打包成 Docker 容器。核心价值：

- **开箱即用**：默认配置可直接 `docker run`，无需写 aria2.conf
- **任务自动整理**：下载完成后自动移动到 `/downloads/completed/`、回收站、过滤无用文件、备份种子文件
- **可选 BT 优化**（a2b variant）：屏蔽迅雷/影音先锋等吸血客户端（依赖 aria2b 项目）
- **多架构**：linux/amd64 + linux/arm64 + linux/arm/v7
- **持久化配置**：所有设置在 `/config/setting.conf`，编辑即时生效，无需重启

## 2. 上游依赖（修改 Dockerfile 前必读）

镜像由 4 个上游项目组合：

| 组件 | 仓库 | 引入方式 | 特殊要求 |
|------|------|----------|----------|
| **基础镜像** | [SuperNG6/docker-baseimage-alpine](https://github.com/SuperNG6/docker-baseimage-alpine) | `FROM superng6/alpine:3.23` | 已含 abc 用户(UID 911) / with-contenv / s6-overlay v2.2.0.3 / coreutils / patched init-stage2，**不要重装**这些 |
| **aria2c 二进制** | [SuperNG6/Aria2-Pro-Core](https://github.com/SuperNG6/Aria2-Pro-Core) | builder 阶段 wget release tarball | 资产名 `aria2-static-linux-${ARCH}.tar.gz`（ARCH: x86_64 / arm64 / armhf / i386），用 `uname -m` 检测 |
| **AriaNg WebUI** | [mayswind/AriaNg](https://github.com/mayswind/AriaNg) | builder 阶段拉 latest AllInOne.zip | 解压到 `/tmp/index.html`，运行时 darkhttpd 服务 |
| **aria2b** （仅 a2b variant） | [SuperNG6/aria2b](https://github.com/SuperNG6/aria2b) | runtime 阶段 curl latest release 单文件 | **必须 >= v2.1.0**（v2.0.0 有 unref bug 导致 10s 重启循环）；需要 NET_ADMIN + nodejs + iptables + ipset |

### 上游升级路线
- aria2c：访问 [SuperNG6/Aria2-Pro-Core/releases](https://github.com/SuperNG6/Aria2-Pro-Core/releases)，Dockerfile 用 `releases/latest` API 自动拉
- aria2b：访问 [SuperNG6/aria2b/releases](https://github.com/SuperNG6/aria2b/releases)，Dockerfile 用 `/tags` API 第一个
- AriaNg：访问 [mayswind/AriaNg/tags](https://github.com/mayswind/AriaNg/tags)，Dockerfile 用 `/tags` API 第一个
- base image：手动 bump `FROM superng6/alpine:<version>`

**CI 关闭了 buildx cache**（项目轻量，缓存会让用户拿到旧版上游）。不要重新开启。

## 3. 重构前的老设计（dev-refactor-20260521 之前的 aria2b 分支）

老 `aria2b` 分支是单 monolithic 风格（[git show aria2b:root/aria2/script/](https://github.com/SuperNG6/docker-aria2/tree/aria2b/root/aria2/script)）：

```
root/aria2/script/            # 老分支里目录名就是 script（无 s），当前分支已重命名为 scripts
├── core              # 颜色 + log + path + file 全在一个文件
├── setting           # LOAD_CONF + SED_CONF
├── rpc_info          # RPC payload 字符串拼接（JSON 注入漏洞）
├── tracker.sh        # file 模式
├── rpc_tracker.sh    # rpc 模式
├── cron-restart-a2b.sh  # 独立 cron 脚本
└── start.sh / stop.sh / completed.sh / pause.sh
```

重构成现在的 `lib/{log,event,files,filter,torrent,rpc,config,tracker}.sh` 模块化结构。

**重构期间默修的 11 个老 bug**（不要在新代码里复活这些反模式）：
1. `core#HANDLE_TORRENT rename` 没指定目标目录 → 改用 `${DOWNLOAD_DIR}/` 前缀
2. `setting#SED_CONF` 用 elif 链填默认值 → 只有第一个空 key 命中 → 改用 per-key 循环
3. `aria2b/run` 用 `echo`+ 退出禁用服务 → s6 看到退出狂重启 → 改用 `exec s6-svc -d .`
4. `aria2/run` `$SECRET_TOKEN` 未引号 → SECRET 含空格被词法分割 → 改用 bash array
5. `rpc_info` JSON 用 `"params":["token:'${SECRET}'"]` 字符串拼接 → 改用 `jq -nc --arg`
6. `cron-restart-a2b.sh` 用 `ps -ef | grep aria2b | xargs kill -9` → 改用 `pkill -x aria2b`
7. `30-config` sed 用 `.*on-download-pause.*` 匹配注释 → 改用 `^\(key=\).*` 锚定
8. `30-config` 仅 `RUT=true` 时启 crond → aria2b 重启 cron 和 periodic 静默 → 改成总是启 crond
9. `tracker.sh` 检查 `[ -z $(grep "bt-tracker=" conf) ]` 无锚定匹配注释 → 改用 `grep -q "^bt-tracker="`
10. `start.sh` RRT 删除前不处理 .torrent → 磁力保存的种子留在 /downloads/ 可能再次触发 → 加 CHECK_TORRENT
11. 拼写 `WARRING` → `WARNING`

**重构后又发现并修的 6 个老 bug**（review 时格外注意这些类别）：
- B1：FA 未设时 30-config 把 file-allocation 改成 none（应回退 falloc）
- B2：tracker._update_rpc 用 `grep -q OK` 被错误响应中的 "OK" 字样欺骗
- B3：tracker._update_rpc curl 无 timeout
- F1：MOVE/RMTASK/CF/DET/TOR/RRT/MPT env var 之前完全是死参数
- F2：SECRET=yourtoken 默认值是公开 token
- F6：darkhttpd 启动失败无日志

> 注意：曾经提出的 "F5 缺 key 兜底" 已撤销 —— aria2.conf 是项目模板（aria2.conf.default），30-config 覆盖的 9 个 key 在模板里都有，用户手动删 key 属于折腾自己，不做兜底。下次 review 不要重新引入这个"防御"。

## 4. 当前架构（修改前必须理解）

### 4.1 cont-init.d 启动序列
```
11-version      # 版本横幅 + SECRET=yourtoken 警告
20-config       # 创建目录、复制默认 conf、env var 种子值（首次）/合并升级（已有）
30-config       # aria2.conf 写 hook 路径 + 端口 + SMD/FA；启 crond；UT=true 时拉 tracker
40-config       # chown abc:abc，chmod +x，a2b variant 注册 aria2b 重启 cron
50-config       # WEBUI=true 时启 darkhttpd（失败时打错误）
90-custom-folders / 99-custom-scripts  # 用户钩子（项目内是空文件）
```

### 4.2 services.d
- `aria2/run`：`s6-setuidgid abc aria2c --conf=...`（QUIET=true 默认屏蔽 stderr，调试需 QUIET=false）
- `aria2b/run`：A2B!=true 时 `exec s6-svc -d .` 禁用；A2B=true 时 poll RPC 就绪后 exec aria2b

### 4.3 事件钩子契约
所有钩子（start.sh / completed.sh / stop.sh / pause.sh）通用模式：
```bash
. "$(dirname "$0")/lib/event.sh"  # 自动 source 所有 lib + LOAD_CONF
INIT_EVENT <completed|recycle> "$@"   # 顺序：GET_BASE_PATH → COMPLETED/RECYCLE_PATH → GET_RPC_INFO → GET_FINAL_PATH
GUARD_EVENT                            # 磁力链/无效任务跳过；路径错误退出
# 业务逻辑
```

**INIT_EVENT 内部顺序不能打乱**：路径目录(TARGET_DIR)必须在 GET_RPC_INFO 之前设好，因为 GET_FINAL_PATH 同时依赖 TARGET_DIR 和 RPC 返回的 DOWNLOAD_DIR。

### 4.4 配置语义三层
- **aria2.conf**：30-config 每次启动覆盖 9 个 key（hook/PORT/BTPORT/SMD/FA），其他用户编辑保留
- **setting.conf**：首次启动 cp 模板 + env var 种子；之后只读，用户编辑即时生效
- **文件过滤.conf**：首次 cp，不动

## 5. 代码风格规范

### 5.1 注释一律中文
```bash
# ✓ 正确
# 删除任务前先备份种子文件，避免 RRT 触发后磁力链元数据丢失
CHECK_TORRENT
rm -rf "${SOURCE_PATH}"

# ✗ 错误（不要用英文注释）
# Backup torrent before delete
```

中文注释要写**为什么**而不是**做什么**。比如：
```bash
# ✓ 写"为什么"
# RPC 返回 .result 才算真成功；.error 字段是 aria2 拒绝（如 secret 错）
[ -n "$(echo "${result}" | jq -r '.result // empty')" ]

# ✗ 写"做什么"（代码本身就说了）
# 检查 result 是否非空
[ -n "$(echo "${result}" | jq -r '.result // empty')" ]
```

### 5.2 库函数 vs 顶层脚本
- **库函数**（`lib/*.sh`）：return 非零，把错误写 stderr，**绝不 exit**
- **顶层脚本**（事件钩子、cont-init、tracker.sh main）：可以 exit
- 例外：`lib/event.sh#INIT_EVENT` 里 `GET_RPC_INFO || exit 1` —— 因为它本质是顶层初始化的延伸

### 5.3 JSON 构造一律 jq -nc
```bash
# ✓ 正确（防注入）
payload=$(jq -nc --arg secret "${SECRET}" --arg gid "${TASK_GID}" \
    '{jsonrpc:"2.0",method:"aria2.tellStatus",id:"NG6",
      params:(if $secret == "" then [$gid] else ["token:" + $secret, $gid] end)}')

# ✗ 错误（SECRET 含 " \ 会破坏 JSON）
payload='{"jsonrpc":"2.0","method":"aria2.tellStatus","params":["token:'${SECRET}'","'${TASK_GID}'"]}'
```

**大 payload（含 base64 torrent 等）特殊处理**：参数走 stdin 给 jq，不要走 argv，否则触发 Linux `MAX_ARG_STRLEN` (128KB)：
```bash
printf '%s' "$params" | jq -nc --arg m "$method" 'input as $p | {..., params: ([token] + $p)}'
```

### 5.4 sed 必须锚定 + 转义元字符
```bash
# ✓ 正确：锚定行首避免误匹配注释
sed -i "s|^\(${key}=\).*|\1${escaped}|" "${conf}"

# ✗ 错误：通配匹配会改注释行
sed -i "s|.*${key}.*|${key}=${value}|" "${conf}"

# 转义 sed replacement 中的 \ & 分隔符
escaped=$(printf '%s' "${value}" | sed -e 's/[\&|]/\\&/g')
```

### 5.5 grep 必须锚定
```bash
# ✓ 正确
grep -q "^bt-tracker=" "${conf}"

# ✗ 错误：会匹配 #bt-tracker= 注释行
grep -q "bt-tracker=" "${conf}"
```

### 5.6 所有 curl 必须有超时
```bash
# ✓ 正确
curl -fsS --max-time 15 --connect-timeout 5 "${url}"

# ✗ 错误：网络挂掉会导致 cron 任务无限阻塞
curl -fsS "${url}"
```

### 5.7 变量必须引号
```bash
# ✓ 正确
mv -f "${SOURCE_PATH}" "${TARGET_PATH}"

# ✗ 错误：路径含空格会破
mv -f ${SOURCE_PATH} ${TARGET_PATH}
```

### 5.8 多参数用 bash array
```bash
# ✓ 正确
ARGS=(s6-setuidgid abc aria2c --conf-path=/config/aria2.conf)
[ -n "$SECRET" ] && ARGS+=(--rpc-secret="$SECRET")
exec "${ARGS[@]}"

# ✗ 错误：变量未引号会被词法分割
SECRET_TOKEN="--rpc-secret=${SECRET}"
exec aria2c --conf=... $SECRET_TOKEN
```

## 6. 测试范式

任何改动必须：

### 6.1 改前：本地预检
```bash
bash -n root/aria2/scripts/lib/*.sh
bash -n root/etc/cont-init.d/*-* root/etc/services.d/*/run
bash -n .github/scripts/*.sh
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/Build Image.yml'))"
```

### 6.2 改 lib 必加 lib-test 用例
位置：`.github/scripts/in-container-lib-test.sh`
- 改 `lib/files.sh#MOVE_FILE` → 加 `t_move_<scenario>`
- 改 `lib/filter.sh` → 加 `t_filter_<rule>`
- 改 `lib/torrent.sh` → 加 `t_torrent_<mode>`
- 改 `lib/config.sh` → 加 `t_sedconf_*` 或 `t_seed_env_*`
- 改 `lib/tracker.sh` → 加 `t_tracker_*`

### 6.3 改 cont-init / 启动流程加 RPC 集成测试
位置：`.github/scripts/rpc-integration-test.sh`
- 改 30-config 写 aria2.conf 的逻辑 → 加 docker exec 验证 conf 文件
- 改 hook 默认行为 → 加 E2E（提交任务 → 等完成 → 验证副作用）

### 6.4 测试脚本本身的约定
- `in-container-lib-test.sh` **不开 `set -u`**（log.sh#TASK_INFO 等引用隐式变量，不实际）
- `rpc-integration-test.sh` 用 `set -uo pipefail` 可以
- 每个测试函数后清理副作用（恢复 setting.conf、删测试目录）

### 6.5 CI 顺序保证发布安全
build → smoke-test → merge。失败时 `:dev-latest` 不更新，用户始终拉到上一次过的版本。

## 7. 绝不能动的设计（动了一定会出 bug）

| 设计 | 文件:行 | 原因 |
|------|---------|------|
| `_LIB=$(dirname "${BASH_SOURCE[0]}")` | `lib/event.sh:5` | 必须用 `BASH_SOURCE[0]` 不是 `$0`，因为这文件总是被 source |
| `_ENV_SEED_SNAPSHOT` 在 `LOAD_CONF` 之前 | `lib/config.sh` | `declare -g VAR=val` 对已 export 的同名变量会修改 env var 值，snapshot 必须先拍 |
| `MOVE_FILE &` 后台化 | `completed.sh` | 大文件跨盘 cp 阻塞 aria2c hook fork，s6/PID-1 收尸孤儿 |
| `tracker.sh` source guard | `lib/tracker.sh` 末尾 | 让测试能 source-and-call 内部函数而不触发 main |
| `aria2b/run` poll RPC 替代 sleep | `services.d/aria2b/run` | sleep 10 在慢启动时抢跑 |
| `cron-restart-a2b` 用 `pkill -x` | `40-config` 内嵌 | 精确匹配，不误杀 aria2b-helper 之类 |
| `crond` 总是启动 | `30-config` | RUT=false 时 aria2b 重启 cron 和 Alpine periodic 都靠它 |
| `INIT_EVENT` 调用顺序 | `lib/event.sh` | path 函数必须在 RPC 之前，否则 GET_FINAL_PATH 用错 TARGET_DIR |

## 8. 工作流程

收到改动需求时：

1. **明确范围**：用户要改什么？影响哪些子系统（移动/过滤/钩子/启动/CI）？
2. **读现状**：`grep -rn <pattern> root/` 找所有相关位置；`git show aria2b:<file>` 看老版怎么做的
3. **查规范**：本 SKILL 第 5 节代码风格；CLAUDE.md 配置语义
4. **改代码**：单一职责，中文注释解释为什么
5. **加测试**：第 6 节范式；覆盖正常路径 + 边界 + 失败回退
6. **本地预检**：第 6.1 节命令
7. **提交触发**：`gh workflow run "Build Image.yml" --ref <branch>`，监控到全绿
8. **失败时**：`gh run view <id> --log-failed` 看具体哪步、哪个用例

## 9. 列建议时的格式

讨论改动方案时，按这个格式列：

```
**[类别]** 短标题
- 现状：当前代码是什么样
- 问题：具体痛点（性能 / 健壮性 / 可读性 / 安全）
- 建议：最小改动是什么
- 测试影响：要加/改哪些用例
- 风险：none | low | medium（medium 必须解释）
```

实施前问用户哪几条要做。
