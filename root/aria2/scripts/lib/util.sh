#!/usr/bin/env bash
# =============================================================================
# 工具函数模块 - 小型通用工具函数
# 设计哲学：简单工具，单一职责
# =============================================================================

# 获取格式化的日期时间字符串
# 返回: YYYY-MM-DD HH:MM:SS 格式的时间字符串
date_time() {
    date '+%Y-%m-%d %H:%M:%S'
}

# 解析布尔值
# 参数: VALUE DEFAULT
# 返回: "true" 或 "false"
parse_bool() {
    local value="$1"
    local default="${2:-false}"
    
    # 将输入转换为小写
    value=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    
    case "$value" in
        true|yes|1|on|enabled)
            echo "true"
            ;;
        false|no|0|off|disabled)
            echo "false"
            ;;
        *)
            echo "$default"
            ;;
    esac
}

# 解析整数值
# 参数: VALUE DEFAULT
# 返回: 整数值或默认值
parse_int() {
    local value="$1"
    local default="${2:-0}"
    
    # 检查是否为数字
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# 将字节数转换为人类可读格式
# 参数: BYTES
# 返回: 如 "1.5G", "256M" 等格式
human_readable_size() {
    local bytes="$1"
    local units=("B" "K" "M" "G" "T")
    local unit_index=0
    local size="$bytes"
    
    while [[ $size -gt 1024 && $unit_index -lt 4 ]]; do
        size=$((size / 1024))
        ((unit_index++))
    done
    
    echo "${size}${units[$unit_index]}"
}

# 将大小字符串转换为字节数
# 参数: SIZE_STRING (如 "1G", "512M")
# 返回: 字节数
to_bytes() {
    local size_str="$1"
    local number="${size_str%[a-zA-Z]*}"
    local unit="${size_str#"$number"}"
    
    # 默认数值为0
    number="${number:-0}"
    
    case "${unit^^}" in
        K|KB)
            echo $((number * 1024))
            ;;
        M|MB)
            echo $((number * 1024 * 1024))
            ;;
        G|GB)
            echo $((number * 1024 * 1024 * 1024))
            ;;
        T|TB)
            echo $((number * 1024 * 1024 * 1024 * 1024))
            ;;
        *)
            echo "$number"
            ;;
    esac
}

# 安全提取JSON字段
# 参数: JSON_STRING FIELD_PATH
# 返回: 字段值或空字符串
safe_json_extract() {
    local json="$1"
    local field="$2"
    
    if command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -r "$field" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# 检查字符串是否为空
# 参数: STRING
# 返回: 0表示空，1表示非空
is_empty() {
    [[ -z "${1// }" ]]
}

# 检查变量是否已设置
# 参数: VARIABLE_NAME
# 返回: 0表示已设置，1表示未设置
is_set() {
    [[ -n "${!1}" ]]
}

# 生成随机字符串
# 参数: LENGTH
# 返回: 随机字符串
random_string() {
    local length="${1:-8}"
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

# 创建锁文件
# 参数: LOCK_FILE
# 返回: 0表示成功获取锁，1表示锁已存在
acquire_lock() {
    local lock_file="$1"
    local lock_dir
    lock_dir="$(dirname "$lock_file")"
    
    # 确保锁目录存在
    mkdir -p "$lock_dir"
    
    # 尝试创建锁文件
    if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 释放锁文件
# 参数: LOCK_FILE
release_lock() {
    local lock_file="$1"
    [[ -f "$lock_file" ]] && rm -f "$lock_file"
}

# URL编码
# 参数: STRING
# 返回: URL编码后的字符串
url_encode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o
    
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) 
                o="${c}" 
                ;;
            * )               
                printf -v o '%%%02x' "'$c"
                ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# 重试执行命令
# 参数: MAX_ATTEMPTS DELAY COMMAND [ARGS...]
# 返回: 最后一次执行的返回码
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            sleep "$delay"
        fi
        ((attempt++))
    done
    
    return 1
}

# 检查网络连接
# 参数: HOST PORT
# 返回: 0表示连接成功，1表示失败
check_network() {
    local host="${1:-localhost}"
    local port="${2:-80}"
    
    if command -v nc >/dev/null 2>&1; then
        nc -z "$host" "$port" 2>/dev/null
    elif command -v telnet >/dev/null 2>&1; then
        timeout 3 telnet "$host" "$port" </dev/null >/dev/null 2>&1
    else
        # fallback to curl
        curl -s --connect-timeout 3 "http://$host:$port" >/dev/null 2>&1
    fi
}

# 工具模块加载完成标志
export ARIA2_UTIL_LOADED="true"