#!/usr/bin/env bash

. "$(dirname "$0")/lib/all.sh"

INIT_EVENT "$@"
COMPLETED_PATH

# 磁力/无路径任务跳过；路径错误退出
[ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ] && exit 0
[ "${GET_PATH_INFO}" = "error" ] && { echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"; exit 1; }

# aria2 开始任务时单文件不传 FILE_PATH，磁力 FILE_NUM=0；TASK_STATUS=error 时通常是控制文件已存在
# 若已完成目录存在同名任务则删除重复任务及文件
if [ "${RRT}" = "true" ] && [ -d "${COMPLETED_DIR}" ] && [ "${TASK_STATUS}" != "error" ]; then
    echo -e "$(DATE_TIME) ${WARNING} 发现目标文件夹已存在当前任务 ${LIGHT_GREEN_FONT_PREFIX}${COMPLETED_DIR}${FONT_COLOR_SUFFIX}"
    echo -e "$(DATE_TIME) ${WARNING} 正在删除该任务，并清除相关文件... ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
    RM_ARIA2
    rm -rf "${SOURCE_PATH}"
    REMOVE_REPEAT_TASK
    exit 0
fi
