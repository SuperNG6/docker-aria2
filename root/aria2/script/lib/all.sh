#!/usr/bin/env bash
# 库入口文件：事件脚本只需 source 本文件即可引入所有库
# 使用 BASH_SOURCE[0] 而非 $0，确保被 source 时路径仍然正确（$0 指向调用者）

_LIB="$(dirname "${BASH_SOURCE[0]}")"
. "${_LIB}/log.sh"     # 颜色常量、DATE_TIME、TASK_INFO、DELETE_INFO
. "${_LIB}/config.sh"  # 读取 setting.conf（LOAD_CONF 在 source 时自动执行）
. "${_LIB}/paths.sh"   # GET_BASE_PATH、COMPLETED_PATH、RECYCLE_PATH、GET_FINAL_PATH
. "${_LIB}/files.sh"   # RM_ARIA2、CLEAN_UP、MOVE_FILE、DELETE_FILE、MOVE_RECYCLE
. "${_LIB}/filter.sh"  # LOAD_SCRIPT_CONF、DELETE_EXCLUDE_FILE、DELETE_EMPTY_DIR
. "${_LIB}/torrent.sh" # HANDLE_TORRENT、CHECK_TORRENT
. "${_LIB}/rpc.sh"     # GET_RPC_INFO 及所有 RPC 子函数

# 事件脚本公共初始化
# path_type：completed（移动到已完成目录）或 recycle（移动到回收站）
# 其余参数 $2 $3 $4 对应 aria2 传入的 GID、文件数量、第一个文件路径
# 调用顺序：GET_BASE_PATH → 路径目录设置 → GET_RPC_INFO → GET_FINAL_PATH
# 顺序不能打乱：GET_FINAL_PATH 依赖 TARGET_DIR（由路径函数设置）和 DOWNLOAD_DIR（由 RPC 返回）
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

# 事件脚本公共前置检查
# 磁力链接任务（FILE_NUM=0）或路径为空时直接退出（正常情况，不是错误）
# 路径计算失败（GET_PATH_INFO=error）时报错退出，避免对错误路径执行文件操作
GUARD_EVENT() {
    if [ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ]; then
        exit 0
    elif [ "${GET_PATH_INFO}" = "error" ]; then
        echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"
        exit 1
    fi
}
