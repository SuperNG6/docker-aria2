#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"
. "$(dirname $0)/rpc_info"

TASK_GID=$1
FILE_NUM=$2
FILE_PATH=$3

GET_BASE_PATH
COMPLETED_PATH
GET_RPC_INFO
GET_FINAL_PATH

START() {
    # aria2开始任务时，单文件不会传递`FILE_PATH`，磁力`FILE_NUM`为0；`TASK_STATUS`为`error`时，多为存在`.aria2控制文件`,任务文件已存在
    # 判断`COMPLETED_DIR`是否存在已完成文件夹，如果有，则通过rpc删除该任务，同时删除任务文件夹和控制文件
    if [ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ]; then
        exit 0
    elif [ "${GET_PATH_INFO}" = "error" ]; then
        echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"
        exit 1
    elif [ -d "${COMPLETED_DIR}" ] && [ "${TASK_STATUS}" != "error" ]; then
        echo -e "$(DATE_TIME) ${WARRING} Repeat task ${LIGHT_GREEN_FONT_PREFIX}${COMPLETED_DIR}${FONT_COLOR_SUFFIX}"
        echo -e "$(DATE_TIME) ${WARRING} Remove task ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
        RM_ARIA2
        rm -rf "${SOURCE_PATH}"
        REMOVE_REPEAT_TASK
        exit 0
    fi
}

if [ "${RRT}" = "true" ]; then
    START
fi
