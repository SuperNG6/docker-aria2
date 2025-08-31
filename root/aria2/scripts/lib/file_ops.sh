#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2312
# 文件操作：删除.aria2、清理内容、移动/删除/回收站

if [[ -n "${_ARIA2_LIB_FILE_OPS_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_FILE_OPS_SH_LOADED=1

. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/path.sh
. /aria2/scripts/lib/torrent.sh

# 任务信息显示函数
print_task_info() {
	echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${TASK_TYPE} ${LOG_NC}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} ${DOWNLOAD_PATH}
${LOG_PURPLE}任务位置:${LOG_NC} ${SOURCE_PATH}
${LOG_PURPLE}首个文件位置:${LOG_NC} ${FILE_PATH}
${LOG_PURPLE}任务文件数量:${LOG_NC} ${FILE_NUM}
${LOG_PURPLE}移动至目标文件夹:${LOG_NC} ${TARGET_PATH}
-----------------------------------------------------------------------------------------------------------------------
"
}

print_delete_info() {
	echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${TASK_TYPE} ${LOG_NC}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} ${DOWNLOAD_PATH}
${LOG_PURPLE}任务位置:${LOG_NC} ${SOURCE_PATH}
${LOG_PURPLE}首个文件位置:${LOG_NC} ${FILE_PATH}
${LOG_PURPLE}任务文件数量:${LOG_NC} ${FILE_NUM}
-----------------------------------------------------------------------------------------------------------------------
"
}

# 读取过滤配置
# 描述：从 /config/文件过滤.conf 中加载一组过滤键，用于内容清理。
# 输出：设置 MIN_SIZE/INCLUDE_FILE/EXCLUDE_FILE/KEYWORD_FILE/INCLUDE_FILE_REGEX/EXCLUDE_FILE_REGEX 六个变量
_filter_load() {
	# 直接使用集中变量 FILTER_FILE
	MIN_SIZE=$(kv_get "${FILTER_FILE}" min-size)
	INCLUDE_FILE=$(kv_get "${FILTER_FILE}" include-file)
	EXCLUDE_FILE=$(kv_get "${FILTER_FILE}" exclude-file)
	KEYWORD_FILE=$(kv_get "${FILTER_FILE}" keyword-file)
	INCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" include-file-regex)
	EXCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" exclude-file-regex)
}

# 删除 .aria2 控制文件
# 描述：若存在与当前任务 SOURCE_PATH 对应的 .aria2 控制文件，则删除之。
rm_aria2() {
	if [[ -e "${SOURCE_PATH}.aria2" ]]; then
		rm -f "${SOURCE_PATH}.aria2"
		echo -e "$(now) ${INFO} 已删除文件: ${SOURCE_PATH}.aria2"
	fi
}

# 删除空目录
# 前提：DET=true 时启用；通常在内容清理后调用以抹掉空层级。
delete_empty_dir() {
	if [[ "${DET}" = "true" ]]; then
		echo -e "$(now) ${INFO} 删除任务中空的文件夹 ..."
		find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
	fi
}

# 内容过滤（BT 多文件）
# 描述：依据过滤规则对 SOURCE_PATH 下的文件进行批量删除，并记录到 CF_LOG；同时删除 .aria2 与可能产生的空目录。
# 限制：仅在 CF=true 且 FILE_NUM>1 且 非下载根目录 情况下执行。
clean_up() {
	rm_aria2
	if [[ "${CF}" = "true" ]] && [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]]; then
		log_i_tee "${CF_LOG}" "被过滤文件的任务路径: ${SOURCE_PATH}"
		_filter_load
		
		# 与原项目完全一致的实现：只有在有规则时才执行
		if [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} || -n ${KEYWORD_FILE} || -n ${EXCLUDE_FILE_REGEX} || -n ${INCLUDE_FILE_REGEX} ]]; then
			log_i_tee "${CF_LOG}" "删除不需要的文件..."
			[[ -n "${MIN_SIZE}" ]] && find "${SOURCE_PATH}" -type f -size -"${MIN_SIZE}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
			[[ -n "${EXCLUDE_FILE}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
			[[ -n "${KEYWORD_FILE}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*(${KEYWORD_FILE}).*" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
			[[ -n "${INCLUDE_FILE}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
			[[ -n "${EXCLUDE_FILE_REGEX}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex "${EXCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
			[[ -n "${INCLUDE_FILE_REGEX}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex "${INCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
		fi

		delete_empty_dir
	fi
}

# 移动文件
# 策略：
#   - MOVE=false 仅清理 .aria2，不移动文件；
#   - MOVE=dmof 根目录单文件不移动；
#   - MOVE=true/dmof 执行内容清理 -> 空间预检 -> 移动；失败时搬运至 /downloads/move-failed 并记录日志。
# 返回：0 成功或无需移动；非 0 表示失败（通常为空间不足）。
move_file() {
	# MOVE=false: 仅删除 .aria2 即返回；MOVE=dmof: 根目录单文件不移动；MOVE=true/dmof: 执行移动
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
		echo -e "$(now) ${INFO} 开始移动该任务文件到: ${LOG_GREEN}${TARGET_PATH}${LOG_NC}"
		mkdir -p "${TARGET_PATH}"

		if ! check_space_before_move "${SOURCE_PATH}" "${TARGET_PATH}"; then
			# 将所需/可用空间写入 move.log
			if [[ -n "${REQ_SPACE_BYTES:-}" ]] && [[ -n "${AVAIL_SPACE_BYTES:-}" ]]; then
				local req_g avail_g
				req_g=$(awk "BEGIN {printf \"%.2f\", ${REQ_SPACE_BYTES}/1024/1024/1024}")
				avail_g=$(awk "BEGIN {printf \"%.2f\", ${AVAIL_SPACE_BYTES}/1024/1024/1024}")
				log_e_tee "${MOVE_LOG}" "目标磁盘空间不足！无法移动文件。所需空间: ${req_g} GB, 目标可用空间: ${avail_g} GB. 源:${SOURCE_PATH} -> 目标:${TARGET_PATH}"
			fi
			local FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
			echo -e "$(now) ${WARN} 尝试将任务移动到: ${FAIL_DIR}"
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

		mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
		local MOVE_EXIT_CODE=$?
		if [[ ${MOVE_EXIT_CODE} -eq 0 ]]; then
			log_i_tee "${MOVE_LOG}" "已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}"
		else
			log_e_tee "${MOVE_LOG}" "文件移动失败: ${SOURCE_PATH}"
			local FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
			mkdir -p "${FAIL_DIR}"
			# Docker环境下的基础检查：确保文件仍然存在
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

# 删除任务文件
# 描述：用于 `remove-task=delete` 场景，删除 SOURCE_PATH 并记录日志。
delete_file() {
	TASK_TYPE=": 删除任务文件"
	print_delete_info
	echo -e "$(now) ${INFO} 下载已停止，开始删除文件..."
	rm -rf "${SOURCE_PATH}"
	local DELETE_EXIT_CODE=$?
	if [[ ${DELETE_EXIT_CODE} -eq 0 ]]; then
		log_i_tee "${DELETE_LOG}" "已删除文件: ${SOURCE_PATH}"
	else
		log_e_tee "${DELETE_LOG}" "delete failed: ${SOURCE_PATH}"
	fi
}

# 移动至回收站
# 描述：用于 `remove-task=recycle` 场景，移动 SOURCE_PATH 到 TARGET_PATH；失败则改为直接删除。
move_recycle() {
	TASK_TYPE=": 移动任务文件至回收站"
	print_task_info
	echo -e "$(now) ${INFO} 开始移动已下载的任务至回收站 ${LOG_GREEN}${TARGET_PATH}${LOG_NC}"
	mkdir -p "${TARGET_PATH}"
	mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
	local RECYCLE_EXIT_CODE=$?
	if [[ ${RECYCLE_EXIT_CODE} -eq 0 ]]; then
		log_i_tee "${RECYCLE_LOG}" "已移至回收站: ${SOURCE_PATH} -> ${TARGET_PATH}"
	else
		log_e_tee "${RECYCLE_LOG}" "移动文件到回收站失败: ${SOURCE_PATH}"
		echo -e "$(now) ${INFO} 已删除文件: ${SOURCE_PATH}"
		rm -rf "${SOURCE_PATH}"
	fi
}
