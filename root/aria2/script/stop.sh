#!/usr/bin/env bash

. "$(dirname "$0")/hook_common"

LOAD_HOOK_CONTEXT "$1" "$2" "$3" "recycle"

# 下载停止钩子：根据 remove-task 配置执行删除、回收或仅删 .aria2。
STOP() {
    EXIT_IF_INVALID_TASK
    if [ "${RMTASK}" = "recycle" ] && [ "${TASK_STATUS}" != "error" ]; then
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
if [ -e "${SOURCE_PATH}" ]; then
    STOP
fi
