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
        log_i "开始移动该任务文件到: ${LOG_GREEN}${TARGET_PATH}${LOG_NC}"
        mkdir -p "${TARGET_PATH}"

        # 移动前检查磁盘空间（使用common.sh中的统一函数）
        if ! check_space_before_move "${SOURCE_PATH}" "${TARGET_PATH}"; then
            # 空间不足的处理
            if [[ -n "${REQ_SPACE_BYTES:-}" ]] && [[ -n "${AVAIL_SPACE_BYTES:-}" ]]; then
                local req_g avail_g
                req_g=$(awk "BEGIN {printf \"%.2f\", ${REQ_SPACE_BYTES}/1024/1024/1024}")
                avail_g=$(awk "BEGIN {printf \"%.2f\", ${AVAIL_SPACE_BYTES}/1024/1024/1024}")
                log_e_tee "${MOVE_LOG}" "目标磁盘空间不足，移动失败。所需空间:${req_g} GB, 可用空间:${avail_g} GB. 源:${SOURCE_PATH} -> 目标:${TARGET_PATH}"
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
    log_i "开始移动已下载的任务至回收站 ${LOG_GREEN}${TARGET_PATH}${LOG_NC}"
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
