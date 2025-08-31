# Docker Aria2 项目完整代码分析

## 项目结构
```
root/
├── aria2/
│   ├── conf/
│   │   ├── 文件过滤.conf
│   │   ├── aria2.conf.default
│   │   ├── rpc-tracker0
│   │   ├── rpc-tracker1
│   │   └── setting.conf
│   └── scripts/
│       ├── handlers/
│       │   ├── on_complete.sh
│       │   ├── on_pause.sh
│       │   ├── on_start.sh
│       │   └── on_stop.sh
│       ├── lib/
│       │   ├── common.sh
│       │   ├── config.sh
│       │   ├── file_ops.sh
│       │   ├── kvconf.sh
│       │   ├── logger.sh
│       │   ├── path.sh
│       │   ├── rpc.sh
│       │   └── torrent.sh
│       └── utils/
│           ├── cron-restart-a2b.sh
│           └── tracker.sh
└── etc/
    ├── cont-init.d/
    │   ├── 11-banner
    │   ├── 20-config
    │   ├── 30-aria2-conf
    │   ├── 40-tracker
    │   ├── 50-darkhttpd
    │   ├── 60-permissions
    │   ├── 99-custom-folders
    │   └── 99-custom-scripts
    └── services.d/
        └── aria2/
            └── run
```

## 完整代码内容

### aria2/scripts/handlers/on_complete.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# 事件处理：on-download-complete（下载完成）
# 职责：
#   - 读取 setting.conf、RPC 任务信息与路径，解析最终位置。
#   - 按 MOVE/CF/DET 等策略执行内容清理与文件移动；
#   - 若为 BT 且保存了 .torrent，按 TOR 策略处理种子文件。
# 输入参数（aria2 传入）：
#   $1=GID  $2=FILE_NUM  $3=FILE_PATH
# 退出码：0 正常；非 0 表示获取路径失败等异常。
set -euo pipefail

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/config.sh
. /aria2/scripts/lib/path.sh
. /aria2/scripts/lib/rpc.sh
. /aria2/scripts/lib/file_ops.sh
. /aria2/scripts/lib/torrent.sh

TASK_GID=${1:-}
FILE_NUM=${2:-0}
FILE_PATH=${3:-}

config_load_setting
rpc_get_parsed_fields "${TASK_GID}" || exit 1
completed_path
get_final_path

# 路径错误防护：无有效文件信息直接返回；解析失败时报错退出
if [[ "${FILE_NUM}" -eq 0 ]] || [[ -z "${FILE_PATH}" ]]; then
	exit 0
elif [[ "${GET_PATH_INFO:-}" = "error" ]]; then
	log_e "GID:${TASK_GID} 获取任务路径失败!"
	exit 1
else
	move_file     # 按 MOVE/CF/DET 等策略执行移动与清理
	check_torrent # 若存在 .torrent 文件则按 TOR 策略处理
fi
```

### aria2/scripts/handlers/on_pause.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154,SC2034
# 事件处理：on-download-pause（下载暂停）
# 职责：当 setting.conf 中启用 move-paused-task（MPT=true）时，模拟“完成”后的处理：
#   - 将当前任务移动到 completed 目录（MOVE 强制设为 true）。
#   - 处理 BT 的 .torrent 文件。
# 输入参数：$1=GID  $2=FILE_NUM  $3=FILE_PATH
set -euo pipefail

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/config.sh
. /aria2/scripts/lib/path.sh
. /aria2/scripts/lib/rpc.sh
. /aria2/scripts/lib/file_ops.sh
. /aria2/scripts/lib/torrent.sh

TASK_GID=${1:-}
FILE_NUM=${2:-0}
FILE_PATH=${3:-}

config_load_setting
rpc_get_parsed_fields "${TASK_GID}" || exit 1
completed_path
get_final_path

if [[ "${MPT}" = "true" ]]; then # 仅在配置开启时生效
	if [[ "${FILE_NUM}" -eq 0 ]] || [[ -z "${FILE_PATH}" ]]; then
		exit 0
	elif [[ "${GET_PATH_INFO:-}" = "error" ]]; then
		log_e "GID:${TASK_GID} 获取任务路径失败!"
		exit 1
	else
		MOVE=true # 强制移动（忽略 dmof 限制）
		move_file
		check_torrent # 根据 TOR 策略处理 .torrent
	fi
fi
```

### aria2/scripts/handlers/on_start.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# 事件处理：on-download-start（下载开始）
# 职责：
#   - 读取 setting.conf 配置与 RPC 任务信息，解析最终路径。
#   - 若启用 remove-repeat-task（RRT=true），当“已存在同名已完成目录”时，将当前重复任务删除并清理已有下载数据。
# 输入参数（aria2 传入）：
#   $1=GID  $2=FILE_NUM  $3=FILE_PATH（开始阶段可能为空）
# 退出码：
#   0 正常；非 0 表示获取路径失败等异常（用于日志定位，aria2 不会中止）。
set -euo pipefail

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/config.sh
. /aria2/scripts/lib/path.sh
. /aria2/scripts/lib/rpc.sh

TASK_GID=${1:-}  # 任务 GID
FILE_NUM=${2:-0} # 文件数量（磁力开始阶段可能为 0）
FILE_PATH=${3:-} # 首个文件路径（开始阶段可能为空）

config_load_setting
rpc_get_parsed_fields "${TASK_GID}" || exit 1
completed_path
get_final_path

# 逻辑：若目标目录已存在同名任务且状态非 error，则移除重复任务并清理现有下载数据
if [[ "${RRT}" = "true" ]]; then
	if [[ "${FILE_NUM}" -eq 0 ]] || [[ -z "${FILE_PATH}" ]]; then
		exit 0
	elif [[ "${GET_PATH_INFO:-}" = "error" ]]; then
		log_e "GID:${TASK_GID} 获取任务路径失败!"
		exit 1
	elif [[ -d "${COMPLETED_DIR:-}" ]] && [[ "${TASK_STATUS}" != "error" ]]; then
		log_w "发现目标文件夹已存在当前任务 ${LOG_GREEN}${COMPLETED_DIR}${LOG_NC}"
		log_w "正在删除该任务，并清除相关文件... ${LOG_GREEN}${SOURCE_PATH}${LOG_NC}"
		# 删除控制文件与源
		[[ -e "${SOURCE_PATH}.aria2" ]] && rm -f "${SOURCE_PATH}.aria2" || true
		rm -rf "${SOURCE_PATH}" || true
		rpc_remove_repeat_task "${TASK_GID}"
		exit 0
	fi
fi
```

### aria2/scripts/handlers/on_stop.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# 事件处理：on-download-stop（下载停止）
# 职责：依据 setting.conf 的 remove-task 选项，对停止的任务执行：
#   - recycle：移动到回收站；
#   - delete：直接删除；
#   - rmaria：仅删除 .aria2 控制文件；
# 并在合适时机处理 .torrent 文件。
# 输入参数：$1=GID  $2=FILE_NUM  $3=FILE_PATH（可能为空）
set -euo pipefail

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/config.sh
. /aria2/scripts/lib/path.sh
. /aria2/scripts/lib/rpc.sh
. /aria2/scripts/lib/file_ops.sh
. /aria2/scripts/lib/torrent.sh

TASK_GID=${1:-}
FILE_NUM=${2:-0}
FILE_PATH=${3:-}

config_load_setting
rpc_get_parsed_fields "${TASK_GID}" || exit 1
recycle_path
get_final_path

stop_handler() {
	# 描述：根据 RMTASK 与 TASK_STATUS 分支执行后处理
	if [[ "${FILE_NUM}" -eq 0 ]] || [[ -z "${FILE_PATH}" ]]; then
		exit 0
	elif [[ "${GET_PATH_INFO:-}" = "error" ]]; then
		log_e "GID:${TASK_GID} 获取任务路径失败!"
		exit 1
	elif [[ "${RMTASK}" = "recycle" ]] && [[ "${TASK_STATUS}" != "error" ]]; then
		move_recycle
		check_torrent
		rm_aria2
		exit 0
	elif [[ "${RMTASK}" = "delete" ]] && [[ "${TASK_STATUS}" != "error" ]]; then
		delete_file
		check_torrent
		rm_aria2
		exit 0
	elif [[ "${RMTASK}" = "rmaria" ]] && [[ "${TASK_STATUS}" != "error" ]]; then
		check_torrent
		rm_aria2
		exit 0
	fi
}

# 若源路径已不存在（可能 start 阶段已清理），则不操作（防止误删）
if [[ -d "${SOURCE_PATH}" ]] || [[ -e "${SOURCE_PATH}" ]]; then
	stop_handler
fi
```

### aria2/scripts/lib/common.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091
# 通用函数库（被 handlers、utils 等多处复用）
# 职责：
#   - 提供统一的工具函数：打印面板、容错执行、KV 配置读写、跨盘空间预检、路径拼接与相对路径计算、调试输出。
#   - 约定输入输出：尽量通过参数传递与标准输出返回结果，必要时读/写全局变量（与其他 lib 协作）。
#   - 一次性加载保护：避免重复 source 带来的函数/变量覆盖与性能浪费。
# 兼容性：仅依赖 BusyBox/Alpine 常见命令（grep/sed/awk/df/du/stat 等），适配容器环境。

# 防止重复加载
if [[ -n "${_ARIA2_LIB_COMMON_SH_LOADED:-}" ]]; then
	return 0
fi
#
# panel
# 描述：打印分割面板与可选内容，用于关键阶段的人类可读输出。
# 参数：
#   $1  标题（必填）
#   $2..N  可选：追加打印的多行内容
# 返回：无（stdout 打印）
_ARIA2_LIB_COMMON_SH_LOADED=1

# 引入统一日志库
. /aria2/scripts/lib/logger.sh

# 打印分割面板
panel() {
	local title="$1"
	shift || true
	#
	# try_run
	# 描述：安全执行命令，发生错误不 exit，中转返回码给调用方自行处理。
	# 参数：
	#   $@  需要执行的命令与参数
	# 返回：命令的实际退出码
	echo -e "==============================================================================="
	echo -e "${title}"
	echo -e "==============================================================================="
	[[ "$#" -gt 0 ]] && echo -e "$*"
}
#
# kv_get
# 描述：从 key=value 结构文件中读取某个键的值（取首个匹配），不处理空格与转义。
# 参数：
#   $1  文件路径（必须存在）
#   $2  键名（不含 =）
# 返回：将值写到 stdout；读取失败返回码非 0

# 安全执行：出错也继续，但返回码可被外层获取
try_run() {
	"$@"
	return $?
}
#
# kv_set
# 描述：在 key=value 结构文件中安全地写入键值。若键存在则替换，不存在则追加。
# 参数：
#   $1  文件路径（不存在将创建）
#   $2  键名
#   $3  值（原样写入，不做转义）
# 返回：0 表示写入成功

# 读文件键值对：key=value（不带空格）
# 入参：$1 配置文件路径；$2 键名
# 返回：将值输出到标准输出
kv_get() {
	# $1: file, $2: key
	[[ -f "$1" ]] || return 1
	grep -E "^$2=" "${1}" | sed -E 's/^([^=]+)=//'
}

# 以 sed 安全替换 key=value（若键不存在则追加）
#
# check_space_before_move
# 描述：在“跨磁盘/分区移动”前进行空间校验；同设备移动则直接放行。
# 参数：
#   $1  源路径（文件或目录）
#   $2  目标目录
# 返回：
#   0 -> 空间充足或同一设备；1 -> 目标空间不足
# 副作用：必要时创建目标目录；通过日志输出提示信息。
# 入参：$1 配置文件路径；$2 键名；$3 值
kv_set() {
	# $1: file, $2: key, $3: value
	local f="$1" k="$2" v="$3"
	touch "${f}"
	if grep -qE "^${k}=" "${f}"; then
		sed -i "s@^\(${k}=\).*@\\1${v}@" "${f}"
	else
		echo "${k}=${v}" >>"${f}"
	fi
}

# 磁盘空间检查（移动前建议调用）
# 功能：当源与目标不在同一文件系统时，预估源大小并检测目标可用空间。
# 入参：$1 源路径（文件或目录）；$2 目标目录。
# 返回：0 表示空间充足或为同分区移动；1 表示目标空间不足。
check_space_before_move() {
	# $1: source_path $2: target_dir
	local sp="$1" td="$2"
	
	# Docker环境下的基础检查：确保源文件和目标目录可访问
	if [[ ! -e "${sp}" ]]; then
		log_e "源文件不存在: ${sp}"
		return 1
	fi
	
	mkdir -p "${td}" || {
		log_e "无法创建目标目录: ${td}"
		return 1
	}
	
	# Docker环境使用Linux命令，参考原项目简化实现
	local sdev tdev req avail
	sdev=$(stat -c %d "${sp}")
	tdev=$(stat -c %d "${td}")
	
	# 当源和目标的设备号不同时，说明是跨磁盘移动，需要检查空间
	if [[ "${sdev}" != "${tdev}" ]]; then
		log_i "检测到跨磁盘移动，正在检查目标磁盘空间..."
		
		# 获取源文件/目录所需的空间大小（单位: 字节）
		req=$(du -sb "${sp}" | awk '{print $1}')
		
		# 获取目标路径的可用空间大小（单位: 字节）
		avail=$(df --output=avail -B1 "${td}" | sed '1d')

		if (( avail < req )); then
			local req_g avail_g
			req_g=$(awk "BEGIN {printf \"%.2f\", ${req}/1024/1024/1024}")
			avail_g=$(awk "BEGIN {printf \"%.2f\", ${avail}/1024/1024/1024}")
			log_e "目标磁盘空间不足，所需: ${req_g}GB，可用: ${avail_g}GB"
			# 仅在空间不足时设置全局变量供调用方使用
			REQ_SPACE_BYTES="${req}"
			AVAIL_SPACE_BYTES="${avail}"
			return 1
		fi
		log_i "目标磁盘空间充足。"
	else
		log_i "检测为同磁盘移动，无需检查空间。"
	fi
	
	# 空间充足时清空变量，避免状态混乱
	REQ_SPACE_BYTES=""
	AVAIL_SPACE_BYTES=""
	return 0
}

# 路径拼接（去除多余斜杠）
# 入参：base 基准路径；subpath 子路径
# 返回：拼接后的路径
path_join() {
	#
	# _dbg
	# 描述：仅当 DEBUG=1 时输出调试日志到 stderr。
	# 参数：
	#   $@  任意要输出的内容
	# 返回：无
	# 用法: path_join base subpath
	local base="$1" sub="$2"
	if [[ -z "${base}" ]]; then
		echo "${sub}"
		return
	fi
	if [[ -z "${sub}" ]]; then
		echo "${base}"
		return
	fi
	echo "${base%/}/${sub#/}"
}

# 获取相对路径（去除前缀 base/）
# 入参：$1 base 基准路径；$2 full 完整路径
# 返回：full 相对 base 的子路径
relative_path() {
	# $1: base $2: full
	local base="$1" full="$2"
	echo "${full#"${base%/}/"}"
}

# 仅在 DEBUG=1 时输出
_dbg() {
	[[ "${DEBUG:-0}" = "1" ]] && echo -e "[DBG] $*" >&2 || true
}
```

### aria2/scripts/lib/config.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# 配置管理库（供 handlers/utils 使用）
# 职责：
#   - 读取 /config/setting.conf 的开关项到当前 Shell 环境（handlers 使用）。
#   - 提供回填函数：以模板为基准补齐用户缺失的键（不覆盖已有值）。
# 注意：
#   - 不主动修改 setting.conf，除非显式调用 config_apply_setting_defaults（由 20-config 在初始化阶段调用）。

# 防止重复加载
if [[ -n "${_ARIA2_LIB_CONFIG_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_CONFIG_SH_LOADED=1

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/path.sh

# 统一初始化路径变量（SETTING_FILE/ARIA2_CONF/FILTER_FILE 等）
get_base_paths

# 读取 setting.conf 中的开关
# 将键值对加载到当前 shell 环境变量中，供 handlers 使用。
config_load_setting() {
	# 描述：将 setting.conf 的各项开关读入环境变量（RMTASK/MOVE/CF/DET/TOR/RRT/MPT）
	RMTASK=$(kv_get "${SETTING_FILE}" remove-task)
	MOVE=$(kv_get "${SETTING_FILE}" move-task)
	CF=$(kv_get "${SETTING_FILE}" content-filter)
	DET=$(kv_get "${SETTING_FILE}" delete-empty-dir)
	TOR=$(kv_get "${SETTING_FILE}" handle-torrent)
	RRT=$(kv_get "${SETTING_FILE}" remove-repeat-task)
	MPT=$(kv_get "${SETTING_FILE}" move-paused-task)
}

# 该函数仅保留作参考，不在运行路径中调用；保留兼容思路（模板复制 + 兜底默认）
# 实际策略：尊重用户配置文件，不主动覆盖
config_apply_setting_defaults() {
	# 描述：按模板复制 -> 覆盖用户已设置的值 -> 为缺失键填默认值 -> 原子替换
	# 复制模板
	cp /aria2/conf/setting.conf "${SETTING_FILE}.new"
	# 应用用户设置
	[[ -n "${RMTASK}" ]] && kv_set "${SETTING_FILE}.new" remove-task "${RMTASK}"
	[[ -n "${MOVE}" ]] && kv_set "${SETTING_FILE}.new" move-task "${MOVE}"
	[[ -n "${CF}" ]] && kv_set "${SETTING_FILE}.new" content-filter "${CF}"
	[[ -n "${DET}" ]] && kv_set "${SETTING_FILE}.new" delete-empty-dir "${DET}"
	[[ -n "${TOR}" ]] && kv_set "${SETTING_FILE}.new" handle-torrent "${TOR}"
	[[ -n "${RRT}" ]] && kv_set "${SETTING_FILE}.new" remove-repeat-task "${RRT}"
	[[ -n "${MPT}" ]] && kv_set "${SETTING_FILE}.new" move-paused-task "${MPT}"

	# 兜底默认值，防止缺项
	[[ -z "${RMTASK}" ]] && kv_set "${SETTING_FILE}.new" remove-task rmaria
	[[ -z "${MOVE}" ]] && kv_set "${SETTING_FILE}.new" move-task false
	[[ -z "${CF}" ]] && kv_set "${SETTING_FILE}.new" content-filter false
	[[ -z "${DET}" ]] && kv_set "${SETTING_FILE}.new" delete-empty-dir true
	[[ -z "${TOR}" ]] && kv_set "${SETTING_FILE}.new" handle-torrent backup-rename
	[[ -z "${RRT}" ]] && kv_set "${SETTING_FILE}.new" remove-repeat-task true
	[[ -z "${MPT}" ]] && kv_set "${SETTING_FILE}.new" move-paused-task false

	mv "${SETTING_FILE}.new" "${SETTING_FILE}"
}
```

### aria2/scripts/lib/file_ops.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2312
# 文件操作：删除.aria2、清理内容、移动/删除/回收站
# 重写版本：完全按照原项目功能实现，修复发现的错误

if [[ -n "${_ARIA2_LIB_FILE_OPS_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_FILE_OPS_SH_LOADED=1

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/path.sh
. /aria2/scripts/lib/torrent.sh

# ==========================任务信息展示===============================
# 功能：与原项目TASK_INFO()完全一致

print_task_info() {
    echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${LOG_GREEN}${TASK_TYPE}${LOG_NC} ${LOG_YELLOW}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} ${DOWNLOAD_PATH}
${LOG_PURPLE}任务位置:${LOG_NC} ${SOURCE_PATH}
${LOG_PURPLE}首个文件位置:${LOG_NC} ${FILE_PATH}
${LOG_PURPLE}任务文件数量:${LOG_NC} ${FILE_NUM}
${LOG_PURPLE}移动至目标文件夹:${LOG_NC} ${TARGET_PATH}
------------------------------------------------------------------------------------------"
}

print_delete_info() {
    echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${LOG_RED}${TASK_TYPE}${LOG_NC} ${LOG_YELLOW}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} ${DOWNLOAD_PATH}
${LOG_PURPLE}任务位置:${LOG_NC} ${SOURCE_PATH}
${LOG_PURPLE}首个文件位置:${LOG_NC} ${FILE_PATH}
${LOG_PURPLE}任务文件数量:${LOG_NC} ${FILE_NUM}
------------------------------------------------------------------------------------------"
}

# =============================读取过滤配置=============================
# 功能：与原项目LOAD_SCRIPT_CONF()完全一致

_filter_load() {
    MIN_SIZE=$(kv_get "${FILTER_FILE}" min-size)
    INCLUDE_FILE=$(kv_get "${FILTER_FILE}" include-file)
    EXCLUDE_FILE=$(kv_get "${FILTER_FILE}" exclude-file)
    KEYWORD_FILE=$(kv_get "${FILTER_FILE}" keyword-file)
    INCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" include-file-regex)
    EXCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" exclude-file-regex)
}

# =============================删除不需要的文件=============================
# 功能：与原项目DELETE_EXCLUDE_FILE()完全一致

_delete_exclude_file() {
    if [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]] && [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} || -n ${KEYWORD_FILE} || -n ${EXCLUDE_FILE_REGEX} || -n ${INCLUDE_FILE_REGEX} ]]; then
        log_i "删除不需要的文件..."
        [[ -n "${MIN_SIZE}" ]] && find "${SOURCE_PATH}" -type f -size -"${MIN_SIZE}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n "${EXCLUDE_FILE}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n "${KEYWORD_FILE}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*(${KEYWORD_FILE}).*" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n "${INCLUDE_FILE}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n "${EXCLUDE_FILE_REGEX}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex "${EXCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n "${INCLUDE_FILE_REGEX}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex "${INCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
    fi
}

# =============================删除.aria2文件=============================
# 功能：与原项目RM_ARIA2()完全一致

rm_aria2() {
    if [[ -e "${SOURCE_PATH}.aria2" ]]; then
        rm -f "${SOURCE_PATH}.aria2"
        log_i "已删除文件: ${SOURCE_PATH}.aria2"
    fi
}

# =============================删除空文件夹=============================
# 功能：与原项目DELETE_EMPTY_DIR()完全一致

delete_empty_dir() {
    if [[ "${DET}" = "true" ]]; then
        log_i "删除任务中空的文件夹 ..."
        find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
    fi
}

# =============================内容过滤=============================
# 功能：与原项目CLEAN_UP()完全一致

clean_up() {
    rm_aria2
    if [[ "${CF}" = "true" ]] && [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]]; then
        log_i_tee "${CF_LOG}" "被过滤文件的任务路径: ${SOURCE_PATH}"
        _filter_load
        _delete_exclude_file
        delete_empty_dir
    fi
}

# =============================移动文件=============================
# 功能：与原项目MOVE_FILE()完全一致（修复了一些错误）

move_file() {
    # DOWNLOAD_DIR = DOWNLOAD_PATH，说明为在根目录下载的单文件，`dmof`时不进行移动
    if [[ "${MOVE}" = "false" ]]; then
        rm_aria2
        return 0
    elif [[ "${MOVE}" = "dmof" ]] && [[ "${DOWNLOAD_DIR}" = "${DOWNLOAD_PATH}" ]] && [[ ${FILE_NUM} -eq 1 ]]; then
        rm_aria2
        return 0
    elif [[ "${MOVE}" = "true" ]] || [[ "${MOVE}" = "dmof" ]]; then
        TASK_TYPE=": 移动任务文件"
        print_task_info
        clean_up
        log_i_color "开始移动该任务文件到: ${LOG_GREEN}${TARGET_PATH}${LOG_NC}"
        mkdir -p "${TARGET_PATH}"

        # 移动前检查磁盘空间（使用common.sh中的统一函数）
        if ! check_space_before_move "${SOURCE_PATH}" "${TARGET_PATH}"; then
            # 空间不足的处理
            if [[ -n "${REQ_SPACE_BYTES:-}" ]] && [[ -n "${AVAIL_SPACE_BYTES:-}" ]]; then
                local req_g avail_g
                req_g=$(awk "BEGIN {printf \"%.2f\", ${REQ_SPACE_BYTES}/1024/1024/1024}")
                avail_g=$(awk "BEGIN {printf \"%.2f\", ${AVAIL_SPACE_BYTES}/1024/1024/1024}")
                log_e "目标磁盘空间不足！无法移动文件。"
                log_e "所需空间: ${req_g} GB, 目标可用空间: ${avail_g} GB."
                log_e_file "${MOVE_LOG}" "目标磁盘空间不足，移动失败。所需空间:${req_g} GB, 可用空间:${avail_g} GB. 源:${SOURCE_PATH} -> 目标:${TARGET_PATH}"
            fi
            
            # 空间不足，直接将任务移动到失败文件夹
            local FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
            log_w "尝试将任务移动到: ${FAIL_DIR}"
            mkdir -p "${FAIL_DIR}"
            mv -f "${SOURCE_PATH}" "${FAIL_DIR}"
            local MOVE_FAIL_EXIT_CODE=$?
            if [[ ${MOVE_FAIL_EXIT_CODE} -eq 0 ]]; then
                log_i_tee "${MOVE_LOG}" "因目标磁盘空间不足，已将文件移动至: ${SOURCE_PATH} -> ${FAIL_DIR}"
            else
                log_e_tee "${MOVE_LOG}" "移动到 ${FAIL_DIR} 依然失败: ${SOURCE_PATH}"
            fi
            return 1
        fi

        # 执行移动
        mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
        local MOVE_EXIT_CODE=$?
        if [[ ${MOVE_EXIT_CODE} -eq 0 ]]; then
            log_i_tee "${MOVE_LOG}" "已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}"
        else
            log_e_tee "${MOVE_LOG}" "文件移动失败: ${SOURCE_PATH}"
            
            # 移动失败后（非空间不足原因），转移至 /downloads/move-failed
            local FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
            mkdir -p "${FAIL_DIR}"
            # 修复：在Docker环境下增加文件存在性检查
            if [[ ! -e "${SOURCE_PATH}" ]]; then
                log_w_tee "${MOVE_LOG}" "源文件不存在，无法移动: ${SOURCE_PATH}"
            else
                mv -f "${SOURCE_PATH}" "${FAIL_DIR}"
                local MOVE_FAIL_EXIT_CODE=$?
                if [[ ${MOVE_FAIL_EXIT_CODE} -eq 0 ]]; then
                    log_i_tee "${MOVE_LOG}" "已将文件移动至: ${SOURCE_PATH} -> ${FAIL_DIR}"
                else
                    log_e_tee "${MOVE_LOG}" "移动到 ${FAIL_DIR} 依然失败: ${SOURCE_PATH}"
                fi
            fi
        fi
    fi
}

# =============================删除文件=============================
# 功能：与原项目DELETE_FILE()完全一致（修复变量名错误）

delete_file() {
    TASK_TYPE=": 删除任务文件"
    print_delete_info
    log_i "下载已停止，开始删除文件..."
    
    # 如果是多文件任务且存在目录，显示删除的文件列表
    if [[ ${FILE_NUM} -gt 1 ]] && [[ -d "${SOURCE_PATH}" ]]; then
        log_i "删除文件夹中的所有文件:"
        find "${SOURCE_PATH}" -type f -print0 | while IFS= read -r -d '' file; do
            echo "removed '${file}'"
        done
    fi
    
    rm -rf "${SOURCE_PATH}"
    local DELETE_EXIT_CODE=$?  # 修复：原项目错误使用了MOVE_EXIT_CODE
    if [[ ${DELETE_EXIT_CODE} -eq 0 ]]; then
        log_i "已删除文件: ${SOURCE_PATH}"
        log_i_tee "${DELETE_LOG}" "文件删除成功: ${SOURCE_PATH}"
    else
        log_e_tee "${DELETE_LOG}" "delete failed: ${SOURCE_PATH}"
    fi
    
    # 删除对应的.aria2文件
    rm_aria2
}

# =============================回收站=============================
# 功能：与原项目MOVE_RECYCLE()完全一致（修复变量名错误）

move_recycle() {
    TASK_TYPE=": 移动任务文件至回收站"
    print_task_info
    log_i_color "开始移动已下载的任务至回收站 ${LOG_GREEN}${TARGET_PATH}${LOG_NC}"
    mkdir -p "${TARGET_PATH}"
    mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
    local RECYCLE_EXIT_CODE=$?  # 修复：原项目错误使用了MOVE_EXIT_CODE
    if [[ ${RECYCLE_EXIT_CODE} -eq 0 ]]; then
        log_i_tee "${RECYCLE_LOG}" "已移至回收站: ${SOURCE_PATH} -> ${TARGET_PATH}"
    else
        log_e "移动文件到回收站失败: ${SOURCE_PATH}"
        log_i "已删除文件: ${SOURCE_PATH}"
        rm -rf "${SOURCE_PATH}"
        log_e_tee "${RECYCLE_LOG}" "移动文件到回收站失败: ${SOURCE_PATH}"
    fi
}
```

### aria2/scripts/lib/kvconf.sh
```bash
#!/usr/bin/env bash
# 通用 kv 配置文件操作（key=value，允许 key\s*=\s*value）
# 提供 upsert：存在则替换，不存在则追加到文件末尾。
# 约定：不改变文件中其他内容的顺序；仅单行键操作。

set -euo pipefail

# conf_upsert_kv <file> <key> <value>
conf_upsert_kv() {
	local file="$1" key="$2" value="$3"
	# 若文件不存在，直接创建
	if [[ ! -f "$file" ]]; then
		printf '%s=%s\n' "$key" "$value" >"$file"
		return 0
	fi
	# 匹配 key[space]*=[space]*
	if grep -Eq "^${key}[[:space:]]*=" "$file"; then
		# 使用 sed 兼容空白的替换
		# shellcheck disable=SC2016
		sed -i "s@^${key}[[:space:]]*=.*@${key}=${value}@" "$file"
	else
		printf '%s=%s\n' "$key" "$value" >>"$file"
	fi
}

# conf_upsert_path <file> <key> </path/value>
# 用于包含路径的值，避免 sed 中出现分隔符冲突，仍使用 @ 作为 sed 分隔符
conf_upsert_path() {
	conf_upsert_kv "$@"
}
```

### aria2/scripts/lib/logger.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# 统一日志库：供所有脚本（handlers/utils/cont-init.d）复用
# 仅定义颜色、时间与 log_* 接口，不引入其他依赖

if [[ -n "${_ARIA2_LIB_LOGGER_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_LOGGER_SH_LOADED=1

# 颜色定义（保持与原项目一致）
LOG_RED="\033[31m"
LOG_GREEN="\033[1;32m" 
LOG_YELLOW="\033[1;33m"
LOG_CYAN="\033[36m"
LOG_PURPLE="\033[1;35m"  # 修正为与原项目一致的 1;35m
LOG_BOLD="\033[1m"
LOG_NC="\033[0m"

# 标签定义（修正拼写错误）
INFO="[${LOG_GREEN}INFO${LOG_NC}]"
ERROR="[${LOG_RED}ERROR${LOG_NC}]"
WARN="[${LOG_YELLOW}WARN${LOG_NC}]"

# 时间函数（与原项目DATE_TIME()一致）
now() { date +"%Y/%m/%d %H:%M:%S"; }

# 基础日志函数（仅控制台输出）
log_i() { echo -e "$(now) ${INFO} $*"; }
log_w() { echo -e "$(now) ${WARN} $*"; }
log_e() { echo -e "$(now) ${ERROR} $*"; }

# 彩色日志函数（支持颜色输出到控制台）
log_i_color() { echo -e "$(now) ${INFO} $*"; }
log_w_color() { echo -e "$(now) ${WARN} $*"; }
log_e_color() { echo -e "$(now) ${ERROR} $*"; }

# tee模式：同时输出到控制台和文件（用于重要操作）
log_i_tee() { echo -e "$(now) ${INFO} $*" | tee -a "${1}"; }
log_w_tee() { echo -e "$(now) ${WARN} $*" | tee -a "${1}"; }
log_e_tee() { echo -e "$(now) ${ERROR} $*" | tee -a "${1}"; }

# 文件模式：仅写入文件，使用纯文本格式（兼容原项目的条件日志）
log_file() { 
    local level="$1" file="$2"; shift 2
    [[ -n "${file}" ]] && echo -e "$(now) [${level}] $*" >> "${file}"
}
log_i_file() { log_file "INFO" "$@"; }
log_w_file() { log_file "WARN" "$@"; }
log_e_file() { log_file "ERROR" "$@"; }
```

### aria2/scripts/lib/path.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154,SC2034
# 路径处理：获取任务路径、目标路径等

if [[ -n "${_ARIA2_LIB_PATH_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_PATH_SH_LOADED=1

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh

# 基础路径
# 描述：初始化路径相关的全局变量（下载根、日志路径、备份目录等）。
get_base_paths() {
	# 下载根目录（允许环境变量覆盖）
	DOWNLOAD_PATH="${DOWNLOAD_PATH:-/downloads}"

	# 配置与日志路径（集中定义，供各脚本引用；允许环境覆盖）
	CONFIG_DIR="${CONFIG_DIR:-/config}"
	LOG_DIR="${LOG_DIR:-${CONFIG_DIR}/logs}"

	# 关键配置文件（允许环境覆盖）
	SETTING_FILE="${SETTING_FILE:-${CONFIG_DIR}/setting.conf}"
	ARIA2_CONF="${ARIA2_CONF:-${CONFIG_DIR}/aria2.conf}"
	FILTER_FILE="${FILTER_FILE:-${CONFIG_DIR}/文件过滤.conf}"

	# 状态文件（允许环境覆盖）
	SESSION_FILE="${SESSION_FILE:-${CONFIG_DIR}/aria2.session}"
	DHT_FILE="${DHT_FILE:-${CONFIG_DIR}/dht.dat}"

	# 日志文件（允许环境覆盖）
	CF_LOG="${CF_LOG:-${LOG_DIR}/文件过滤日志.log}"
	MOVE_LOG="${MOVE_LOG:-${LOG_DIR}/move.log}"
	DELETE_LOG="${DELETE_LOG:-${LOG_DIR}/delete.log}"
	RECYCLE_LOG="${RECYCLE_LOG:-${LOG_DIR}/recycle.log}"
	TORRENT_LOG="${TORRENT_LOG:-${LOG_DIR}/torrent.log}"

	# 其他目录（允许环境覆盖）
	BAK_TORRENT_DIR="${BAK_TORRENT_DIR:-${CONFIG_DIR}/backup-torrent}" # 种子备份目录
}

# 确保仅初始化一次：可被显式调用，也会在库加载时自动执行一次
ensure_base_paths() {
	if [[ -z "${_ARIA2_BASE_PATHS_INIT:-}" ]]; then
		get_base_paths
		_ARIA2_BASE_PATHS_INIT=1
	fi
}

# 自动初始化一次，避免各脚本显式重复调用
ensure_base_paths

# 规范化与验证工具
# 描述：
#   - normalize_path: 折叠多重斜杠、移除内联"/./"、去除末尾"/."；
#   - validate_under_target: 校验路径前缀必须位于 TARGET_DIR 下。
normalize_path() {
	local p="$1"
	# 使用 sed 进行路径规范化（更高效的单次处理）
	printf '%s' "$p" | sed 's|/\./|/|g; s|/\+|/|g; s|/\.$||'
}

validate_under_target() {
	local target_dir p
	# 支持调用方式：validate_under_target path (使用 TARGET_DIR)
	target_dir="${TARGET_DIR}"
	p="$1"
	
	if [[ -z "$p" ]]; then
		GET_PATH_INFO="error"
		return 1
	fi
	# 必须在目标目录下
	if [[ ! "$p" =~ ^"${target_dir}"(/.*)?$ ]]; then
		GET_PATH_INFO="error"
		return 1
	fi
	return 0
}

# 完成目录
# 描述：设置目标根目录为 /downloads/completed（最终移动目标基准）。
completed_path() { TARGET_DIR="${DOWNLOAD_PATH}/completed"; }
# 回收站目录
# 描述：设置目标根目录为 /downloads/recycle（回收站目标基准）。
recycle_path() { TARGET_DIR="${DOWNLOAD_PATH}/recycle"; }

# 打印任务信息
# 描述：任务信息输出。
print_task_info() {
	echo -e "\n-------------------------- [${LOG_YELLOW} 任务信息 ${TASK_TYPE:-} ${LOG_NC}] --------------------------"
	echo -e "${LOG_PURPLE}根下载路径:${LOG_NC} ${DOWNLOAD_PATH}"
	echo -e "${LOG_PURPLE}任务位置:${LOG_NC} ${SOURCE_PATH}"
	echo -e "${LOG_PURPLE}首个文件位置:${LOG_NC} ${FILE_PATH}"
	echo -e "${LOG_PURPLE}任务文件数量:${LOG_NC} ${FILE_NUM}"
	[[ -n "${TARGET_PATH:-}" ]] && echo -e "${LOG_PURPLE}移动至目标文件夹:${LOG_NC} ${TARGET_PATH}"
	echo -e "------------------------------------------------------------------------------\n"
}

print_delete_info() {
	# 描述：仅用于删除场景的信息输出，省略目标目录展示。
	echo -e "\n-------------------------- [${LOG_YELLOW} 任务信息 ${TASK_TYPE:-} ${LOG_NC}] --------------------------"
	echo -e "${LOG_PURPLE}根下载路径:${LOG_NC} ${DOWNLOAD_PATH}"
	echo -e "${LOG_PURPLE}任务位置:${LOG_NC} ${SOURCE_PATH}"
	echo -e "${LOG_PURPLE}首个文件位置:${LOG_NC} ${FILE_PATH}"
	echo -e "${LOG_PURPLE}任务文件数量:${LOG_NC} ${FILE_NUM}"
	echo -e "------------------------------------------------------------------------------\n"
}

# 解析最终路径（兼容原逻辑）
# 输入依赖：FILE_NUM、FILE_PATH、DOWNLOAD_DIR、DOWNLOAD_PATH、目标根 TARGET_DIR
# 行为：
#   - 多文件任务或文件在子目录 -> 以任务顶层目录为 SOURCE_PATH，并保持相对层级生成 TARGET_PATH/COMPLETED_DIR；
#   - 单文件任务 -> 以文件自身为 SOURCE_PATH，TARGET_PATH 指向保持层级的目标目录；
#   - 防御：若解析得到的 TARGET_PATH 异常（如 “//” 或 “/.”），进行纠正或置错误标记。
get_final_path() {
	# 依赖: FILE_NUM, FILE_PATH, DOWNLOAD_DIR, DOWNLOAD_PATH, TARGET_DIR
	[[ -z "${FILE_PATH}" ]] && return 0

	# 边界检查：确保 FILE_PATH 在 DOWNLOAD_DIR 下
	if [[ ! "${FILE_PATH}" =~ ^"${DOWNLOAD_DIR}"(/.*)?$ ]]; then
		log_w "文件路径异常，跳过处理: ${FILE_PATH}"
		GET_PATH_INFO="error"
		return 0
	fi
	if [[ "${FILE_NUM}" -gt 1 ]] || [[ "$(dirname "${FILE_PATH}")" != "${DOWNLOAD_DIR}" ]]; then
		# 多文件 或 文件在子目录
		local rel task
		rel=$(relative_path "${DOWNLOAD_DIR}" "${FILE_PATH}")
		task="${rel%%/*}"
		# 防御性检查：确保任务名不为空；为空则报错并退出
		if [[ -z "${task}" ]]; then
			log_w "无法解析任务名，跳过处理: ${FILE_PATH}"
			GET_PATH_INFO="error"
			return 0
		fi
		TASK_NAME="${task}"
		SOURCE_PATH="${DOWNLOAD_DIR}/${TASK_NAME}"
		# 目标路径保持层级
		local rel2
		rel2=$(relative_path "${DOWNLOAD_PATH}" "${SOURCE_PATH}")
		TARGET_PATH="${TARGET_DIR}/$(dirname "${rel2}")"
		COMPLETED_DIR="${TARGET_PATH}/${TASK_NAME}"
	else
		# 单文件
		SOURCE_PATH="${FILE_PATH}"
		local rel
		rel=$(relative_path "${DOWNLOAD_DIR}" "${FILE_PATH}")
		TASK_NAME="${rel%.*}"
		local rel2
		rel2=$(relative_path "${DOWNLOAD_PATH}" "${SOURCE_PATH}")
		TARGET_PATH="${TARGET_DIR}/$(dirname "${rel2}")"
	fi
	# 统一规范化并进行前缀校验，杜绝出现 // 或 /.
	TARGET_PATH="$(normalize_path "${TARGET_PATH}")"
	if [[ -n "${COMPLETED_DIR:-}" ]]; then
		COMPLETED_DIR="$(normalize_path "${COMPLETED_DIR}")"
	fi
	validate_under_target "${TARGET_PATH}" || return 0
	if [[ -n "${COMPLETED_DIR:-}" ]]; then
		validate_under_target "${COMPLETED_DIR}" || return 0
	fi
}
```

### aria2/scripts/lib/rpc.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2034
# RPC 相关操作库
# 职责：
#   - 构造 JSON-RPC 请求（含可选 SECRET 鉴权）。
#   - 提供通用调用封装：获取任务状态、删除任务、修改全局配置。
#   - 解析返回并导出常用字段供 handlers 使用。
# 约定：PORT/SECRET 若存在，则用于拼装 RPC 地址与鉴权。

if [[ -n "${_ARIA2_LIB_RPC_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_RPC_SH_LOADED=1

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh

RPC_ADDR() { echo "http://localhost:${PORT:-6800}/jsonrpc"; } # 生成 RPC 地址，默认 6800

rpc_call() {
	# 统一的 RPC 调用入口：先 HTTP，失败回退 HTTPS（-k）
	# $1: json payload
	local payload="$1"
	curl "$(RPC_ADDR)" -fsSd "${payload}" -H 'Content-Type: application/json' || curl "$(RPC_ADDR | sed "s@http:@https:@")" -kfsSd "${payload}" -H 'Content-Type: application/json'
}

rpc_payload_status() {
	# 生成 tellStatus 请求体；若设置 SECRET 则携带 token
	# $1: gid
	local gid="$1"
	local id="NG6"
	if [[ -n "${SECRET:-}" ]]; then
		echo '{"jsonrpc":"2.0","method":"aria2.tellStatus","id":"'"${id}"'","params":["token:'"${SECRET}"'","'"${gid}"'"]}'
	else
		echo '{"jsonrpc":"2.0","method":"aria2.tellStatus","id":"'"${id}"'","params":["'"${gid}"'"]}'
	fi
}

rpc_payload_remove() {
	# 生成 remove 请求体；若设置 SECRET 则携带 token
	local gid="$1"
	local id="NG6"
	if [[ -n "${SECRET:-}" ]]; then
		echo '{"jsonrpc":"2.0","method":"aria2.remove","id":"'"${id}"'","params":["token:'"${SECRET}"'","'"${gid}"'"]}'
	else
		echo '{"jsonrpc":"2.0","method":"aria2.remove","id":"'"${id}"'","params":["'"${gid}"'"]}'
	fi
}

rpc_payload_change_global() {
	# 生成 changeGlobalOption 请求体；若设置 SECRET 则携带 token
	# $1: key $2: value
	local key="$1" val="$2" id="NG6"
	if [[ -n "${SECRET:-}" ]]; then
		echo '{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"'"${id}"'","params":["token:'"${SECRET}"'",{"'"${key}"'":"'"${val}"'"}]}'
	else
		echo '{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"'"${id}"'","params":[{"'"${key}"'":"'"${val}"'"}]}'
	fi
}

rpc_get_status() {
	# 执行 tellStatus 并返回原始 JSON
	# $1: gid -> stdout json
	local payload
	payload=$(rpc_payload_status "$1")
	rpc_call "${payload}"
}

rpc_remove_task() {
	# 执行 remove 删除任务
	local payload
	payload=$(rpc_payload_remove "$1")
	rpc_call "${payload}"
}

rpc_change_global_option() {
	# 修改 aria2 的全局配置（如 bt-tracker）
	local key="$1" val="$2" payload
	payload=$(rpc_payload_change_global "${key}" "${val}")
	rpc_call "${payload}"
}

rpc_get_parsed_fields() {
	# 获取并解析任务核心字段，失败时返回非 0
	# $1: gid -> set global vars: RPC_RESULT, TASK_STATUS, DOWNLOAD_DIR, INFO_HASH, TORRENT_PATH, TORRENT_FILE
	local gid="$1"
	RPC_RESULT=$(rpc_get_status "${gid}")
	if [[ -z "${RPC_RESULT}" ]]; then
		log_e "Aria2 RPC 接口错误。"
		return 1
	fi
	TASK_STATUS=$(echo "${RPC_RESULT}" | jq -r '.result.status')
	DOWNLOAD_DIR=$(echo "${RPC_RESULT}" | jq -r '.result.dir')
	INFO_HASH=$(echo "${RPC_RESULT}" | jq -r '.result.infoHash // empty')
	if [[ -z "${TASK_STATUS}" ]] || [[ -z "${DOWNLOAD_DIR}" ]]; then
		echo "${RPC_RESULT}" | jq '.result' 2>/dev/null || true
		log_e "获取任务状态或下载目录失败。"
		return 1
	fi
	if [[ -n "${INFO_HASH}" ]] && [[ "${INFO_HASH}" != "null" ]]; then
		TORRENT_PATH="${DOWNLOAD_DIR}/${INFO_HASH}"
		TORRENT_FILE="${DOWNLOAD_DIR}/${INFO_HASH}.torrent"
	else
		TORRENT_PATH=""
		TORRENT_FILE=""
	fi
}

# 仅用于重复任务移除：延迟 3s 后忽略错误尝试 remove
rpc_remove_repeat_task() {
	local gid="$1"
	sleep 3
	rpc_remove_task "${gid}" >/dev/null 2>&1 || true
}
```

### aria2/scripts/lib/torrent.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# 种子文件处理
# 职责：根据 setting.conf 的 handle-torrent 选项处理磁力保存的 .torrent 文件。
# 支持策略：retain/delete/rename/backup/backup-rename。

if [[ -n "${_ARIA2_LIB_TORRENT_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_TORRENT_SH_LOADED=1

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/path.sh

handle_torrent() {
	# 描述：按 TOR 指定的策略处理 .torrent 文件
	# 依赖: TOR, TORRENT_FILE, TASK_NAME, BAK_TORRENT_DIR
	[[ -n "${TOR:-}" ]] || return 0
	[[ -n "${TORRENT_FILE:-}" ]] || return 0
	case "${TOR}" in
	retain)
		# 保留种子文件，不做处理
		log_i_tee "${TORRENT_LOG}" "种子已保留: $(basename "${TORRENT_FILE}") -> ${SAVE_PATH:-unknown}"
		;;
	delete)
		log_i "已删除种子文件: ${TORRENT_FILE}"
		rm -f "${TORRENT_FILE}"
		log_i_tee "${TORRENT_LOG}" "种子已删除: $(basename "${TORRENT_FILE}") -> ${SAVE_PATH:-unknown}"
		;;
	rename)
		log_i "已重命名种子文件: ${TORRENT_FILE} -> ${TASK_NAME}.torrent"
		mv -f "${TORRENT_FILE}" "$(dirname "${TORRENT_FILE}")/${TASK_NAME}.torrent"
		log_i_tee "${TORRENT_LOG}" "种子已重命名: ${TASK_NAME}.torrent -> ${SAVE_PATH:-unknown}"
		;;
	backup)
		log_i "备份种子文件: ${TORRENT_FILE}"
		mkdir -p "${BAK_TORRENT_DIR}" && mv -vf "${TORRENT_FILE}" "${BAK_TORRENT_DIR}"
		log_i_tee "${TORRENT_LOG}" "种子已备份: $(basename "${TORRENT_FILE}") -> ${BAK_TORRENT_DIR}"
		;;
	backup-rename)
		log_i "重命名并备份种子文件: ${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
		mkdir -p "${BAK_TORRENT_DIR}" && mv -f "${TORRENT_FILE}" "${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
		log_i_tee "${TORRENT_LOG}" "种子已重命名并备份: ${TASK_NAME}.torrent -> ${BAK_TORRENT_DIR}"
		;;
	*)
		:
		;;
	esac
}

check_torrent() { [[ -e "${TORRENT_FILE:-}" ]] && handle_torrent; } # 若存在 .torrent 文件才进行处理
```

### aria2/scripts/utils/cron-restart-a2b.sh
```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# 定时重启 aria2b
set -euo pipefail
. /aria2/scripts/lib/logger.sh

# 检查 aria2b 是否存在，不存在则静默退出
[[ -x "/usr/local/bin/aria2b" ]] || exit 0

# 仅在 A2B=true 时生效
if [[ "${A2B:-false}" != "true" ]]; then
    log_i "A2B 未启用，跳过配置 aria2b 重启定时任务。"
    exit 0
fi

VAL="${CRA2B:-2h}"
if [[ "${VAL}" == "false" ]]; then
    # 移除既有条目
    (crontab -l 2>/dev/null | grep -v "aria2b.*kill") | crontab - || true
    log_i "CRA2B=false，已移除 aria2b 重启定时任务。"
    exit 0
fi

# 提取小时数字，默认 2 小时；范围 1-24
HOURS=${VAL//[^0-9]/}
if ! [[ "${HOURS}" =~ ^([1-9]|1[0-9]|2[0-4])$ ]]; then
    HOURS=2
    log_w "CRA2B='${VAL}' 非法，回退为 ${HOURS} 小时。"
fi

# 先清理旧规则，再写入新规则（整点执行）
(crontab -l 2>/dev/null | grep -v "aria2b.*kill") | crontab - || true
(crontab -l 2>/dev/null; echo "0 */${HOURS} * * * pgrep -x aria2b >/dev/null && pkill -9 aria2b || true") | crontab -
log_i "已设置定时任务：每 ${HOURS} 小时整点重启 aria2b。"
```

### aria2/scripts/utils/tracker.sh
```bash
#!/usr/bin/env bash
# 工具：Tracker 更新
# 用法：tracker.sh            -> 从默认列表更新到 aria2.conf
#       tracker.sh --local    -> 从 /config/aria2.conf 直接覆盖 bt-tracker（同上）
#       tracker.sh --rpc      -> 通过 RPC 动态更新 bt-tracker（无需重启）

set -euo pipefail

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/config.sh
. /aria2/scripts/lib/rpc.sh
. /aria2/scripts/lib/kvconf.sh

# 使用集中化的 ARIA2_CONF
DOWNLOADER="curl -fsSL --connect-timeout 3 --max-time 3 --retry 2"
NL=$'\n'
TRACKER_COUNT=0

get_trackers() {
	# 描述：获取 trackers 列表；优先使用默认源，若设置 CTU（逗号分隔）则按自定义源合并去重。
	if [ -z "${CTU:-}" ]; then
		log_i "获取 bt-tracker ..."
		TRACKER=$(
			${DOWNLOADER} https://trackerslist.com/all_aria2.txt ||
				${DOWNLOADER} https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt ||
				${DOWNLOADER} https://trackers.p3terx.com/all_aria2.txt
		)
	else
		log_i "从自定义地址获取 bt-tracker: ${CTU}"
		local urls
		urls=$(echo "${CTU}" | tr "," "$NL")
		local t=""
		for u in $urls; do
			t+="$(${DOWNLOADER} "$u" | tr "," "\n")$NL"
		done
		TRACKER=$(echo "$t" | awk NF | sort -u | sed 'H;1h;$!d;x;y/\n/,/')
	fi
	[ -n "${TRACKER:-}" ] || {
		log_e "无法获取 trackers，网络错误或链接无效。"
		exit 1
	}

	# 统计数量（按逗号拆分并过滤空行）
	TRACKER_COUNT=$(printf "%s" "${TRACKER}" | tr ',' '\n' | awk 'NF' | wc -l | tr -d ' ')
}

show_trackers() {
	# 描述：打印列表或摘要；默认打印数量摘要，TRACKER_SHOW=list 或 DEBUG=1 时打印完整列表
	local mode="count"
	if [[ "${TRACKER_SHOW:-count}" = "list" || "${DEBUG:-0}" = "1" ]]; then
		mode="list"
	fi
	if [[ "${mode}" = "list" ]]; then
		echo -e "\n--------------------[BitTorrent Trackers]--------------------\n${TRACKER}\n--------------------[BitTorrent Trackers]--------------------\n"
	else
		log_i "获取到 ${TRACKER_COUNT} 条 bt-tracker。"
	fi
}

add_trackers_conf() {
	# 描述：将 TRACKER 列表写入到 /config/aria2.conf 的 bt-tracker 键
	log_i "添加 bt-tracker 到 Aria2 配置文件: ${LOG_PURPLE}${ARIA2_CONF}${LOG_NC}"
	[ -f "$ARIA2_CONF" ] || {
		log_e "配置文件不存在: $ARIA2_CONF"
		exit 1
	}
	conf_upsert_kv "$ARIA2_CONF" bt-tracker "$TRACKER"
	log_i "bt-tracker 已写入配置文件，共 ${TRACKER_COUNT} 条。"
}

add_trackers_rpc() {
	# 描述：通过 RPC 动态更新 bt-tracker，无需重启 aria2
	log_i "通过 RPC 更新 bt-tracker（无需重启）..."
	local res
	res=$(rpc_change_global_option "bt-tracker" "${TRACKER}" || true)
	if echo "$res" | grep -q OK; then
		log_i "RPC 更新成功，共 ${TRACKER_COUNT} 条。"
	else
		log_e "RPC 更新失败或接口无响应。"
	fi
}

main() {
	# 描述：主入口；默认写配置文件，传入 --rpc 参数时改为通过 RPC 更新
	local mode="conf"
	if [ "${1:-}" = "--rpc" ]; then mode="rpc"; fi
	get_trackers
	show_trackers
	if [ "$mode" = "rpc" ]; then
		add_trackers_rpc
	else
		add_trackers_conf
	fi
}

main "$@"
```

## 配置文件
### aria2/conf/setting.conf
```
## docker aria2 功能设置 ##
# 配置文件为本项目的自定义设置选项
# 重置配置文件：删除本文件后重启容器
# 所有设置无需重启容器,即刻生效

# 删除任务，`delete`为删除任务后删除文件，`recycle`为删除文件至回收站，`rmaria`为只删除.aria2文件
remove-task=rmaria

# 下载完成后执行操作选项，默认`false`
# `true`，下载完成后保留目录结构移动
# `dmof`非自定义目录任务，单文件，不执行移动操作。自定义目录、单文件，保留目录结构移动（推荐）
move-task=false

# 文件过滤，任务下载完成后删除不需要的文件内容，`false`、`true`
# 由于aria2自身限制，无法在下载前取消不需要的文件（只能在任务完成后删除文件）
content-filter=false

# 下载完成后删除空文件夹，默认`true`，需要开启文件过滤功能才能生效
# 开启内容过滤后，可能会产生空文件夹，开启`DET`选项后可以删除当前任务中的空文件夹
delete-empty-dir=true

# 对磁力链接生成的种子文件进行操作
# 在开启`SMD`选项后生效，上传的种子无法更名、移动、删除，仅对通过磁力链接保存的种子生效
# 默认保留`retain`,可选删除`delete`，备份种子文件`backup`、重命名种子文件`rename`，重命名种子文件并备份`backup-rename`
# 种子备份位于`/config/backup-torrent`
handle-torrent=backup-rename

# 删除重复任务，检测已完成文件夹，如果有该任务文件，则删除任务，并删除文件，仅针对文件数量大于1的任务生效
# 默认`true`，可选`false`关闭该功能
remove-repeat-task=true

# 任务暂停后移动文件，部分任务下载至百分之99时无法下载，可以启动本选项
# 建议仅在需要时开启该功能，使用完后请记得关闭
# 默认`false`，可选`true`开启该功能
move-paused-task=false
```

### aria2/conf/文件过滤.conf
```
## 文件过滤设置(全局) ##

# 仅 BT 多文件下载时有效，用于过滤无用文件。
# 可自定义；如需启用请删除对应行的注释 # 

# 排除小文件。低于此大小的文件将在下载完成后被删除。
#min-size=10M

# 保留文件类型。其它文件类型将在下载完成后被删除。
#include-file=mp4|mkv|rmvb|mov|avi|srt|ass

# 排除文件类型。排除的文件类型将在下载完成后被删除。
#exclude-file=html|url|lnk|txt|jpg|png

# 按关键词排除。包含以下关键字的文件将在下载完成后被删除。
#keyword-file=广告1|广告2|广告3

# 保留文件(正则表达式)。其它文件类型将在下载完成后被删除。
#include-file-regex=

# 排除文件(正则表达式)。排除的文件类型将在下载完成后被删除。
# 示例为排除比特彗星的 padding file
#exclude-file-regex="(.*/)_+(padding)(_*)(file)(.*)(_+)"```

## 系统初始化脚本
### etc/cont-init.d/11-banner
```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2312
# 显示启动看板（仅在容器启动时显示一次）
set -euo pipefail
. /aria2/scripts/lib/logger.sh

build=$(sed -n '1p' /aria2/build-date 2>/dev/null)
ver=${build:-docker-aria2}
arch=$(uname -m)
base="Alpine Linux $(cat /etc/alpine-release 2>/dev/null)"
tz=${TZ:-Asia/Shanghai}

echo "==============================================================================="
echo "                    🚀 Docker-Aria2 容器启动成功 🚀"
echo "==============================================================================="
echo
echo "📦 镜像信息:"
echo "   版本信息: ${ver}"
echo "   AriaNg版本: $(sed -n '2p' /aria2/build-date 2>/dev/null | sed 's/docker-ariang-//')"
echo "   Aria2版本: 1.36.0 (静态编译, 解除线程限制)"
echo "   平台架构: ${arch}"
echo "   基础镜像: ${base}"
echo "   时区设置: ${tz}"
echo
echo "🌐 服务端口:"
echo "   RPC端口: ${PORT:-6800}"
if [[ "${WEBUI:-true}" = "true" ]]; then echo "   WebUI端口: ${WEBUI_PORT:-8080} [启用]"; else echo "   WebUI端口: ${WEBUI_PORT:-8080} [停用]"; fi
echo "   BT监听端口: ${BTPORT:-32516} (TCP/UDP)"
echo
echo "⚙️  核心配置:"
echo "   磁盘缓存: ${CACHE:-128M}"
echo "   静默模式: [${QUIET:-true}]"
echo "   用户权限: PUID=${PUID:-0}, PGID=${PGID:-0}"
echo
echo "🎯 功能特性:"
echo "   启动更新Tracker: [${UT:-true}]"
echo "   定时更新Tracker: [${RUT:-true}]"
echo "   Tracker 输出: 默认仅显示数量；设 TRACKER_SHOW=list 或 DEBUG=1 显示完整列表"
echo "   保存磁力为种子: [${SMD:-true}]"
echo "   屏蔽吸血客户端: $([[ "${A2B:-false}" = "true" && -f /usr/local/bin/aria2b ]] && echo "[启用]" || echo "[禁用]")"
echo
echo "📚 帮助链接:"
echo "   项目地址: https://github.com/SuperNG6/docker-aria2"
echo "   使用教程: https://sleele.com/2019/09/27/docker-aria2的最佳实践"
echo "   Docker Hub: https://hub.docker.com/r/superng6/aria2"
echo
echo "==============================================================================="
echo "                      🎉 启动完成 🎉"
echo "==============================================================================="
```

### etc/cont-init.d/20-config
```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# shellcheck disable=SC1091
# 初始化目录、配置与日志文件（仅在容器启动）
set -euo pipefail
. /aria2/scripts/lib/logger.sh
# 供 config_apply_setting_defaults 使用的依赖
# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/config.sh

# 此处不再手工定义路径，统一由 path.sh/config.sh 内的 get_base_paths 提供

# 目录
mkdir -p "${CONFIG_DIR}/ssl" "${LOG_DIR}" "${BAK_TORRENT_DIR}" "${DOWNLOAD_PATH}/completed" "${DOWNLOAD_PATH}/recycle"

# 配置文件按模板初始化
[[ -f "${ARIA2_CONF}" ]] || cp /aria2/conf/aria2.conf.default "${ARIA2_CONF}"
[[ -f "${SETTING_FILE}" ]] || cp /aria2/conf/setting.conf "${SETTING_FILE}"
[[ -f "${FILTER_FILE}" ]] || cp /aria2/conf/文件过滤.conf "${FILTER_FILE}"

# 必需空文件
[[ -f "${SESSION_FILE}" ]] || : > "${SESSION_FILE}"
[[ -f "${DHT_FILE}" ]] || : > "${DHT_FILE}"

# setting.conf 缺省回填/容错回写：
# 将模板复制为临时文件 → 覆盖用户现有值 → 为缺失键填默认值 → 原子替换回 setting.conf
config_load_setting || true
config_apply_setting_defaults || true
```

### etc/cont-init.d/30-aria2-conf
```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# shellcheck disable=SC1091
# 根据环境变量动态更新 /config/aria2.conf（仅在容器启动）
set -euo pipefail
. /aria2/scripts/lib/logger.sh
. /aria2/scripts/lib/kvconf.sh
. /aria2/scripts/lib/config.sh

# 路径集中化：由 path.sh/config.sh 初始化的 ARIA2_CONF

# 统一写入回调路径
conf_upsert_kv "${ARIA2_CONF}" on-download-stop "/aria2/scripts/handlers/on_stop.sh"
conf_upsert_kv "${ARIA2_CONF}" on-download-complete "/aria2/scripts/handlers/on_complete.sh"
conf_upsert_kv "${ARIA2_CONF}" on-download-pause "/aria2/scripts/handlers/on_pause.sh"
conf_upsert_kv "${ARIA2_CONF}" on-download-start "/aria2/scripts/handlers/on_start.sh"

# 端口配置
conf_upsert_kv "${ARIA2_CONF}" rpc-listen-port "${PORT:-6800}"
conf_upsert_kv "${ARIA2_CONF}" dht-listen-port "${BTPORT:-32516}"
conf_upsert_kv "${ARIA2_CONF}" listen-port "${BTPORT:-32516}"

# bt-save-metadata
if [[ "${SMD:-true}" = "true" ]]; then
	conf_upsert_kv "${ARIA2_CONF}" bt-save-metadata true
else
	conf_upsert_kv "${ARIA2_CONF}" bt-save-metadata false
fi

# file-allocation（先解析成有效值，避免未绑定变量）
FA_EFF="${FA:-falloc}"
case "${FA_EFF}" in
	falloc|trunc|prealloc|none) FA_VAL="${FA_EFF}" ;;
	*) FA_VAL="falloc" ;;
esac
conf_upsert_kv "${ARIA2_CONF}" file-allocation "${FA_VAL}"

# set cron-restart-a2b
bash /aria2/scripts/utils/cron-restart-a2b.sh


```

### etc/cont-init.d/40-tracker
```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# shellcheck disable=SC1091
# tracker 初始化与定时任务（容器启动时更新 + RPC 定时）
set -euo pipefail
. /aria2/scripts/lib/logger.sh

if [[ "${UT:-true}" = "true" ]]; then
	log_i "容器启动：更新 bt-tracker 至 aria2.conf"
	bash /aria2/scripts/utils/tracker.sh || log_w "tracker 本地更新失败（忽略继续）"
else
	log_i "容器启动：跳过本地 tracker 更新（UT=false）"
fi

if [[ "${RUT:-true}" = "true" ]]; then
	cp /aria2/conf/rpc-tracker1 /etc/crontabs/root
	/usr/sbin/crond
	log_i "已启用每日 05:00 RPC 更新 bt-tracker（RUT=true）"
else
	cp /aria2/conf/rpc-tracker0 /etc/crontabs/root
	log_i "已禁用 RPC 定时更新（RUT=false）"
fi
```

### etc/cont-init.d/50-darkhttpd
```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# 启动 AriaNg web UI（可选）
set -euo pipefail
if [[ "${WEBUI:-true}" = "true" ]]; then
	darkhttpd /www --index index.html --port "${WEBUI_PORT:-8080}" --daemon
fi
```

### etc/cont-init.d/60-permissions
```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# 权限设置：最后执行
set -euo pipefail

chown -R abc:abc /config /downloads || true
chmod a+x /aria2/scripts/lib/* /aria2/scripts/handlers/* /aria2/scripts/utils/* 2>/dev/null || true
```

### etc/cont-init.d/99-custom-folders
```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# 预留：创建自定义目录（用户可通过挂载覆盖本脚本）
set -euo pipefail
exit 0
```

### etc/cont-init.d/99-custom-scripts
```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# 预留：执行自定义脚本（用户可通过挂载覆盖本脚本）
set -euo pipefail
exit 0
```

### etc/services.d/aria2/run
```bash
#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# 启动 aria2 服务
set -euo pipefail

if [[ -n "${SECRET:-}" ]]; then
	SECRET_TOKEN="--rpc-secret=${SECRET}"
fi

exec \
	s6-setuidgid abc aria2c \
	--conf-path=/config/aria2.conf \
	${SECRET_TOKEN:+"${SECRET_TOKEN}"} \
	--disk-cache="${CACHE:-128M}" \
	--quiet="${QUIET:-true}"
```

