#!/usr/bin/env bash
# =============================================================================
# Aria2下载开始回调脚本
#
# 功能: 处理下载开始事件，主要用于检测重复任务并清理
# 回调时机: 当aria2开始一个下载任务时  
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
    
    log_info "=== 下载开始处理 ==="
    log_info "GID: $task_gid"
    log_info "文件数量: $file_num"  
    log_info "文件路径: $file_path"
    
    # 计算路径信息
    if ! compute_paths "$task_gid" "$file_num" "$file_path"; then
        log_error "路径计算失败"
        exit $E_PATH_ERROR
    fi
    
    # 检查是否启用重复任务检测
    local remove_repeat_enabled
    remove_repeat_enabled=$(parse_bool "${RRT:-true}")
    
    if [[ "$remove_repeat_enabled" == "true" ]]; then
        check_and_remove_repeat_task
    else
        log_debug "重复任务检测已禁用"
    fi
    
    log_info "=== 下载开始处理完成 ==="
}

# 检查并移除重复任务
check_and_remove_repeat_task() {
    log_debug "开始检查重复任务"
    
    # aria2开始任务时，单文件不会传递FILE_PATH，磁力FILE_NUM为0
    # TASK_STATUS为error时，多为存在.aria2控制文件，任务文件已存在
    if [[ "$FILE_NUM" -eq 0 || -z "$FILE_PATH" ]]; then
        log_debug "文件数量为0或路径为空，跳过重复检测"
        exit 0
    fi
    
    if [[ "$GET_PATH_INFO" == "error" ]]; then
        log_error "GID:${task_gid} 获取任务路径失败！"
        exit $E_PATH_ERROR
    fi
    
    # 检查完成目录是否存在相同任务
    set_completed_target
    local completed_task_path="$COMPLETED_DIR"
    
    # 对于多文件任务，检查具体的任务目录
    if [[ "$FILE_NUM" -gt 1 && -n "$TASK_NAME" ]]; then
        completed_task_path="$COMPLETED_DIR/$TASK_NAME"
    fi
    
    # 如果完成目录中存在该任务且任务状态不是error，则删除重复任务
    if [[ -d "$completed_task_path" && "$TASK_STATUS" != "error" ]]; then
        log_warn "发现目标文件夹已存在当前任务: $completed_task_path"
        log_warn "正在删除该任务，并清除相关文件: $SOURCE_PATH"
        
        # 执行重复任务清理
        remove_repeat_task_files
        
        # 通过RPC删除任务
        if ! rpc_remove_task "$task_gid"; then
            log_error "RPC删除任务失败: $task_gid"
            exit $E_RPC_ERROR
        fi
        
        log_info "重复任务清理完成"
        exit 0
    else
        log_debug "未发现重复任务"
    fi
}

# 清理重复任务的文件
remove_repeat_task_files() {
    if [[ -z "$SOURCE_PATH" ]]; then
        log_warn "源路径为空，跳过文件清理"
        return 0
    fi
    
    # 清理aria2控制文件
    clean_aria2_files "$SOURCE_PATH"
    
    # 删除任务文件/目录
    if [[ -e "$SOURCE_PATH" ]]; then
        if safe_rm "$SOURCE_PATH"; then
            log_info "重复任务文件删除成功: $SOURCE_PATH"
        else
            log_error "重复任务文件删除失败: $SOURCE_PATH"
        fi
    fi
    
    # 清理可能的空目录
    local parent_dir
    parent_dir="$(dirname "$SOURCE_PATH")"
    if [[ "$parent_dir" != "$DOWNLOAD_PATH" && "$parent_dir" != "/" ]]; then
        remove_empty_dir "$parent_dir"
    fi
}

# 检查任务状态是否异常
check_task_status() {
    if [[ "$TASK_STATUS" == "error" ]]; then
        log_warn "任务状态为错误: GID=$task_gid"
        
        # 可以在这里添加错误任务的特殊处理逻辑
        # 例如：清理损坏的文件、发送通知等
        
        return 1
    fi
    
    return 0
}

# 记录任务信息
log_task_info() {
    log_debug "=== 任务详细信息 ==="
    log_debug "任务GID: $TASK_GID"
    log_debug "任务状态: $TASK_STATUS"
    log_debug "下载目录: $DOWNLOAD_DIR"
    log_debug "源路径: $SOURCE_PATH"
    log_debug "任务名称: $TASK_NAME"
    log_debug "种子文件: $TORRENT_FILE"
    log_debug "=================="
}

# 错误处理
error_handler() {
    local exit_code=$?
    local line_number=$1
    
    log_error "脚本在第 $line_number 行发生错误，退出码: $exit_code"
    
    # 在开始阶段出错，通常不需要特殊清理
    # 但可以记录更多诊断信息
    log_error "错误发生时的环境信息:"
    log_error "  TASK_GID=${TASK_GID:-未设置}"
    log_error "  FILE_NUM=${FILE_NUM:-未设置}"
    log_error "  FILE_PATH=${FILE_PATH:-未设置}"
    log_error "  SOURCE_PATH=${SOURCE_PATH:-未设置}"
    log_error "  TASK_STATUS=${TASK_STATUS:-未设置}"
    
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