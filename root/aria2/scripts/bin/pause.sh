#!/usr/bin/env bash
# =============================================================================
# Aria2下载暂停回调脚本
#
# 功能: 处理下载暂停事件，根据配置决定是否移动未完成的文件
# 回调时机: 当aria2暂停一个下载任务时
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
    
    log_info "=== 下载暂停处理开始 ==="
    log_info "GID: $task_gid"
    log_info "文件数量: $file_num"
    log_info "文件路径: $file_path"
    
    # 检查是否启用暂停后移动功能
    local move_paused_enabled
    move_paused_enabled=$(parse_bool "${MPT:-false}")
    
    if [[ "$move_paused_enabled" != "true" ]]; then
        log_info "暂停后移动功能已禁用，无需处理"
        exit 0
    fi
    
    # 计算路径信息
    if ! compute_paths "$task_gid" "$file_num" "$file_path"; then
        log_error "路径计算失败"
        exit $E_PATH_ERROR
    fi
    
    # 执行暂停处理逻辑
    process_paused_task
    
    log_info "=== 下载暂停处理结束 ==="
}

# 处理暂停的任务
process_paused_task() {
    log_info "处理暂停任务，移动部分下载的文件"
    
    # 处理特殊情况
    if [[ "$FILE_NUM" -eq 0 || -z "$FILE_PATH" ]]; then
        log_info "文件数量为0或路径为空，无需处理"
        exit 0
    fi
    
    if [[ "$GET_PATH_INFO" == "error" ]]; then
        log_error "GID:${task_gid} 获取任务路径失败！"
        exit $E_PATH_ERROR
    fi
    
    # 检查源文件是否存在
    if [[ ! -e "$SOURCE_PATH" ]]; then
        log_warn "源路径不存在，可能任务尚未开始下载: $SOURCE_PATH"
        exit 0
    fi
    
    # 执行移动操作
    execute_paused_move
    
    # 处理种子文件
    process_torrent_file
}

# 执行暂停文件移动
execute_paused_move() {
    log_info "开始移动暂停的文件到完成目录"
    
    # 设置完成目录为目标
    set_completed_target
    
    # 重新计算目标路径
    if ! calculate_target_path; then
        log_error "目标路径计算失败"
        return $E_PATH_ERROR
    fi
    
    # 强制启用移动模式进行移动
    export MOVE="true"
    
    # 执行移动操作
    if safe_mv "$SOURCE_PATH" "$TARGET_PATH"; then
        log_info "暂停文件移动成功: $SOURCE_PATH -> $TARGET_PATH"
        
        # 清理控制文件
        clean_aria2_files "$SOURCE_PATH"
        
        # 删除空目录
        delete_empty_directories
        
        # 记录统计信息
        log_paused_move_stats
        
    else
        log_error "暂停文件移动失败"
        return $E_FILE_ERROR
    fi
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

# 记录暂停移动统计信息
log_paused_move_stats() {
    local source_size=""
    local download_progress=""
    
    if [[ -e "$TARGET_PATH/$(basename "$SOURCE_PATH")" ]]; then
        source_size=$(get_path_size "$TARGET_PATH/$(basename "$SOURCE_PATH")")
        source_size=$(human_readable_size "$source_size")
    fi
    
    log_info "暂停移动统计: 文件大小=$source_size, 原路径=$SOURCE_PATH, 新路径=$TARGET_PATH"
    
    # 检查是否存在.aria2控制文件以判断下载进度
    local aria2_file="${SOURCE_PATH}.aria2"
    if [[ -f "$aria2_file" ]]; then
        log_info "检测到控制文件，任务可能未完全下载完成"
    fi
}

# 检查任务是否适合移动
is_task_suitable_for_move() {
    # 检查任务状态
    if [[ "$TASK_STATUS" == "error" ]]; then
        log_warn "任务状态为错误，可能不适合移动: GID=$task_gid"
        return 1
    fi
    
    # 检查文件大小，过小的文件可能是刚开始下载
    local min_size_threshold=$((1024 * 1024))  # 1MB
    local current_size
    current_size=$(get_path_size "$SOURCE_PATH")
    
    if [[ $current_size -lt $min_size_threshold ]]; then
        log_debug "文件大小过小（< 1MB），可能刚开始下载: $(human_readable_size $current_size)"
        return 1
    fi
    
    return 0
}

# 备份.aria2控制文件
backup_aria2_control_file() {
    local aria2_file="${SOURCE_PATH}.aria2"
    
    if [[ -f "$aria2_file" ]]; then
        local backup_dir="$TARGET_PATH/.aria2_backup"
        local backup_file="$backup_dir/$(basename "$SOURCE_PATH").aria2.$(date +%Y%m%d_%H%M%S)"
        
        # 创建备份目录
        ensure_dir "$backup_dir"
        
        if cp "$aria2_file" "$backup_file"; then
            log_info "控制文件已备份: $aria2_file -> $backup_file"
            log_info "提示: 如需恢复下载，可将备份文件重命名并移回原位置"
        else
            log_warn "控制文件备份失败: $aria2_file"
        fi
    fi
}

# 创建暂停信息文件
create_pause_info_file() {
    local info_file="$TARGET_PATH/.aria2_pause_info"
    
    cat > "$info_file" << EOF
# Aria2 暂停任务信息
# 生成时间: $(date_time)
# 
任务GID: $TASK_GID
文件数量: $FILE_NUM
原始路径: $FILE_PATH
源路径: $SOURCE_PATH
目标路径: $TARGET_PATH
任务名称: $TASK_NAME
任务状态: $TASK_STATUS
下载目录: $DOWNLOAD_DIR
种子文件: $TORRENT_FILE

# 说明: 该文件记录了暂停任务的基本信息，可用于故障排查
EOF

    log_debug "创建暂停信息文件: $info_file"
}

# 错误处理
error_handler() {
    local exit_code=$?
    local line_number=$1
    
    log_error "脚本在第 $line_number 行发生错误，退出码: $exit_code"
    
    # 记录错误时的环境信息
    log_error "错误发生时的环境信息:"
    log_error "  移动暂停任务: ${MPT:-未设置}"
    log_error "  任务状态: ${TASK_STATUS:-未设置}"
    log_error "  源路径: ${SOURCE_PATH:-未设置}"
    log_error "  目标路径: ${TARGET_PATH:-未设置}"
    
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