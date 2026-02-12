#!/usr/bin/env bash
# =============================================================================
# Aria2 脚本框架核心库 - 主入口模块
# 设计哲学：每个函数只做一件事，保持简单，模块化设计
# =============================================================================

# 脚本版本信息
readonly ARIA2_SCRIPTS_VERSION="2.0.0"

# 全局配置变量
BASE_CONFIG_DIR=""
LOG_DIR=""
SCRIPT_DIR=""

# 错误代码
readonly E_SUCCESS=0
readonly E_CONFIG_ERROR=1
readonly E_RPC_ERROR=2
readonly E_PATH_ERROR=3
readonly E_FILE_ERROR=4

# 初始化脚本库
# 参数: CONFIG_DIR LOG_DIR
# 作用: 设置全局路径变量，加载其他模块
init_lib() {
    local config_dir="${1:-/config}"
    local log_dir="${2:-/config/logs}"
    
    BASE_CONFIG_DIR="$config_dir"
    LOG_DIR="$log_dir"
    SCRIPT_DIR="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
    
    # 确保日志目录存在
    mkdir -p "$LOG_DIR"
    
    # 加载其他模块
    source "$SCRIPT_DIR/lib/util.sh"
    source "$SCRIPT_DIR/lib/log.sh"  
    source "$SCRIPT_DIR/lib/rpc.sh"
    source "$SCRIPT_DIR/lib/paths.sh"
    source "$SCRIPT_DIR/lib/fsops.sh"
    source "$SCRIPT_DIR/lib/torrent.sh"
    
    # 初始化日志系统
    init_logging "$LOG_DIR"
    
    log_info "Aria2脚本框架初始化完成 v$ARIA2_SCRIPTS_VERSION"
}

# 加载配置文件
# 参数: CONFIG_FILE
# 作用: 解析KEY=VALUE格式的配置文件，忽略注释和空行
load_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log_warn "配置文件不存在: $config_file"
        return $E_CONFIG_ERROR
    fi
    
    # 读取配置文件，忽略注释和空行
    while IFS='=' read -r key value; do
        # 跳过注释行和空行
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # 去除前后空格
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 转换key为有效的变量名（将连字符转换为下划线）
        local var_name
        var_name=$(echo "$key" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
        
        # 导出环境变量
        if [[ -n "$var_name" && -n "$value" ]]; then
            export "$var_name"="$value"
        fi
    done < <(grep -v '^[[:space:]]*$' "$config_file")
    
    log_info "配置文件加载完成: $config_file"
    return $E_SUCCESS
}

# 检查必需的命令是否存在
# 参数: CMD1 CMD2 ...
# 作用: 检查系统命令是否可用
require_commands() {
    local missing_cmds=()
    
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_cmds+=("$cmd")
        fi
    done
    
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        log_error "缺少必需的命令: ${missing_cmds[*]}"
        return $E_CONFIG_ERROR
    fi
    
    return $E_SUCCESS
}

# 显示框架版本信息
show_version() {
    echo "Aria2脚本框架 v$ARIA2_SCRIPTS_VERSION"
    echo "设计理念: Unix哲学 - 做好一件事"
}

# 设置调试模式
# 参数: true/false  
# 作用: 启用或禁用调试输出
set_debug_mode() {
    local enable="${1:-false}"
    
    if [[ "$enable" == "true" ]]; then
        export DEBUG_MODE="true"
        set -x
        log_info "调试模式已启用"
    else
        export DEBUG_MODE="false"
        set +x
    fi
}

# 设置DRY_RUN模式
# 参数: true/false
# 作用: 启用或禁用空运行模式（只记录操作不实际执行）
set_dry_run_mode() {
    local enable="${1:-false}"
    
    if [[ "$enable" == "true" ]]; then
        export DRY_RUN="true"
        log_info "空运行模式已启用 - 只记录操作不实际执行"
    else
        export DRY_RUN="false"
    fi
}

# 错误处理函数
# 参数: EXIT_CODE MESSAGE
# 作用: 记录错误信息并退出
die() {
    local exit_code="${1:-1}"
    local message="$2"
    
    log_error "$message"
    exit "$exit_code"
}

# 主库导出标志
export ARIA2_LIB_LOADED="true"