#!/usr/bin/env bash
# 改进版本的文件过滤函数 - 解决规则冲突问题

# =============================智能文件过滤（改进版）=============================
# 功能：提供更安全、更可预测的文件过滤逻辑
# 优先级：include-* > exclude-* > keyword > min-size

_delete_exclude_file_improved() {
    if [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]] && [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} || -n ${KEYWORD_FILE} || -n ${EXCLUDE_FILE_REGEX} || -n ${INCLUDE_FILE_REGEX} ]]; then
        log_i "开始智能文件过滤..."
        
        # 统计初始文件数量
        local initial_count=$(find "${SOURCE_PATH}" -type f | wc -l)
        log_i "过滤前文件总数: ${initial_count}"
        
        # 优先级1：include规则（白名单模式，优先级最高）
        if [[ -n "${INCLUDE_FILE}" ]] || [[ -n "${INCLUDE_FILE_REGEX}" ]]; then
            log_i "执行白名单过滤..."
            
            if [[ -n "${INCLUDE_FILE}" ]]; then
                log_i "保留文件类型: ${INCLUDE_FILE}"
                find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
            fi
            
            if [[ -n "${INCLUDE_FILE_REGEX}" ]]; then
                log_i "保留文件模式: ${INCLUDE_FILE_REGEX}"
                find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex "${INCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
            fi
            
            # 白名单模式下，跳过其他过滤规则避免冲突
            log_i "已执行白名单过滤，跳过其他规则以避免冲突"
            
        else
            # 优先级2-5：黑名单模式过滤
            log_i "执行黑名单过滤..."
            
            # 2. 按文件大小过滤
            if [[ -n "${MIN_SIZE}" ]]; then
                log_i "删除小于 ${MIN_SIZE} 的文件"
                find "${SOURCE_PATH}" -type f -size -"${MIN_SIZE}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
            fi
            
            # 3. 按正则排除
            if [[ -n "${EXCLUDE_FILE_REGEX}" ]]; then
                log_i "排除文件模式: ${EXCLUDE_FILE_REGEX}"
                find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex "${EXCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
            fi
            
            # 4. 按文件扩展名排除
            if [[ -n "${EXCLUDE_FILE}" ]]; then
                log_i "排除文件类型: ${EXCLUDE_FILE}"
                find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
            fi
            
            # 5. 按关键词排除
            if [[ -n "${KEYWORD_FILE}" ]]; then
                log_i "排除关键词: ${KEYWORD_FILE}"
                find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*(${KEYWORD_FILE}).*" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
            fi
        fi
        
        # 统计过滤后文件数量
        local final_count=$(find "${SOURCE_PATH}" -type f 2>/dev/null | wc -l)
        local deleted_count=$((initial_count - final_count))
        log_i "过滤完成，删除文件: ${deleted_count}，剩余文件: ${final_count}"
        
        # 如果所有文件都被删除，给出警告
        if [[ ${final_count} -eq 0 ]]; then
            log_w "警告：所有文件都被过滤删除，请检查过滤配置是否过于严格"
            log_w_tee "${CF_LOG}" "任务 ${SOURCE_PATH} 的所有文件都被过滤删除"
        fi
    fi
}

# =============================配置验证函数=============================
# 功能：在执行过滤前验证配置的合理性

_validate_filter_config() {
    local has_include_rules=false
    local has_exclude_rules=false
    local warnings=()
    
    # 检查是否有include规则
    [[ -n "${INCLUDE_FILE}" ]] || [[ -n "${INCLUDE_FILE_REGEX}" ]] && has_include_rules=true
    
    # 检查是否有exclude规则  
    [[ -n "${EXCLUDE_FILE}" ]] || [[ -n "${KEYWORD_FILE}" ]] || [[ -n "${EXCLUDE_FILE_REGEX}" ]] || [[ -n "${MIN_SIZE}" ]] && has_exclude_rules=true
    
    # 规则冲突检查
    if [[ ${has_include_rules} == true ]] && [[ ${has_exclude_rules} == true ]]; then
        warnings+=("同时配置了白名单(include)和黑名单(exclude)规则，白名单将优先生效，黑名单规则将被忽略")
    fi
    
    # 过于宽泛的include规则检查
    if [[ -n "${INCLUDE_FILE}" ]] && [[ $(echo "${INCLUDE_FILE}" | tr '|' '\n' | wc -l) -lt 3 ]]; then
        warnings+=("include-file 规则可能过于严格，只保留很少的文件类型: ${INCLUDE_FILE}")
    fi
    
    # 输出警告
    if [[ ${#warnings[@]} -gt 0 ]]; then
        log_w "过滤配置警告："
        for warning in "${warnings[@]}"; do
            log_w "  - ${warning}"
        done
        log_w "如需了解配置建议，请查看 filter_config_examples.conf"
    fi
}

# =============================使用示例=============================
# 在 clean_up 函数中的调用方式：

clean_up_improved() {
    rm_aria2
    if [[ "${CF}" = "true" ]] && [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]]; then
        log_i_tee "${CF_LOG}" "开始过滤任务路径: ${SOURCE_PATH}"
        _filter_load
        _validate_filter_config  # 验证配置
        _delete_exclude_file_improved  # 执行改进的过滤
        delete_empty_dir
    fi
}
