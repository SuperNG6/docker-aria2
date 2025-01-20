#!/usr/bin/env bash
#====================================================================
# functions.sh
# 核心业务函数库
#====================================================================

source "$(dirname "$0")/logging.sh"
source "$(dirname "$0")/config.sh"

#===================== 文件操作相关函数 =====================

# 移动文件到目标目录
move_file() {
    # 如果move配置为false,仅删除.aria2文件后退出
    if [[ "${MOVE}" == "false" ]]; then
        remove_aria2_file "${SOURCE_PATH}"
        return
    fi

    # 单文件下载且在根目录时的特殊处理
    if [[ "${MOVE}" == "dmof" && "${DOWNLOAD_DIR}" == "${DOWNLOAD_PATH}" && ${FILE_NUM} -eq 1 ]]; then
        remove_aria2_file "${SOURCE_PATH}"
        return
    fi

    # 正常的移动处理
    if [[ "${MOVE}" == "true" || "${MOVE}" == "dmof" ]]; then
        TASK_TYPE=": 移动任务文件"
        print_task_info "${TASK_TYPE}" "${SOURCE_PATH}" "${FILE_PATH}" "${FILE_NUM}" "${TARGET_PATH}"
        
        # 清理工作
        clean_up
        
        # 开始移动文件
        log_info "开始移动该任务文件到: ${TARGET_PATH}"
        mkdir -p "${TARGET_PATH}"
        
        if mv -f "${SOURCE_PATH}" "${TARGET_PATH}"; then
            log_info "已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}"
            echo "$(get_datetime) [INFO] 已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}" >> "${MOVE_LOG}"
        else
            log_error "文件移动失败: ${SOURCE_PATH}"
            echo "$(get_datetime) [ERROR] 文件移动失败: ${SOURCE_PATH}" >> "${MOVE_LOG}"
            
            # 移动失败后的备用处理
            handle_move_failure "${SOURCE_PATH}"
        fi
    fi
}

# 处理移动失败的情况
handle_move_failure() {
    local source_path="$1"
    local fail_dir="${DOWNLOAD_PATH}/move-failed"
    
    mkdir -p "${fail_dir}"
    if mv -f "${source_path}" "${fail_dir}"; then
        log_info "已将文件移动至备用文件夹: ${source_path} -> ${fail_dir}"
        echo "$(get_datetime) [INFO] 已将文件移动至备用文件夹: ${source_path} -> ${fail_dir}" >> "${MOVE_LOG}"
    else
        log_error "移动到备用文件夹依然失败: ${source_path}"
        echo "$(get_datetime) [ERROR] 移动到备用文件夹依然失败: ${source_path}" >> "${MOVE_LOG}"
    fi
}

# 删除文件
delete_file() {
    TASK_TYPE=": 删除任务文件"
    print_task_info "${TASK_TYPE}" "${SOURCE_PATH}" "${FILE_PATH}" "${FILE_NUM}"
    
    log_info "下载已停止，开始删除文件..."
    if rm -rf "${SOURCE_PATH}"; then
        log_info "已删除文件: ${SOURCE_PATH}"
        echo "$(get_datetime) [INFO] 文件删除成功: ${SOURCE_PATH}" >> "${DELETE_LOG}"
    else
        log_error "delete failed: ${SOURCE_PATH}"
        echo "$(get_datetime) [ERROR] 文件删除失败: ${SOURCE_PATH}" >> "${DELETE_LOG}"
    fi
}

# 移动文件到回收站
move_to_recycle() {
    TASK_TYPE=": 移动任务文件至回收站"
    print_task_info "${TASK_TYPE}" "${SOURCE_PATH}" "${FILE_PATH}" "${FILE_NUM}" "${TARGET_PATH}"
    
    log_info "开始移动已下载的任务至回收站 ${TARGET_PATH}"
    mkdir -p "${TARGET_PATH}"
    
    if mv -f "${SOURCE_PATH}" "${TARGET_PATH}"; then
        log_info "已移至回收站: ${SOURCE_PATH} -> ${TARGET_PATH}"
        echo "$(get_datetime) [INFO] 成功移动文件到回收站: ${SOURCE_PATH} -> ${TARGET_PATH}" >> "${RECYCLE_LOG}"
    else
        log_error "移动文件到回收站失败: ${SOURCE_PATH}"
        log_info "已删除文件: ${SOURCE_PATH}"
        rm -rf "${SOURCE_PATH}"
        echo "$(get_datetime) [ERROR] 移动文件到回收站失败: ${SOURCE_PATH}" >> "${RECYCLE_LOG}"
    fi
}

#===================== 清理相关函数 =====================

# 删除.aria2控制文件
remove_aria2_file() {
    local filepath="$1"
    if [[ -e "${filepath}.aria2" ]]; then
        rm -f "${filepath}.aria2"
        log_info "已删除文件: ${filepath}.aria2"
    fi
}

# 删除空目录
remove_empty_dirs() {
    if [[ "${DET}" == "true" ]]; then
        log_info "删除任务中空的文件夹 ..."
        find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
    fi
}

# 删除不需要的文件
delete_excluded_files() {
    if [[ ${FILE_NUM} -gt 1 && "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]] && 
       [[ -n "${MIN_SIZE}" || -n "${INCLUDE_FILE}" || -n "${EXCLUDE_FILE}" || 
          -n "${KEYWORD_FILE}" || -n "${EXCLUDE_FILE_REGEX}" || -n "${INCLUDE_FILE_REGEX}" ]]; then
        
        log_info "删除不需要的文件..."
        
        # 按大小过滤
        [[ -n "${MIN_SIZE}" ]] && find "${SOURCE_PATH}" -type f -size -"${MIN_SIZE}" -print0 | 
            xargs -0 rm -vf | tee -a "${FILTER_LOG}"
            
        # 按扩展名过滤(排除)
        [[ -n "${EXCLUDE_FILE}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended \
            -iregex ".*\.(${EXCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${FILTER_LOG}"
            
        # 按关键词过滤
        [[ -n "${KEYWORD_FILE}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended \
            -iregex ".*(${KEYWORD_FILE}).*" -print0 | xargs -0 rm -vf | tee -a "${FILTER_LOG}"
            
        # 按扩展名过滤(包含)
        [[ -n "${INCLUDE_FILE}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended \
            ! -iregex ".*\.(${INCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${FILTER_LOG}"
            
        # 正则表达式过滤(排除)
        [[ -n "${EXCLUDE_FILE_REGEX}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended \
            -iregex "${EXCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${FILTER_LOG}"
            
        # 正则表达式过滤(包含)
        [[ -n "${INCLUDE_FILE_REGEX}" ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended \
            ! -iregex "${INCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${FILTER_LOG}"
    fi
}

# 清理操作
clean_up() {
    remove_aria2_file "${SOURCE_PATH}"
    if [[ "${CF}" == "true" && ${FILE_NUM} -gt 1 && "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]]; then
        log_info "被过滤文件的任务路径: ${SOURCE_PATH}" | tee -a "${FILTER_LOG}"
        delete_excluded_files
        remove_empty_dirs
    fi
}

#===================== 种子文件处理 =====================

# 处理种子文件
handle_torrent() {
    case "${TOR}" in
        "retain")
            return
            ;;
        "delete")
            log_info "已删除种子文件: ${TORRENT_FILE}"
            rm -f "${TORRENT_FILE}"
            ;;
        "rename")
            log_info "已删除种子文件: ${TORRENT_FILE}"
            mv -f "${TORRENT_FILE}" "${TASK_NAME}.torrent"
            ;;
        "backup")
            log_info "备份种子文件: ${TORRENT_FILE}"
            mv -vf "${TORRENT_FILE}" "${BAK_TORRENT_DIR}"
            ;;
        "backup-rename")
            log_info "重命名并备份种子文件: ${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
            mv -f "${TORRENT_FILE}" "${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
            ;;
    esac
}

# 检查并处理种子文件
check_torrent() {
    [[ -e "${TORRENT_FILE}" ]] && handle_torrent
}

#===================== 路径处理函数 =====================

# 获取目标路径
get_target_path() {
    local relative_path="${SOURCE_PATH#"${DOWNLOAD_PATH}/"}"
    TARGET_PATH="${TARGET_DIR}/$(dirname "${relative_path}")"
    
    # 检查路径有效性
    if [[ "${TARGET_PATH}" == "${TARGET_DIR}//" ]]; then
        GET_PATH_INFO="error"
        return
    elif [[ "${TARGET_PATH}" == "${TARGET_DIR}/." ]]; then
        TARGET_PATH="${TARGET_DIR}"
    fi
}

# 获取最终路径
get_final_path() { 
    [[ -z "${FILE_PATH}" ]] && return
    
    # 处理多文件或非根目录的单文件BT下载任务
    if [[ ${FILE_NUM} -gt 1 || "$(dirname "${FILE_PATH}")" != "${DOWNLOAD_DIR}" ]]; then
        RELATIVE_PATH="${FILE_PATH#"${DOWNLOAD_DIR}/"}"
        TASK_NAME="${RELATIVE_PATH%%/*}"
        SOURCE_PATH="${DOWNLOAD_DIR}/${TASK_NAME}"
        get_target_path
        COMPLETED_DIR="${TARGET_PATH}/${TASK_NAME}"
        return
    fi
    
    # 处理单文件任务
    if [[ ${FILE_NUM} -eq 1 ]]; then
        SOURCE_PATH="${FILE_PATH}"
        RELATIVE_PATH="${FILE_PATH#"${DOWNLOAD_DIR}/"}"
        TASK_NAME="${RELATIVE_PATH%.*}"
        get_target_path
    fi
}