#!/usr/bin/env bash

_LIB="$(dirname "${BASH_SOURCE[0]}")"
. "${_LIB}/log.sh"
. "${_LIB}/config.sh"
. "${_LIB}/paths.sh"
. "${_LIB}/files.sh"
. "${_LIB}/filter.sh"
. "${_LIB}/torrent.sh"
. "${_LIB}/rpc.sh"

# 事件脚本公共初始化：path_type 为 completed 或 recycle，决定 TARGET_DIR 的设置
# 必须在 GET_RPC_INFO 和 GET_FINAL_PATH 之前调用对应的路径函数
INIT_EVENT() {
    local path_type=$1
    TASK_GID=$2
    FILE_NUM=$3
    FILE_PATH=$4
    GET_BASE_PATH
    [ "${path_type}" = "recycle" ] && RECYCLE_PATH || COMPLETED_PATH
    GET_RPC_INFO
    GET_FINAL_PATH
}

# 公共前置检查：磁力/无效任务直接退出，路径错误报错退出
GUARD_EVENT() {
    if [ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ]; then
        exit 0
    elif [ "${GET_PATH_INFO}" = "error" ]; then
        echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"
        exit 1
    fi
}
