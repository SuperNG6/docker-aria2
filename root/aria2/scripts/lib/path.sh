#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154,SC2034
# 路径处理：获取任务路径、目标路径等

if [[ -n "${_ARIA2_LIB_PATH_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_PATH_SH_LOADED=1

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
