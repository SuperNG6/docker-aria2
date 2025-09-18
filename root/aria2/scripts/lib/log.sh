#!/usr/bin/env bash
# =============================================================================
# 日志处理模块 - 统一日志记录，支持并发安全
# 设计哲学：统一接口，并发安全，级别控制
# =============================================================================

# 日志级别定义
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# 颜色常量
readonly COLOR_RED="\033[31m"
readonly COLOR_GREEN="\033[1;32m"
readonly COLOR_YELLOW="\033[1;33m" 
readonly COLOR_PURPLE="\033[1;35m"
readonly COLOR_BLUE="\033[1;34m"
readonly COLOR_RESET="\033[0m"

# 全局日志配置
LOG_BASE_DIR=""
CURRENT_LOG_LEVEL="${LOG_LEVEL_INFO}"
LOG_LOCK_FILE="/var/lock/aria2-scripts.log"

# 初始化日志系统
# 参数: LOG_DIR [LOG_LEVEL]
init_logging() {
    local log_dir="$1"
    local log_level="${2:-$LOG_LEVEL_INFO}"
    
    LOG_BASE_DIR="$log_dir"
    CURRENT_LOG_LEVEL="$log_level"
    
    # 确保日志目录存在
    mkdir -p "$LOG_BASE_DIR"
    mkdir -p "$(dirname "$LOG_LOCK_FILE")"
    
    # 确保锁文件目录权限正确
    chmod 755 "$(dirname "$LOG_LOCK_FILE")" 2>/dev/null || true
}

# 内部日志写入函数（带锁保护）
# 参数: LEVEL MESSAGE [LOG_FILE]
_write_log() {
    local level="$1"
    local message="$2"
    local log_file="$3"
    local timestamp
    timestamp="$(date_time)"
    
    # 控制台输出
    case "$level" in
        "DEBUG")
            [[ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ]] && \
                echo -e "${COLOR_BLUE}[$timestamp] [DEBUG] $message${COLOR_RESET}"
            ;;
        "INFO")
            [[ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_INFO" ]] && \
                echo -e "${COLOR_GREEN}[$timestamp] [INFO] $message${COLOR_RESET}"
            ;;
        "WARN")
            [[ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_WARN" ]] && \
                echo -e "${COLOR_YELLOW}[$timestamp] [WARN] $message${COLOR_RESET}" >&2
            ;;
        "ERROR")
            [[ "$CURRENT_LOG_LEVEL" -le "$LOG_LEVEL_ERROR" ]] && \
                echo -e "${COLOR_RED}[$timestamp] [ERROR] $message${COLOR_RESET}" >&2
            ;;
    esac
    
    # 文件输出（使用flock保证并发安全）
    if [[ -n "$log_file" && -n "$LOG_BASE_DIR" ]]; then
        local full_log_path="$LOG_BASE_DIR/$log_file"
        local lock_file="${LOG_LOCK_FILE}.$(basename "$log_file")"
        
        # 使用flock进行文件锁定，避免并发写入冲突
        (
            flock -w 10 200 || {
                echo "无法获取日志文件锁: $lock_file" >&2
                return 1
            }
            echo "[$timestamp] [$level] $message" >> "$full_log_path"
        ) 200>"$lock_file"
    fi
}

# 记录调试信息
# 参数: MESSAGE [LOG_FILE]
log_debug() {
    local message="$1"
    local log_file="${2:-debug.log}"
    _write_log "DEBUG" "$message" "$log_file"
}

# 记录信息
# 参数: MESSAGE [LOG_FILE]  
log_info() {
    local message="$1"
    local log_file="${2:-info.log}"
    _write_log "INFO" "$message" "$log_file"
}

# 记录警告
# 参数: MESSAGE [LOG_FILE]
log_warn() {
    local message="$1"
    local log_file="${2:-warn.log}"
    _write_log "WARN" "$message" "$log_file"
}

# 记录错误
# 参数: MESSAGE [LOG_FILE]
log_error() {
    local message="$1"
    local log_file="${2:-error.log}"
    _write_log "ERROR" "$message" "$log_file"
}

# 记录移动操作
# 参数: MESSAGE
log_move() {
    local message="$1"
    _write_log "INFO" "$message" "move.log"
}

# 记录删除操作
# 参数: MESSAGE
log_delete() {
    local message="$1"
    _write_log "INFO" "$message" "delete.log"
}

# 记录回收操作
# 参数: MESSAGE
log_recycle() {
    local message="$1"
    _write_log "INFO" "$message" "recycle.log"
}

# 记录过滤操作
# 参数: MESSAGE
log_filter() {
    local message="$1"
    _write_log "INFO" "$message" "文件过滤日志.log"
}

# 设置日志级别
# 参数: LEVEL (debug|info|warn|error)
set_log_level() {
    local level="$1"
    
    case "${level,,}" in
        debug)
            CURRENT_LOG_LEVEL="$LOG_LEVEL_DEBUG"
            ;;
        info)
            CURRENT_LOG_LEVEL="$LOG_LEVEL_INFO"
            ;;
        warn)
            CURRENT_LOG_LEVEL="$LOG_LEVEL_WARN"
            ;;
        error)
            CURRENT_LOG_LEVEL="$LOG_LEVEL_ERROR"
            ;;
        *)
            log_warn "未知的日志级别: $level，使用默认级别 INFO"
            CURRENT_LOG_LEVEL="$LOG_LEVEL_INFO"
            ;;
    esac
    
    log_info "日志级别设置为: $level"
}

# 日志文件轮转
# 参数: LOG_FILE [MAX_SIZE_MB]
rotate_log_file() {
    local log_file="$1"
    local max_size_mb="${2:-100}"
    local full_path="$LOG_BASE_DIR/$log_file"
    
    if [[ ! -f "$full_path" ]]; then
        return 0
    fi
    
    # 检查文件大小
    local file_size_kb
    file_size_kb=$(du -k "$full_path" | cut -f1)
    local max_size_kb=$((max_size_mb * 1024))
    
    if [[ $file_size_kb -gt $max_size_kb ]]; then
        # 备份当前日志文件
        local backup_file="${full_path}.$(date +%Y%m%d_%H%M%S)"
        mv "$full_path" "$backup_file"
        
        # 创建新的日志文件
        touch "$full_path"
        
        log_info "日志文件已轮转: $log_file -> $(basename "$backup_file")"
        
        # 可选：压缩旧文件
        if command -v gzip >/dev/null 2>&1; then
            gzip "$backup_file" &
        fi
    fi
}

# 清理旧日志文件
# 参数: DAYS_TO_KEEP
cleanup_old_logs() {
    local days="${1:-30}"
    
    if [[ -d "$LOG_BASE_DIR" ]]; then
        find "$LOG_BASE_DIR" -name "*.log.*" -type f -mtime +"$days" -delete 2>/dev/null || true
        log_info "清理了 $days 天前的旧日志文件"
    fi
}

# 导出彩色字体常量（保持向后兼容）
export RED_FONT_PREFIX="$COLOR_RED"
export LIGHT_GREEN_FONT_PREFIX="$COLOR_GREEN"
export YELLOW_FONT_PREFIX="$COLOR_YELLOW"
export LIGHT_PURPLE_FONT_PREFIX="$COLOR_PURPLE"
export FONT_COLOR_SUFFIX="$COLOR_RESET"

# 向后兼容的别名
export INFO="${COLOR_GREEN}[INFO]${COLOR_RESET}"
export WARNING="${COLOR_YELLOW}[WARN]${COLOR_RESET}"
export ERROR="${COLOR_RED}[ERROR]${COLOR_RESET}"

# 兼容旧的DATE_TIME函数
DATE_TIME() {
    date_time
}

# 日志模块加载完成标志
export ARIA2_LOG_LOADED="true"