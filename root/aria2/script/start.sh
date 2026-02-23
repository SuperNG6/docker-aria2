#!/usr/bin/env bash

. "$(dirname "$0")/hook_common"

LOAD_HOOK_CONTEXT "$1" "$2" "$3" "completed"

START() {
    # aria2 开始任务时，单文件不会传递 `FILE_PATH`，磁力任务 `FILE_NUM` 为 0；
    # `TASK_STATUS` 为 `error` 时，多为存在 `.aria2` 控制文件且任务文件已存在。
    # 判断 `COMPLETED_DIR` 是否已存在任务，若存在则通过 RPC 删除重复任务并清理相关文件。
    EXIT_IF_INVALID_TASK
    if [ -d "${COMPLETED_DIR}" ] && [ "${TASK_STATUS}" != "error" ]; then
        echo -e "$(DATE_TIME) ${WARNING} 发现目标文件夹已存在当前任务 ${LIGHT_GREEN_FONT_PREFIX}${COMPLETED_DIR}${FONT_COLOR_SUFFIX}"
        echo -e "$(DATE_TIME) ${WARNING} 正在删除该任务，并清除相关文件... ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
        RM_ARIA2
        rm -rf "${SOURCE_PATH}"
        REMOVE_REPEAT_TASK
        exit 0
    fi
}

if [ "${RRT}" = "true" ]; then
    START
fi
