#!/usr/bin/env bash
# Aria2 RPC 接口库：通过 JSON-RPC 查询任务状态、下载目录、infoHash，以及删除重复任务
# 所有函数依赖环境变量 PORT（RPC 端口）和 SECRET（RPC 密钥）
# RPC 地址优先尝试 http，失败自动降级为 https（自签证书）
# Lib 层契约：发生错误时返回非零，错误信息写 stderr；由调用方（INIT_EVENT）决定是否中止

# 构造 aria2.tellStatus 请求体并发起查询，返回原始 JSON
# 结果赋值给外部变量 RPC_RESULT（由 GET_RPC_RESULT 调用）
# 用 jq 构造 payload：自动转义 SECRET / TASK_GID 中的 " \ 换行等特殊字符，杜绝 JSON 注入
RPC_TASK_INFO() {
    RPC_PAYLOAD=$(jq -nc \
        --arg secret "${SECRET}" \
        --arg gid "${TASK_GID}" \
        '{jsonrpc:"2.0",method:"aria2.tellStatus",id:"NG6",
          params:(if $secret == "" then [$gid] else ["token:" + $secret, $gid] end)}')
    curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}"
}

# 移除重复任务（aria2 中删除指定 GID 的任务）
# 调用前需等待 3 秒，确保 aria2 已完成本次任务的内部状态更新
REMOVE_REPEAT_TASK() {
    sleep 3s
    RPC_ADDRESS="localhost:${PORT}/jsonrpc"
    RPC_PAYLOAD=$(jq -nc \
        --arg secret "${SECRET}" \
        --arg gid "${TASK_GID}" \
        '{jsonrpc:"2.0",method:"aria2.remove",id:"NG6",
          params:(if $secret == "" then [$gid] else ["token:" + $secret, $gid] end)}')
    curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}"
}

# 发起 RPC 查询并将结果存入 RPC_RESULT 变量
GET_RPC_RESULT() {
    RPC_ADDRESS="localhost:${PORT}/jsonrpc"
    RPC_RESULT="$(RPC_TASK_INFO)"
}

# 从 RPC_RESULT 中解析任务下载目录（dir 字段）
# 空结果说明 aria2 RPC 不可用，返回 1 让调用方中止
GET_DOWNLOAD_DIR() {
    if [ -z "${RPC_RESULT}" ]; then
        echo -e "$(DATE_TIME) ${ERROR} Aria2 RPC interface error!" >&2
        return 1
    fi
    DOWNLOAD_DIR=$(echo "${RPC_RESULT}" | jq -r '.result.dir')
    if [ -z "${DOWNLOAD_DIR}" ] || [ "${DOWNLOAD_DIR}" = "null" ]; then
        echo "${RPC_RESULT}" | jq '.result' >&2
        echo -e "$(DATE_TIME) ${ERROR} Failed to get download directory!" >&2
        return 1
    fi
}

# 从 RPC_RESULT 中解析任务状态（status 字段）
# 常见值：active / waiting / paused / error / complete / removed
GET_TASK_STATUS() {
    TASK_STATUS=$(echo "${RPC_RESULT}" | jq -r '.result.status')
    if [ -z "${TASK_STATUS}" ] || [ "${TASK_STATUS}" = "null" ]; then
        echo "${RPC_RESULT}" | jq '.result' >&2
        echo -e "$(DATE_TIME) ${ERROR} Failed to get task status!" >&2
        return 1
    fi
}

# 从 RPC_RESULT 中解析 BT 任务的 infoHash，并推算种子文件路径
# 返回码语义：
#   0 - BT 任务且 infoHash 有效，已设置 TORRENT_FILE
#   1 - 非 BT 任务（HTTP/FTP），infoHash=null，TORRENT_FILE 未设置
#   2 - 解析失败（RPC 响应不含 infoHash 字段），是真正的错误
GET_INFO_HASH() {
    INFO_HASH=$(echo "${RPC_RESULT}" | jq -r '.result.infoHash')
    if [ -z "${INFO_HASH}" ]; then
        echo "${RPC_RESULT}" | jq '.result' >&2
        echo -e "$(DATE_TIME) ${ERROR} Failed to get Info Hash!" >&2
        return 2
    fi
    if [ "${INFO_HASH}" = "null" ]; then
        return 1
    fi
    # aria2 把 .torrent 缓存为 <infoHash>.torrent，放在任务下载目录
    TORRENT_PATH="${DOWNLOAD_DIR}/${INFO_HASH}"
    TORRENT_FILE="${DOWNLOAD_DIR}/${INFO_HASH}.torrent"
}

# 一次性获取所有 RPC 信息（结果、状态、下载目录、infoHash）
# 由 lib/all.sh 的 INIT_EVENT 调用；任何致命错误返回 1，调用方决定是否中止
# GET_INFO_HASH 返回 1（非 BT）属正常情况，不向上传播
GET_RPC_INFO() {
    GET_RPC_RESULT
    GET_TASK_STATUS  || return 1
    GET_DOWNLOAD_DIR || return 1
    GET_INFO_HASH
    [ $? -eq 2 ] && return 1
    return 0
}
