#!/usr/bin/env bash
#====================================================================
# rpc.sh
# 处理所有与Aria2 RPC相关的操作
#====================================================================

source "$(dirname "$0")/logging.sh"

# RPC地址构建
get_rpc_address() {
    echo "localhost:${PORT}/jsonrpc"
}

# 构建RPC请求参数
build_rpc_params() {
    if [[ -n "${SECRET}" ]]; then
        echo "token:${SECRET}"
    fi
}

# 获取任务状态信息
get_task_status() {
    local task_gid="$1"
    local rpc_address
    rpc_address=$(get_rpc_address)
    local auth_token
    auth_token=$(build_rpc_params)

    local payload
    if [[ -n "${auth_token}" ]]; then
        payload="{\"jsonrpc\":\"2.0\",\"method\":\"aria2.tellStatus\",\"id\":\"NG6\",\"params\":[\"${auth_token}\",\"${task_gid}\"]}"
    else
        payload="{\"jsonrpc\":\"2.0\",\"method\":\"aria2.tellStatus\",\"id\":\"NG6\",\"params\":[\"${task_gid}\"]}"
    fi

    # 发送RPC请求
    local response
    response=$(curl "${rpc_address}" -fsSd "${payload}" || curl "https://${rpc_address}" -kfsSd "${payload}")
    
    # 检查响应
    if [[ -z "${response}" ]]; then
        log_error "RPC请求失败: 无响应"
        return 1
    fi

    # 返回响应数据
    echo "${response}"
}

# 从RPC响应中解析下载目录
parse_download_dir() {
    local response="$1"
    local dir
    
    dir=$(echo "${response}" | jq -r '.result.dir')
    if [[ -z "${dir}" || "${dir}" == "null" ]]; then
        log_error "无法获取下载目录"
        return 1
    fi
    
    echo "${dir}"
}

# 从RPC响应中解析任务状态
parse_task_status() {
    local response="$1"
    local status
    
    status=$(echo "${response}" | jq -r '.result.status')
    if [[ -z "${status}" || "${status}" == "null" ]]; then
        log_error "无法获取任务状态"
        return 1
    }
    
    echo "${status}"
}

# 从RPC响应中解析种子Hash
parse_info_hash() {
    local response="$1"
    local info_hash
    
    info_hash=$(echo "${response}" | jq -r '.result.infoHash')
    if [[ -z "${info_hash}" ]]; then
        log_error "无法获取InfoHash"
        return 1
    elif [[ "${info_hash}" == "null" ]]; then
        return 0
    fi
    
    # 设置种子相关路径
    TORRENT_PATH="${DOWNLOAD_DIR}/${info_hash}"
    TORRENT_FILE="${DOWNLOAD_DIR}/${info_hash}.torrent"
    
    echo "${info_hash}"
}

# 删除重复的任务
remove_task() {
    local task_gid="$1"
    local rpc_address
    rpc_address=$(get_rpc_address)
    local auth_token
    auth_token=$(build_rpc_params)

    # 等待3秒确保任务状态已更新
    sleep 3

    local payload
    if [[ -n "${auth_token}" ]]; then
        payload="{\"jsonrpc\":\"2.0\",\"method\":\"aria2.remove\",\"id\":\"NG6\",\"params\":[\"${auth_token}\",\"${task_gid}\"]}"
    else
        payload="{\"jsonrpc\":\"2.0\",\"method\":\"aria2.remove\",\"id\":\"NG6\",\"params\":[\"${task_gid}\"]}"
    fi

    # 发送删除请求
    curl "${rpc_address}" -fsSd "${payload}" || curl "https://${rpc_address}" -kfsSd "${payload}"
}

# 更新BT Tracker
update_trackers() {
    local trackers="$1"
    local rpc_address
    rpc_address=$(get_rpc_address)
    local auth_token
    auth_token=$(build_rpc_params)

    local payload
    if [[ -n "${auth_token}" ]]; then
        payload="{\"jsonrpc\":\"2.0\",\"method\":\"aria2.changeGlobalOption\",\"id\":\"NG6\",\"params\":[\"${auth_token}\",{\"bt-tracker\":\"${trackers}\"}]}"
    else
        payload="{\"jsonrpc\":\"2.0\",\"method\":\"aria2.changeGlobalOption\",\"id\":\"NG6\",\"params\":[{\"bt-tracker\":\"${trackers}\"}]}"
    fi

    # 发送更新请求
    local response
    response=$(curl "${rpc_address}" -fsSd "${payload}" || curl "https://${rpc_address}" -kfsSd "${payload}")
    
    # 检查更新结果
    if echo "${response}" | grep -q "OK"; then
        log_info "成功更新BT Trackers"
        return 0
    else
        log_error "更新BT Trackers失败"
        return 1
    fi
}

# 获取完整的RPC信息
get_rpc_info() {
    local task_gid="$1"
    local response
    
    # 获取任务状态
    response=$(get_task_status "${task_gid}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # 解析下载目录
    DOWNLOAD_DIR=$(parse_download_dir "${response}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # 解析任务状态
    TASK_STATUS=$(parse_task_status "${response}")
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # 解析种子Hash
    parse_info_hash "${response}"
}