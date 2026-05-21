#!/usr/bin/env bash
# 下载开始事件脚本
# aria2 在任务开始时调用，参数：$1=GID $2=文件数量 $3=第一个文件路径
# 功能：检测重复任务（RRT=true 时，若 completed 目录已有同名文件夹则取消本次任务）
# 注意：单文件任务开始时 FILE_PATH 为空，磁力链接开始时 FILE_NUM=0，这两种情况正常跳过

. "$(dirname "$0")/lib/all.sh"

INIT_EVENT completed "$@"  # 初始化路径（目标目录：completed，用于检查是否已存在）

# 磁力/无路径任务跳过；路径错误退出
[ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ] && exit 0
[ "${GET_PATH_INFO}" = "error" ] && { echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"; exit 1; }

# RRT=true 时：发现 completed 目录已有同名文件夹，说明是重复任务
# 删除本地已下载的部分文件，并通过 RPC 取消 aria2 中的任务
if [ "${RRT}" = "true" ] && [ -d "${COMPLETED_DIR}" ] && [ "${TASK_STATUS}" != "error" ]; then
    echo -e "$(DATE_TIME) ${WARNING} 发现目标文件夹已存在当前任务 ${LIGHT_GREEN_FONT_PREFIX}${COMPLETED_DIR}${FONT_COLOR_SUFFIX}"
    echo -e "$(DATE_TIME) ${WARNING} 正在删除该任务，并清除相关文件... ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
    RM_ARIA2
    rm -rf "${SOURCE_PATH}"
    REMOVE_REPEAT_TASK
    exit 0
fi
