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
		log_i "已删除文件: ${SOURCE_PATH}.aria2"
	fi
}

# 删除空目录
# 前提：DET=true 时启用；通常在内容清理后调用以抹掉空层级。
delete_empty_dir() {
	if [[ "${DET}" = "true" ]]; then
		log_i "删除任务中空的文件夹 ..."
		find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
	fi
}

# 内容过滤（BT 多文件）
# 描述：依据过滤规则对 SOURCE_PATH 下的文件进行批量删除，并记录到 CF_LOG；同时删除 .aria2 与可能产生的空目录。
# 限制：仅在 CF=true 且 FILE_NUM>1 且 非下载根目录 情况下执行。
clean_up() {
	rm_aria2
	if [[ "${CF}" = "true" ]] && [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]]; then
		echo -e "$(now) ${INFO} 被过滤文件的任务路径: ${SOURCE_PATH}" | tee -a "${CF_LOG}"
		log_i "删除不需要的文件..."
		_filter_load

		# 删除函数：逐个删除并输出文件名
		_del_and_log() {
			local file="$1"
			if rm -f "${file}"; then
				echo "removed '${file}'" | tee -a "${CF_LOG}"
			fi
		}

		# 文件过滤判断函数：判断文件是否应该被删除
		_should_delete() {
			local file="$1"
			local delete_by_size=false
			local delete_by_exclude=false
			local delete_by_keyword=false
			local delete_by_include=false
			local delete_by_exclude_regex=false
			local delete_by_include_regex=false

			# 1. 检查文件大小 (小于指定大小的删除)
			if [[ -n "${MIN_SIZE}" ]]; then
				local file_size
				file_size=$(stat -c%s "${file}" 2>/dev/null || echo "0")
				local min_bytes
				case "${MIN_SIZE}" in
				*K | *k) min_bytes=$((${MIN_SIZE%[Kk]} * 1024)) ;;
				*M | *m) min_bytes=$((${MIN_SIZE%[Mm]} * 1024 * 1024)) ;;
				*G | *g) min_bytes=$((${MIN_SIZE%[Gg]} * 1024 * 1024 * 1024)) ;;
				*) min_bytes="${MIN_SIZE}" ;;
				esac
				[[ "${file_size}" -lt "${min_bytes}" ]] && delete_by_size=true
			fi

			# 2. 检查排除文件类型 (匹配的删除)
			if [[ -n "${EXCLUDE_FILE}" ]]; then
				if [[ "${file}" =~ \.(${EXCLUDE_FILE})$ ]]; then
					delete_by_exclude=true
				fi
			fi

			# 3. 检查关键词 (包含关键词的删除)
			if [[ -n "${KEYWORD_FILE}" ]]; then
				if [[ "${file}" =~ (${KEYWORD_FILE}) ]]; then
					delete_by_keyword=true
				fi
			fi

			# 4. 检查保留文件类型 (不匹配的删除)
			if [[ -n "${INCLUDE_FILE}" ]]; then
				if [[ ! "${file}" =~ \.(${INCLUDE_FILE})$ ]]; then
					delete_by_include=true
				fi
			fi

			# 5. 检查排除文件正则 (匹配的删除)
			if [[ -n "${EXCLUDE_FILE_REGEX}" ]]; then
				if [[ "${file}" =~ ${EXCLUDE_FILE_REGEX} ]]; then
					delete_by_exclude_regex=true
				fi
			fi

			# 6. 检查保留文件正则 (不匹配的删除)
			if [[ -n "${INCLUDE_FILE_REGEX}" ]]; then
				if [[ ! "${file}" =~ ${INCLUDE_FILE_REGEX} ]]; then
					delete_by_include_regex=true
				fi
			fi

			# 任何一个条件满足就删除
			if [[ "${delete_by_size}" = true ]] || [[ "${delete_by_exclude}" = true ]] ||
				[[ "${delete_by_keyword}" = true ]] || [[ "${delete_by_include}" = true ]] ||
				[[ "${delete_by_exclude_regex}" = true ]] || [[ "${delete_by_include_regex}" = true ]]; then
				return 0 # 应该删除
			else
				return 1 # 不应该删除
			fi
		}

		# 单次遍历所有文件
		while IFS= read -r -d '' file; do
			if _should_delete "${file}"; then
				_del_and_log "${file}"
			fi
		done < <(find "${SOURCE_PATH}" -type f -print0)

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
		log_i "开始移动该任务文件到: ${LOG_GREEN}${TARGET_PATH}${LOG_NC}"
		mkdir -p "${TARGET_PATH}"

		if ! check_space_before_move "${SOURCE_PATH}" "${TARGET_PATH}"; then
			# 将所需/可用空间写入 move.log
			if [[ -n "${REQ_SPACE_BYTES:-}" ]] && [[ -n "${AVAIL_SPACE_BYTES:-}" ]]; then
				local req_g avail_g
				req_g=$(awk "BEGIN {printf \"%.2f\", ${REQ_SPACE_BYTES}/1024/1024/1024}")
				avail_g=$(awk "BEGIN {printf \"%.2f\", ${AVAIL_SPACE_BYTES}/1024/1024/1024}")
				echo -e "$(now) [ERROR] 目标磁盘空间不足，移动失败。所需空间:${req_g} GB, 可用空间:${avail_g} GB. 源:${SOURCE_PATH} -> 目标:${TARGET_PATH}" >>"${MOVE_LOG}"
			fi
			local FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
			local SOURCE_NAME
			SOURCE_NAME=$(basename "${SOURCE_PATH}")
			log_w "目标磁盘空间不足，尝试将任务移动到: ${FAIL_DIR}"
			mkdir -p "${FAIL_DIR}"
			if mv -f "${SOURCE_PATH}" "${FAIL_DIR}"; then
				log_i "因目标磁盘空间不足，已将文件移动至: ${FAIL_DIR}/${SOURCE_NAME}"
				echo -e "$(now) [INFO] 因目标磁盘空间不足，已将文件移动至: ${FAIL_DIR}/${SOURCE_NAME}" >>"${MOVE_LOG}"
			else
				log_e "移动到 ${FAIL_DIR} 失败: ${SOURCE_PATH}"
				echo -e "$(now) [ERROR] 移动到 ${FAIL_DIR} 失败: ${SOURCE_PATH}" >>"${MOVE_LOG}"
			fi
			return 1
		fi

		if mv -f "${SOURCE_PATH}" "${TARGET_PATH}"; then
			log_i "已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}"
			echo -e "$(now) [INFO] 已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}" >>"${MOVE_LOG}"
		else
			log_e "文件移动失败: ${SOURCE_PATH}"
			echo -e "$(now) [ERROR] 文件移动失败: ${SOURCE_PATH}" >>"${MOVE_LOG}"
			local FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
			local SOURCE_NAME
			SOURCE_NAME=$(basename "${SOURCE_PATH}")
			mkdir -p "${FAIL_DIR}"
			# Docker环境下的基础检查：确保文件仍然存在
			if [[ ! -e "${SOURCE_PATH}" ]]; then
				log_w "源文件不存在，无法移动: ${SOURCE_PATH}"
				echo -e "$(now) [WARN] 源文件不存在，无法移动: ${SOURCE_PATH}" >>"${MOVE_LOG}"
			elif mv -f "${SOURCE_PATH}" "${FAIL_DIR}"; then
				log_i "已将文件移动至: ${FAIL_DIR}/${SOURCE_NAME}"
				echo -e "$(now) [INFO] 已将文件移动至: ${FAIL_DIR}/${SOURCE_NAME}" >>"${MOVE_LOG}"
			else
				log_e "移动到 ${FAIL_DIR} 依然失败: ${SOURCE_PATH}"
				echo -e "$(now) [ERROR] 移动到 ${FAIL_DIR} 依然失败: ${SOURCE_PATH}" >>"${MOVE_LOG}"
			fi
		fi
	fi
}

# 删除任务文件
# 描述：用于 `remove-task=delete` 场景，删除 SOURCE_PATH 并记录日志。
delete_file() {
	TASK_TYPE=": 删除任务文件"
	print_delete_info
	log_i "下载已停止，开始删除文件..."
	if rm -rf "${SOURCE_PATH}"; then
		log_i "已删除文件: ${SOURCE_PATH}"
		echo -e "$(now) [INFO] 文件删除成功: ${SOURCE_PATH}" >>"${DELETE_LOG}"
	else
		log_e "文件删除失败: ${SOURCE_PATH}"
		echo -e "$(now) [ERROR] 文件删除失败: ${SOURCE_PATH}" >>"${DELETE_LOG}"
	fi
}

# 移动至回收站
# 描述：用于 `remove-task=recycle` 场景，移动 SOURCE_PATH 到 TARGET_PATH；失败则改为直接删除。
move_recycle() {
	TASK_TYPE=": 移动任务文件至回收站"
	print_task_info
	log_i "开始移动至回收站: ${LOG_GREEN}${TARGET_PATH}${LOG_NC}"
	mkdir -p "${TARGET_PATH}"
	if mv -f "${SOURCE_PATH}" "${TARGET_PATH}"; then
		log_i "已移至回收站: ${SOURCE_PATH} -> ${TARGET_PATH}"
		echo -e "$(now) [INFO] 成功移动文件到回收站: ${SOURCE_PATH} -> ${TARGET_PATH}" >>"${RECYCLE_LOG}"
	else
		log_e "移动文件到回收站失败，改为直接删除: ${SOURCE_PATH}"
		rm -rf "${SOURCE_PATH}" || true
		echo -e "$(now) [ERROR] 移动文件到回收站失败: ${SOURCE_PATH}" >>"${RECYCLE_LOG}"
	fi
}
