#!/usr/bin/env bash
# =============================================================================
# RPC通信模块 - Aria2 JSON-RPC接口封装
# 设计哲学：统一RPC调用，错误处理，重试机制
# =============================================================================

# RPC配置变量
RPC_ADDRESS=""
RPC_SECRET=""
RPC_PORT="${PORT:-6800}"
RPC_TIMEOUT=10
RPC_MAX_RETRIES=3

# RPC错误代码
readonly RPC_ERROR_NETWORK=10
readonly RPC_ERROR_AUTH=11  
readonly RPC_ERROR_RESPONSE=12

# 初始化RPC配置
# 参数: [PORT] [SECRET]
init_rpc() {
    local port="${1:-$RPC_PORT}"
    local secret="${2:-$SECRET}"
    
    RPC_PORT="$port"
    RPC_SECRET="$secret"
    RPC_ADDRESS="localhost:${RPC_PORT}/jsonrpc"
    
    log_debug "RPC配置初始化: 端口=$RPC_PORT, 密钥=${RPC_SECRET:+已设置}"
}

# 构建RPC请求载荷
# 参数: METHOD PARAMS...
# 返回: JSON字符串
_build_rpc_payload() {
    local method="$1"
    shift
    local params_array=""
    
    # 如果设置了密钥，添加token参数
    if [[ -n "$RPC_SECRET" ]]; then
        params_array="\"token:$RPC_SECRET\""
        [[ $# -gt 0 ]] && params_array+=","
    fi
    
    # 添加其他参数
    local param
    for param in "$@"; do
        # 如果参数包含特殊字符，需要转义
        if [[ "$param" =~ [\"\\] ]]; then
            param=$(printf '%s' "$param" | sed 's/\\/\\\\/g; s/"/\\"/g')
        fi
        params_array+="\"$param\""
        [[ $# -gt 1 ]] && params_array+=","
        shift
    done
    
    # 构建完整的JSON负载
    cat <<EOF
{
    "jsonrpc": "2.0",
    "method": "$method",
    "id": "aria2-scripts",
    "params": [$params_array]
}
EOF
}

# 执行RPC调用
# 参数: PAYLOAD
# 返回: JSON响应或错误码
_execute_rpc_call() {
    local payload="$1"
    local attempt=1
    local response
    
    while [[ $attempt -le $RPC_MAX_RETRIES ]]; do
        log_debug "RPC调用尝试 $attempt/$RPC_MAX_RETRIES"
        
        # 首先尝试HTTP
        response=$(curl -sS --fail --connect-timeout "$RPC_TIMEOUT" \
                      --max-time $((RPC_TIMEOUT * 2)) \
                      -H "Content-Type: application/json" \
                      -d "$payload" \
                      "http://$RPC_ADDRESS" 2>/dev/null)
        
        local exit_code=$?
        
        # 如果HTTP失败，尝试HTTPS
        if [[ $exit_code -ne 0 ]]; then
            log_debug "HTTP调用失败，尝试HTTPS"
            response=$(curl -ksSf --connect-timeout "$RPC_TIMEOUT" \
                          --max-time $((RPC_TIMEOUT * 2)) \
                          -H "Content-Type: application/json" \
                          -d "$payload" \
                          "https://$RPC_ADDRESS" 2>/dev/null)
            exit_code=$?
        fi
        
        # 检查响应
        if [[ $exit_code -eq 0 && -n "$response" ]]; then
            # 检查是否为有效的JSON响应
            if echo "$response" | jq . >/dev/null 2>&1; then
                echo "$response"
                return 0
            else
                log_debug "无效的JSON响应: $response"
            fi
        fi
        
        # 重试前等待
        if [[ $attempt -lt $RPC_MAX_RETRIES ]]; then
            local delay=$((attempt * 2))
            log_debug "RPC调用失败，${delay}秒后重试..."
            sleep "$delay"
        fi
        
        ((attempt++))
    done
    
    log_error "RPC调用失败，已重试 $RPC_MAX_RETRIES 次"
    return $RPC_ERROR_NETWORK
}

# 通用RPC调用接口
# 参数: METHOD PARAMS...
# 返回: JSON响应
rpc_call() {
    local method="$1"
    shift
    
    # 检查RPC是否已初始化
    if [[ -z "$RPC_ADDRESS" ]]; then
        init_rpc
    fi
    
    local payload
    payload=$(_build_rpc_payload "$method" "$@")
    
    log_debug "RPC调用: $method"
    log_debug "载荷: $payload"
    
    local response
    response=$(_execute_rpc_call "$payload")
    local rpc_exit_code=$?
    
    if [[ $rpc_exit_code -eq 0 ]]; then
        # 检查响应中是否有错误
        local error
        error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
        if [[ -n "$error" && "$error" != "null" ]]; then
            log_error "RPC错误响应: $error"
            return $RPC_ERROR_RESPONSE
        fi
        
        echo "$response"
        return 0
    else
        return $rpc_exit_code
    fi
}

# 获取任务状态信息
# 参数: GID
# 导出变量: TASK_STATUS, DOWNLOAD_DIR, INFO_HASH, TORRENT_FILE, FILES
get_task_info() {
    local gid="$1"
    
    if [[ -z "$gid" ]]; then
        log_error "获取任务信息：GID不能为空"
        return $E_RPC_ERROR
    fi
    
    local response
    response=$(rpc_call "aria2.tellStatus" "$gid")
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "获取任务信息失败: GID=$gid"
        return $exit_code
    fi
    
    # 解析响应
    local result
    result=$(echo "$response" | jq -r '.result' 2>/dev/null)
    
    if [[ -z "$result" || "$result" == "null" ]]; then
        log_error "无效的任务信息响应: $response"
        return $RPC_ERROR_RESPONSE
    fi
    
    # 导出任务信息变量
    export TASK_STATUS
    export DOWNLOAD_DIR
    export INFO_HASH
    export TORRENT_FILE
    
    TASK_STATUS=$(echo "$result" | jq -r '.status // "unknown"')
    DOWNLOAD_DIR=$(echo "$result" | jq -r '.dir // ""')
    INFO_HASH=$(echo "$result" | jq -r '.infoHash // ""')
    
    # 构建种子文件路径
    if [[ -n "$INFO_HASH" && "$INFO_HASH" != "null" ]]; then
        TORRENT_FILE="${DOWNLOAD_DIR}/${INFO_HASH}.torrent"
    else
        TORRENT_FILE=""
    fi
    
    log_debug "任务信息获取成功: GID=$gid, 状态=$TASK_STATUS, 目录=$DOWNLOAD_DIR"
    
    # 验证关键字段
    if [[ -z "$DOWNLOAD_DIR" || "$DOWNLOAD_DIR" == "null" ]]; then
        log_error "获取下载目录失败: GID=$gid"
        return $RPC_ERROR_RESPONSE
    fi
    
    return 0
}

# 删除任务
# 参数: GID [FORCE]
rpc_remove_task() {
    local gid="$1"
    local force="${2:-false}"
    
    if [[ -z "$gid" ]]; then
        log_error "删除任务：GID不能为空"
        return $E_RPC_ERROR
    fi
    
    # 等待3秒让任务稳定
    sleep 3
    
    local method="aria2.remove"
    [[ "$force" == "true" ]] && method="aria2.forceRemove"
    
    local response
    response=$(rpc_call "$method" "$gid")
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "任务删除成功: GID=$gid"
        return 0
    else
        log_error "任务删除失败: GID=$gid"
        return $exit_code
    fi
}

# 暂停任务
# 参数: GID [FORCE]
rpc_pause_task() {
    local gid="$1"
    local force="${2:-false}"
    
    if [[ -z "$gid" ]]; then
        log_error "暂停任务：GID不能为空"
        return $E_RPC_ERROR
    fi
    
    local method="aria2.pause"
    [[ "$force" == "true" ]] && method="aria2.forcePause"
    
    local response
    response=$(rpc_call "$method" "$gid")
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "任务暂停成功: GID=$gid"
        return 0
    else
        log_error "任务暂停失败: GID=$gid"
        return $exit_code
    fi
}

# 获取全局配置
# 返回: JSON配置
rpc_get_global_options() {
    local response
    response=$(rpc_call "aria2.getGlobalOption")
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "$response" | jq -r '.result' 2>/dev/null
        return 0
    else
        log_error "获取全局配置失败"
        return $exit_code
    fi
}

# 更新全局配置
# 参数: OPTIONS_JSON
rpc_change_global_options() {
    local options="$1"
    
    if [[ -z "$options" ]]; then
        log_error "更新全局配置：选项不能为空"
        return $E_RPC_ERROR
    fi
    
    local response
    response=$(rpc_call "aria2.changeGlobalOption" "$options")
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "全局配置更新成功"
        return 0
    else
        log_error "全局配置更新失败"
        return $exit_code
    fi
}

# 检查RPC连接状态
# 返回: 0表示连接正常，非0表示连接异常
check_rpc_connection() {
    local response
    response=$(rpc_call "aria2.getVersion" 2>/dev/null)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        local version
        version=$(echo "$response" | jq -r '.result.version' 2>/dev/null)
        log_debug "RPC连接正常，Aria2版本: $version"
        return 0
    else
        log_warn "RPC连接异常"
        return $exit_code
    fi
}

# 兼容旧接口的函数
RPC_TASK_INFO() {
    local response
    response=$(rpc_call "aria2.tellStatus" "$TASK_GID")
    echo "$response"
}

REMOVE_REPEAT_TASK() {
    rpc_remove_task "$TASK_GID"
}

GET_RPC_RESULT() {
    RPC_RESULT=$(RPC_TASK_INFO)
}

GET_RPC_INFO() {
    get_task_info "$TASK_GID"
}

# RPC模块加载完成标志
export ARIA2_RPC_LOADED="true"