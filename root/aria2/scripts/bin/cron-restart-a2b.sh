#!/usr/bin/env bash
# =============================================================================
# Aria2B定时重启脚本
#
# 功能: 管理aria2b进程的定时重启，防止吸血客户端连接过久
# 使用: 通过环境变量CRA2B控制重启间隔
# 配置: CRA2B=false 禁用, CRA2B=2h 每2小时重启一次
# =============================================================================

set -euo pipefail

# 脚本目录
readonly SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

# 加载框架库
source "$SCRIPT_DIR/../lib/lib.sh"

# 默认重启间隔（小时）
readonly DEFAULT_RESTART_HOURS=2
readonly MIN_RESTART_HOURS=1
readonly MAX_RESTART_HOURS=24

# Cron任务标识符
readonly CRON_MARKER="aria2b-restart"

# 主处理函数
main() {
    # 初始化脚本环境
    init_lib "/config" "/config/logs"
    
    log_info "=== Aria2B定时重启管理 ==="
    
    # 获取配置
    local restart_config="${CRA2B:-${1:-}}"
    
    if [[ -z "$restart_config" ]]; then
        log_info "未指定重启配置，显示当前状态"
        show_current_status
        exit 0
    fi
    
    # 处理配置
    process_restart_config "$restart_config"
    
    log_info "=== Aria2B定时重启管理完成 ==="
}

# 处理重启配置
process_restart_config() {
    local config="$1"
    
    log_info "处理重启配置: $config"
    
    # 检查是否禁用
    if [[ "${config,,}" == "false" || "${config,,}" == "disable" ]]; then
        disable_restart_cron
        return 0
    fi
    
    # 解析重启间隔
    local hours
    hours=$(parse_restart_hours "$config")
    
    if [[ -z "$hours" ]]; then
        log_error "无效的重启配置: $config"
        exit 1
    fi
    
    # 设置定时重启
    setup_restart_cron "$hours"
}

# 解析重启间隔小时数
parse_restart_hours() {
    local config="$1"
    local hours=""
    
    # 提取数字部分
    hours=$(echo "$config" | sed 's/[^0-9]*//g')
    
    # 验证数字范围
    if [[ "$hours" =~ ^[0-9]+$ ]]; then
        if [[ $hours -ge $MIN_RESTART_HOURS && $hours -le $MAX_RESTART_HOURS ]]; then
            echo "$hours"
            return 0
        fi
    fi
    
    # 如果解析失败，返回默认值
    log_warn "配置解析失败: $config，使用默认值 ${DEFAULT_RESTART_HOURS}h"
    echo "$DEFAULT_RESTART_HOURS"
}

# 设置定时重启任务
setup_restart_cron() {
    local hours="$1"
    
    log_info "设置定时重启任务: 每 $hours 小时重启一次"
    
    # 删除现有的定时任务
    remove_existing_cron_jobs
    
    # 创建新的定时任务
    local cron_command="0 */$hours * * * /bin/bash -c 'ps -ef | grep aria2b | grep -v grep | awk \"{print \\\$2}\" | xargs -r kill -9' # $CRON_MARKER"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY_RUN] 将添加Cron任务: $cron_command"
        return 0
    fi
    
    # 添加新的cron任务
    if add_cron_job "$cron_command"; then
        log_info "定时重启任务设置成功: 每 $hours 小时的整点执行重启aria2b进程"
        
        # 验证设置
        verify_cron_setup "$hours"
    else
        log_error "定时重启任务设置失败"
        exit 1
    fi
}

# 禁用定时重启
disable_restart_cron() {
    log_info "禁用aria2b定时重启功能"
    
    if remove_existing_cron_jobs; then
        log_info "已移除定时重启任务"
    else
        log_warn "移除定时重启任务时出现问题"
    fi
}

# 移除现有的cron任务
remove_existing_cron_jobs() {
    log_debug "移除现有的aria2b重启任务"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY_RUN] 将移除现有的aria2b重启任务"
        return 0
    fi
    
    # 获取当前crontab，移除包含标识符的行
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    if [[ -n "$current_crontab" ]]; then
        local new_crontab
        new_crontab=$(echo "$current_crontab" | grep -v "$CRON_MARKER" || echo "")
        
        # 更新crontab
        if echo "$new_crontab" | crontab -; then
            log_debug "现有aria2b重启任务已移除"
            return 0
        else
            log_error "移除现有cron任务失败"
            return 1
        fi
    else
        log_debug "没有找到现有的cron任务"
        return 0
    fi
}

# 添加cron任务
add_cron_job() {
    local cron_command="$1"
    
    log_debug "添加Cron任务: $cron_command"
    
    # 获取当前crontab
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    # 添加新任务
    local new_crontab
    if [[ -n "$current_crontab" ]]; then
        new_crontab="$current_crontab
$cron_command"
    else
        new_crontab="$cron_command"
    fi
    
    # 更新crontab
    if echo "$new_crontab" | crontab -; then
        log_debug "Cron任务添加成功"
        return 0
    else
        log_error "Cron任务添加失败"
        return 1
    fi
}

# 验证cron设置
verify_cron_setup() {
    local hours="$1"
    
    log_debug "验证cron设置"
    
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    if echo "$current_crontab" | grep -q "$CRON_MARKER"; then
        log_info "定时任务验证成功"
        
        # 显示设置的任务
        local cron_line
        cron_line=$(echo "$current_crontab" | grep "$CRON_MARKER")
        log_debug "设置的任务: $cron_line"
        
        return 0
    else
        log_error "定时任务验证失败，未找到设置的任务"
        return 1
    fi
}

# 显示当前状态
show_current_status() {
    log_info "=== 当前Aria2B重启配置状态 ==="
    
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    if [[ -n "$current_crontab" ]]; then
        local restart_jobs
        restart_jobs=$(echo "$current_crontab" | grep "$CRON_MARKER" || echo "")
        
        if [[ -n "$restart_jobs" ]]; then
            log_info "已启用定时重启:"
            while read -r job; do
                [[ -n "$job" ]] && log_info "  $job"
            done <<< "$restart_jobs"
        else
            log_info "未设置aria2b定时重启任务"
        fi
    else
        log_info "用户未设置任何cron任务"
    fi
    
    # 检查aria2b进程状态
    check_aria2b_status
    
    log_info "环境变量 CRA2B: ${CRA2B:-未设置}"
}

# 检查aria2b进程状态
check_aria2b_status() {
    log_debug "检查aria2b进程状态"
    
    local aria2b_processes
    aria2b_processes=$(ps -ef | grep aria2b | grep -v grep || echo "")
    
    if [[ -n "$aria2b_processes" ]]; then
        local process_count
        process_count=$(echo "$aria2b_processes" | wc -l)
        log_info "当前运行的aria2b进程数: $process_count"
        log_debug "进程信息:"
        while read -r process; do
            [[ -n "$process" ]] && log_debug "  $process"
        done <<< "$aria2b_processes"
    else
        log_info "当前没有运行的aria2b进程"
    fi
}

# 手动重启aria2b
manual_restart_aria2b() {
    log_info "执行手动重启aria2b"
    
    local aria2b_pids
    aria2b_pids=$(ps -ef | grep aria2b | grep -v grep | awk '{print $2}' || echo "")
    
    if [[ -n "$aria2b_pids" ]]; then
        log_info "发现aria2b进程，准备重启"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY_RUN] 将重启进程: $aria2b_pids"
            return 0
        fi
        
        # 终止进程
        if echo "$aria2b_pids" | xargs -r kill -9; then
            log_info "aria2b进程重启成功"
            
            # 等待进程重新启动
            sleep 3
            check_aria2b_status
        else
            log_error "aria2b进程重启失败"
            return 1
        fi
    else
        log_info "没有发现运行中的aria2b进程"
    fi
}

# 错误处理
error_handler() {
    local exit_code=$?
    local line_number=$1
    
    log_error "脚本在第 $line_number 行发生错误，退出码: $exit_code"
    log_error "当前配置: CRA2B=${CRA2B:-未设置}"
    
    exit $exit_code
}

# 显示使用帮助
show_help() {
    cat << EOF
Aria2B定时重启脚本

用法:
  $0 [配置]

配置选项:
  false|disable  - 禁用定时重启
  <数字>h       - 设置重启间隔（1-24小时）
  status        - 显示当前状态
  restart       - 手动重启aria2b
  help          - 显示此帮助

示例:
  $0 2h         # 每2小时重启一次
  $0 false      # 禁用定时重启
  $0 status     # 显示当前状态
  $0 restart    # 手动重启

环境变量:
  CRA2B         - 重启配置（与命令行参数相同）
  DRY_RUN       - 设置为true时只显示操作不执行

EOF
}

# 设置错误处理
trap 'error_handler $LINENO' ERR

# 参数处理
case "${1:-}" in
    "help"|"-h"|"--help")
        show_help
        exit 0
        ;;
    "status")
        main ""
        ;;
    "restart")
        init_lib "/config" "/config/logs"
        manual_restart_aria2b
        ;;
    *)
        main "$@"
        ;;
esac