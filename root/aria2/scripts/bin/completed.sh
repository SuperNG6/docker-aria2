#!/usr/bin/env bash
# =============================================================================
# Aria2下载完成回调脚本
# 
# 功能: 处理下载完成的任务，包括文件移动、种子处理等
# 回调时机: 当aria2完成一个下载任务时
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
    require_commands curl jq mv rm mkdir stat df
    
    log_info "=== 下载完成处理开始 ==="
    log_info "GID: $task_gid"
    log_info "文件数量: $file_num"
    log_info "文件路径: $file_path"
    
    # 计算路径信息
    if ! compute_paths "$task_gid" "$file_num" "$file_path"; then
        log_error "路径计算失败"
        exit $E_PATH_ERROR
    fi
    
    # 处理特殊情况
    if [[ "$file_num" -eq 0 || -z "$file_path" ]]; then
        log_info "文件数量为0或路径为空，无需处理"
        exit 0
    fi
    
    if [[ "$GET_PATH_INFO" == "error" ]]; then
        log_error "GID:${task_gid} 获取任务路径失败！"
        exit $E_PATH_ERROR
    fi
    
    # 执行主要处理逻辑
    process_completed_task
    
    # 处理种子文件
    process_torrent_file
    
    log_info "=== 下载完成处理结束 ==="
}

# 处理完成的任务
process_completed_task() {
    # 检查移动配置
    local move_enabled
    move_enabled=$(parse_bool "${MOVE:-false}")
    
    if [[ "$move_enabled" == "false" ]]; then
        log_info "文件移动功能已禁用，仅清理控制文件"
        clean_aria2_files "$SOURCE_PATH"
        return 0
    fi
    
    # dmof模式：单文件且在根目录下载时不移动
    if [[ "${MOVE:-false}" == "dmof" && "$DOWNLOAD_DIR" == "$DOWNLOAD_PATH" && "$file_num" -eq 1 ]]; then
        log_info "dmof模式：根目录单文件下载，不执行移动"
        clean_aria2_files "$SOURCE_PATH"
        return 0
    fi
    
    # 执行文件移动
    if [[ "$move_enabled" == "true" || "${MOVE:-false}" == "dmof" ]]; then
        log_info "开始移动文件到完成目录"
        
        # 设置完成目录为目标
        set_completed_target
        
        # 重新计算目标路径
        if ! calculate_target_path; then
            log_error "目标路径计算失败"
            return $E_PATH_ERROR
        fi
        
        # 执行移动操作
        if safe_mv "$SOURCE_PATH" "$TARGET_PATH"; then
            log_info "文件移动成功: $SOURCE_PATH -> $TARGET_PATH"
            
            # 清理控制文件
            clean_aria2_files "$SOURCE_PATH"
            
            # 删除空目录
            delete_empty_directories
        else
            log_error "文件移动失败"
            return $E_FILE_ERROR
        fi
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

# 错误处理
error_handler() {
    local exit_code=$?
    local line_number=$1
    
    log_error "脚本在第 $line_number 行发生错误，退出码: $exit_code"
    
    # 清理工作（如果需要）
    # cleanup_on_error
    
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