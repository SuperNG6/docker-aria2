#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"
. "$(dirname $0)/rpc_info"

TASK_GID=$1
FILE_NUM=$2
FILE_PATH=$3

GET_BASE_PATH
RECYCLE_PATH
GET_RPC_INFO
GET_FINAL_PATH

STOP() {
    if [ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ]; then
        exit 0
    elif [ "${GET_PATH_INFO}" = "error" ]; then
        echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"
        exit 1
    elif [ "${RMTASK}" = "recycle" ] && [ "${TASK_STATUS}" != "error" ]; then
        MOVE_RECYCLE
        CHECK_TORRENT
        RM_ARIA2
        exit 0
    elif [ "${RMTASK}" = "delete" ] && [ "${TASK_STATUS}" != "error" ]; then
        DELETE_FILE
        CHECK_TORRENT
        RM_ARIA2
        exit 0
    elif [ "${RMTASK}" = "rmaria" ] && [ "${TASK_STATUS}" != "error" ]; then
        CHECK_TORRENT
        RM_ARIA2
        exit 0
    fi
}

# 判断`SOURCE_PATH`是否存：start.sh可能已经删除文件或文件夹，不存在`SOURCE_PATH`则不进行任何操作
if [ -d "${SOURCE_PATH}" ] || [ -e "${SOURCE_PATH}" ]; then
    STOP
fi
