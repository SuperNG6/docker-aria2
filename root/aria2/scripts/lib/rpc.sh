#!/usr/bin/env bash
# Aria2 RPC 接口库：通过 JSON-RPC 查询任务状态、下载目录、infoHash，以及删除重复任务
# 所有函数依赖环境变量 PORT（RPC 端口）和 SECRET（RPC 密钥）
# RPC 地址优先尝试 http，失败自动降级为 https（自签证书）
# Lib 层契约：发生错误时返回非零，错误信息写 stderr；由调用方（INIT_EVENT）决定是否中止

# RPC 地址：源自 PORT 环境变量，整个事件生命周期内不变；source 时初始化一次，避免每函数重设
RPC_ADDRESS="localhost:${PORT}/jsonrpc"

# 构造 aria2.tellStatus 请求体并发起查询，返回原始 JSON
# 用 jq 构造 payload：自动转义 SECRET / TASK_GID 中的 " \ 换行等特殊字符，杜绝 JSON 注入
RPC_TASK_INFO() {
    local payload
    payload=$(jq -nc \
        --arg secret "${SECRET}" \
        --arg gid "${TASK_GID}" \
        '{jsonrpc:"2.0",method:"aria2.tellStatus",id:"NG6",
          params:(if $secret == "" then [$gid] else ["token:" + $secret, $gid] end)}')
    # 两次 curl 屏蔽 stderr：http 失败降级 https 是正常路径，curl 错误噪音不应进 docker logs
    # 失败语义由 GET_RPC_RESULT 的空响应判定捕获，不依赖 stderr
    curl "${RPC_ADDRESS}" -fsSd "${payload}" 2>/dev/null \
        || curl "https://${RPC_ADDRESS}" -kfsSd "${payload}" 2>/dev/null
}

# 移除重复任务（aria2 中删除指定 GID 的任务）
# 调用前需等待 3 秒，确保 aria2 已完成本次任务的内部状态更新
# 返回 0=移除成功（RPC 响应含 .result）；返回 1=网络失败或 aria2 拒绝（.error 非空）
# 调用方需检查返回值——失败时本地文件已删，但 aria2 任务仍存活，可能继续下载
REMOVE_REPEAT_TASK() {
    sleep 3
    local payload result
    payload=$(jq -nc \
        --arg secret "${SECRET}" \
        --arg gid "${TASK_GID}" \
        '{jsonrpc:"2.0",method:"aria2.remove",id:"NG6",
          params:(if $secret == "" then [$gid] else ["token:" + $secret, $gid] end)}')
    result=$(curl "${RPC_ADDRESS}" -fsSd "${payload}" 2>/dev/null) \
        || result=$(curl "https://${RPC_ADDRESS}" -kfsSd "${payload}" 2>/dev/null) \
        || return 1
    # 响应里 .result 字段（值为被移除的 GID）存在才算真成功；.error 字段表示 aria2 拒绝
    [ -n "$(echo "${result}" | jq -r '.result // empty' 2>/dev/null)" ]
}

# 发起 RPC 查询，结果存入 RPC_RESULT；空响应（curl 失败 / aria2 未起）即报错
GET_RPC_RESULT() {
    RPC_RESULT="$(RPC_TASK_INFO)"
    if [ -z "${RPC_RESULT}" ]; then
        echo -e "$(DATE_TIME) ${ERROR} Aria2 RPC interface error!" >&2
        return 1
    fi
}

# 私有辅助：从 RPC_RESULT 中提取 .result.<field>；空或 "null" 时打印错误并返回 1
# 调用方负责把成功值赋给目标变量：`MY_VAR=$(_jq_field <name>) || return 1`
_jq_field() {
    local field=$1 val
    val=$(echo "${RPC_RESULT}" | jq -r ".result.${field}")
    if [ -z "${val}" ] || [ "${val}" = "null" ]; then
        echo "${RPC_RESULT}" | jq '.result' >&2
        echo -e "$(DATE_TIME) ${ERROR} Failed to get ${field}!" >&2
        return 1
    fi
    printf '%s' "${val}"
}

# 解析任务下载目录（dir 字段）
GET_DOWNLOAD_DIR() { DOWNLOAD_DIR=$(_jq_field dir); }

# 解析任务状态（status 字段）；常见值：active / waiting / paused / error / complete / removed
GET_TASK_STATUS() { TASK_STATUS=$(_jq_field status); }

# 解析 BT 任务的 infoHash，并推算种子文件路径
# 返回码语义（GET_RPC_INFO 用来区分致命错误与正常的非 BT 任务）：
#   0 - BT 任务且 infoHash 有效，已设置 TORRENT_FILE
#   1 - 非 BT 任务（HTTP/FTP），infoHash=null，TORRENT_FILE 未设置（正常路径）
#   2 - 解析失败（RPC 响应不含 infoHash 字段），致命错误
GET_INFO_HASH() {
    # 入口先清空：防止本进程内若再次进入时上一次的 INFO_HASH 残留被误读。
    # 当前 INIT_EVENT 每次只调一次，此行为不可达；清空是为让"无效=空串"成为显式语义，
    # 而不是靠"调用方 GET_RPC_INFO 失败必 exit"的隐式契约兜底。
    INFO_HASH=""
    INFO_HASH=$(echo "${RPC_RESULT}" | jq -r '.result.infoHash')
    if [ -z "${INFO_HASH}" ]; then
        echo "${RPC_RESULT}" | jq '.result' >&2
        echo -e "$(DATE_TIME) ${ERROR} Failed to get infoHash!" >&2
        return 2
    fi
    [ "${INFO_HASH}" = "null" ] && return 1
    # aria2 把磁力元数据缓存为 <dir>/<infoHash>.torrent，放在任务下载目录
    TORRENT_FILE="${DOWNLOAD_DIR}/${INFO_HASH}.torrent"
}

# 一次性获取所有 RPC 信息（结果、状态、下载目录、infoHash）
# 由 lib/event.sh 的 INIT_EVENT 调用；任何致命错误返回 1，调用方决定是否中止
# GET_INFO_HASH 返回 1（非 BT）属正常情况，不向上传播
GET_RPC_INFO() {
    GET_RPC_RESULT   || return 1
    GET_TASK_STATUS  || return 1
    GET_DOWNLOAD_DIR || return 1
    GET_INFO_HASH
    [ $? -eq 2 ] && return 1
    return 0
}
