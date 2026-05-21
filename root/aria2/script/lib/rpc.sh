#!/usr/bin/env bash
# Aria2 RPC 接口库：通过 JSON-RPC 查询任务状态、下载目录、infoHash，以及删除重复任务
# 所有函数依赖环境变量 PORT（RPC 端口）和 SECRET（RPC 密钥）
# RPC 地址优先尝试 http，失败自动降级为 https（自签证书）

# 构造 aria2.tellStatus 请求体并发起查询，返回原始 JSON
# 结果赋值给外部变量 RPC_RESULT（由 GET_RPC_RESULT 调用）
RPC_TASK_INFO() {
    if [[ "${SECRET}" ]]; then
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.tellStatus","id":"NG6","params":["token:'${SECRET}'","'${TASK_GID}'"]}'
    else
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.tellStatus","id":"NG6","params":["'${TASK_GID}'"]}'
    fi
    curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}"
}

# 移除重复任务（aria2 中删除指定 GID 的任务）
# 调用前需等待 3 秒，确保 aria2 已完成本次任务的内部状态更新
REMOVE_REPEAT_TASK() {
    sleep 3s
    RPC_ADDRESS="localhost:${PORT}/jsonrpc"
    if [[ "${SECRET}" ]]; then
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.remove","id":"NG6","params":["token:'${SECRET}'","'${TASK_GID}'"]}'
    else
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.remove","id":"NG6","params":["'${TASK_GID}'"]}'
    fi
    curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}"
}

# 发起 RPC 查询并将结果存入 RPC_RESULT 变量
GET_RPC_RESULT() {
    RPC_ADDRESS="localhost:${PORT}/jsonrpc"
    RPC_RESULT="$(RPC_TASK_INFO)"
}

# 从 RPC_RESULT 中解析任务下载目录（dir 字段）
# 空结果说明 aria2 RPC 不可用，直接退出容器启动流程
GET_DOWNLOAD_DIR() {
    [[ -z ${RPC_RESULT} ]] && {
        echo -e "$(DATE_TIME) ${ERROR} Aria2 RPC interface error!"
        exit 1
    }
    DOWNLOAD_DIR=$(echo "${RPC_RESULT}" | jq -r '.result.dir')
    [[ -z "${DOWNLOAD_DIR}" || "${DOWNLOAD_DIR}" = "null" ]] && {
        echo "${RPC_RESULT}" | jq '.result'
        echo -e "$(DATE_TIME) ${ERROR} Failed to get download directory!"
        exit 1
    }
}

# 从 RPC_RESULT 中解析任务状态（status 字段）
# 常见值：active / waiting / paused / error / complete / removed
GET_TASK_STATUS() {
    TASK_STATUS=$(echo "${RPC_RESULT}" | jq -r '.result.status')
    [[ -z "${TASK_STATUS}" || "${TASK_STATUS}" = "null" ]] && {
        echo "${RPC_RESULT}" | jq '.result'
        echo -e "$(DATE_TIME) ${ERROR} Failed to get task status!"
        exit 1
    }
}

# 从 RPC_RESULT 中解析 BT 任务的 infoHash，并推算种子文件路径
# 非 BT 任务（HTTP/FTP）infoHash 为 null，返回值 1 表示非 BT，TORRENT_FILE 不设置
GET_INFO_HASH() {
    INFO_HASH=$(echo "${RPC_RESULT}" | jq -r '.result.infoHash')
    if [[ -z "${INFO_HASH}" ]]; then
        echo "${RPC_RESULT}" | jq '.result'
        echo -e "$(DATE_TIME) ${ERROR} Failed to get Info Hash!"
        exit 1
    elif [[ "${INFO_HASH}" = "null" ]]; then
        # 非 BT 任务，没有 infoHash，正常情况
        return 1
    else
        # aria2 把 .torrent 缓存为 <infoHash>.torrent，放在任务下载目录
        TORRENT_PATH="${DOWNLOAD_DIR}/${INFO_HASH}"
        TORRENT_FILE="${DOWNLOAD_DIR}/${INFO_HASH}.torrent"
    fi
}

# 一次性获取所有 RPC 信息（结果、状态、下载目录、infoHash）
# 由 lib/all.sh 的 INIT_EVENT 调用
GET_RPC_INFO() {
    GET_RPC_RESULT
    GET_TASK_STATUS
    GET_DOWNLOAD_DIR
    GET_INFO_HASH
}
