#!/usr/bin/env bash
# =============================================================================
# Aria2下载停止回调脚本
#
# 功能: 处理下载停止事件，根据配置执行删除、回收或仅清理控制文件
# 回调时机: 当aria2停止/取消一个下载任务时
# 传入参数: GID FILE_NUM FILE_PATH  
# =============================================================================

set -euo pipefail

# 脚本目录
readonly SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# 加载框架库
source "$SCRIPT_DIR/../lib/lib.sh"

# 主处理函数
main() {
    local task_gid="$1"
    local file_num="$2"
    local file_path="$3"
    
    # 初始化脚本环境
    init_lib "/config" "/config/logs"
    
    # 加载配置文件
    if ! load_config "/config/setting.conf"; then
        log_warn "配置文件加载失败，使用默认配置"
    fi
    
    # 检查必需的命令
    require_commands curl jq mv rm mkdir stat
    
    log_info "=== 下载停止处理开始 ==="
    log_info "GID: $task_gid"
    log_info "文件数量: $file_num"
    log_info "文件路径: $file_path"
    
    # 计算路径信息
    if ! compute_paths "$task_gid" "$file_num" "$file_path"; then
        log_error "路径计算失败"
        exit $E_PATH_ERROR
    fi
    
    # 检查源路径是否存在
    # start.sh可能已经删除文件或文件夹，不存在SOURCE_PATH则不进行任何操作
    if [[ ! -d "$SOURCE_PATH" && ! -e "$SOURCE_PATH" ]]; then
        log_info "源路径不存在，可能已被其他脚本处理: $SOURCE_PATH"
        exit 0
    fi
    
    # 执行停止处理逻辑
    process_stopped_task
    
    log_info "=== 下载停止处理结束 ==="
}

# 处理停止的任务
process_stopped_task() {
    # 处理特殊情况
    if [[ "$FILE_NUM" -eq 0 || -z "$FILE_PATH" ]]; then
        log_info "文件数量为0或路径为空，无需处理"
        exit 0
    fi
    
    if [[ "$GET_PATH_INFO" == "error" ]]; then
        log_error "GID:${task_gid} 获取任务路径失败！"
        exit $E_PATH_ERROR
    fi
    
    # 如果任务状态为error，通常不执行删除操作
    if [[ "$TASK_STATUS" == "error" ]]; then
        log_warn "任务状态为错误，跳过删除操作: GID=$task_gid"
        # 仍然处理种子文件和清理控制文件
        process_torrent_file
        clean_aria2_files "$SOURCE_PATH"
        exit 0
    fi
    
    # 根据删除任务配置执行相应操作
    local remove_strategy="${RMTASK:-rmaria}"
    
    log_info "删除策略: $remove_strategy"
    
    case "$remove_strategy" in
        "recycle")
            execute_recycle_operation
            ;;
        "delete") 
            execute_delete_operation
            ;;
        "rmaria")
            execute_rmaria_operation
            ;;
        *)
            log_warn "未知的删除策略: $remove_strategy，使用默认策略 rmaria"
            execute_rmaria_operation
            ;;
    esac
}

# 执行回收操作
execute_recycle_operation() {
    log_info "执行回收操作: 移动文件到回收站"
    
    # 移动到回收站
    if move_to_recycle "$SOURCE_PATH"; then
        log_info "文件已移动到回收站: $SOURCE_PATH"
    else
        log_error "移动到回收站失败: $SOURCE_PATH"
        return $E_FILE_ERROR
    fi
    
    # 处理种子文件
    process_torrent_file
    
    # 清理控制文件
    clean_aria2_files "$SOURCE_PATH"
}

# 执行删除操作
execute_delete_operation() {
    log_info "执行删除操作: 直接删除文件"
    
    # 直接删除文件/目录
    if safe_rm "$SOURCE_PATH"; then
        log_info "文件删除成功: $SOURCE_PATH"
    else
        log_error "文件删除失败: $SOURCE_PATH"
        return $E_FILE_ERROR
    fi
    
    # 处理种子文件
    process_torrent_file
    
    # 清理控制文件
    clean_aria2_files "$SOURCE_PATH"
    
    # 清理空目录
    delete_empty_directories
}

# 执行仅删除控制文件操作
execute_rmaria_operation() {
    log_info "执行rmaria操作: 仅删除.aria2控制文件"
    
    # 处理种子文件
    process_torrent_file
    
    # 仅清理控制文件，保留下载的文件
    clean_aria2_files "$SOURCE_PATH"
}

# 处理种子文件
process_torrent_file() {
    if [[ -n "$TORRENT_FILE" && -f "$TORRENT_FILE" ]]; then
        local torrent_strategy="${TOR:-backup-rename}"
        log_info "处理种子文件: $TORRENT_FILE, 策略: $torrent_strategy"
        
        if ! handle_torrent "$TASK_NAME" "$TORRENT_FILE" "$torrent_strategy"; then
            log_warn "种子文件处理失败，但不影响主流程"
        fi
    else
        log_debug "未找到种子文件或任务非种子下载"
    fi
}

# 删除空目录
delete_empty_directories() {
    local delete_empty_enabled
    delete_empty_enabled=$(parse_bool "${DET:-true}")
    
    if [[ "$delete_empty_enabled" == "true" && -n "$SOURCE_PATH" ]]; then
        log_debug "清理空目录功能已启用"
        local parent_dir
        parent_dir="$(dirname "$SOURCE_PATH")"
        remove_empty_dir "$parent_dir"
    fi
}

# 记录操作统计信息
log_operation_stats() {
    local operation="$1"
    local source_size=""
    
    if [[ -e "$SOURCE_PATH" ]]; then
        source_size=$(get_path_size "$SOURCE_PATH")
        source_size=$(human_readable_size "$source_size")
    fi
    
    log_info "操作统计: 操作=$operation, 文件大小=$source_size, 路径=$SOURCE_PATH"
}

# 安全性检查
safety_check() {
    # 确保不会删除重要的系统目录
    local safe_prefixes=("/downloads" "/config" "/tmp")
    local is_safe=false
    
    for prefix in "${safe_prefixes[@]}"; do
        if [[ "$SOURCE_PATH" == "$prefix"* ]]; then
            is_safe=true
            break
        fi
    done
    
    if [[ "$is_safe" != "true" ]]; then
        log_error "安全检查失败: 路径不在安全范围内 - $SOURCE_PATH"
        exit $E_FILE_ERROR
    fi
    
    # 确保不会删除下载根目录本身
    if [[ "$SOURCE_PATH" == "$DOWNLOAD_PATH" ]]; then
        log_error "安全检查失败: 不能删除下载根目录 - $SOURCE_PATH"
        exit $E_FILE_ERROR
    fi
}

# 错误处理
error_handler() {
    local exit_code=$?
    local line_number=$1
    
    log_error "脚本在第 $line_number 行发生错误，退出码: $exit_code"
    
    # 记录错误时的环境信息
    log_error "错误发生时的环境信息:"
    log_error "  删除策略: ${RMTASK:-未设置}"
    log_error "  任务状态: ${TASK_STATUS:-未设置}"
    log_error "  源路径: ${SOURCE_PATH:-未设置}"
    
    exit $exit_code
}

# 设置错误处理
trap 'error_handler $LINENO' ERR

# 参数验证
if [[ $# -ne 3 ]]; then
    echo "用法: $0 <GID> <FILE_NUM> <FILE_PATH>" >&2
    echo "参数: GID - 任务ID, FILE_NUM - 文件数量, FILE_PATH - 文件路径" >&2
    exit 1
fi

# 设置全局变量供其他模块使用
export TASK_GID="$1"
export FILE_NUM="$2"
export FILE_PATH="$3"

# 执行主函数
main "$@"