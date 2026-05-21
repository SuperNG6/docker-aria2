#!/usr/bin/env bash

_LIB="$(dirname "${BASH_SOURCE[0]}")"
. "${_LIB}/log.sh"
. "${_LIB}/config.sh"
. "${_LIB}/paths.sh"
. "${_LIB}/files.sh"
. "${_LIB}/filter.sh"
. "${_LIB}/torrent.sh"
. "${_LIB}/rpc.sh"

# 事件脚本公共初始化：解析 aria2 传入的三个参数并完成 RPC 查询
INIT_EVENT() {
    TASK_GID=$1
    FILE_NUM=$2
    FILE_PATH=$3
    GET_BASE_PATH
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
