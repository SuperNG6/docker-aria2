#!/usr/bin/env bash
# 日志工具库：终端颜色常量、时间戳函数、任务信息打印模板
# 供所有事件脚本和 tracker 脚本通过 lib/all.sh 引入使用

# ANSI 颜色前缀/后缀
RED_FONT_PREFIX="\033[31m"
LIGHT_GREEN_FONT_PREFIX="\033[1;32m"
YELLOW_FONT_PREFIX="\033[1;33m"
LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
FONT_COLOR_SUFFIX="\033[0m"

# 带颜色的日志级别标签
INFO="[${LIGHT_GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
WARNING="[${YELLOW_FONT_PREFIX}WARNING${FONT_COLOR_SUFFIX}]"

# 返回当前时间，格式：2024/01/01 12:00:00
DATE_TIME() {
    date +"%Y/%m/%d %H:%M:%S"
}

# 打印移动任务的详细信息（含目标路径）
# 调用前需设置：TASK_TYPE、DOWNLOAD_PATH、SOURCE_PATH、FILE_PATH、FILE_NUM、TARGET_PATH
TASK_INFO() {
    echo -e "
-------------------------- [${YELLOW_FONT_PREFIX} 任务信息 ${TASK_TYPE} ${FONT_COLOR_SUFFIX}] --------------------------
${LIGHT_PURPLE_FONT_PREFIX}根下载路径:${FONT_COLOR_SUFFIX} ${DOWNLOAD_PATH}
${LIGHT_PURPLE_FONT_PREFIX}任务位置:${FONT_COLOR_SUFFIX} ${SOURCE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}首个文件位置:${FONT_COLOR_SUFFIX} ${FILE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}任务文件数量:${FONT_COLOR_SUFFIX} ${FILE_NUM}
${LIGHT_PURPLE_FONT_PREFIX}移动至目标文件夹:${FONT_COLOR_SUFFIX} ${TARGET_PATH}
-----------------------------------------------------------------------------------------------------------------------
"
}

# 打印删除任务的详细信息（不含目标路径）
# 调用前需设置：TASK_TYPE、DOWNLOAD_PATH、SOURCE_PATH、FILE_PATH、FILE_NUM
DELETE_INFO() {
    echo -e "
-------------------------- [${YELLOW_FONT_PREFIX} 任务信息 ${TASK_TYPE} ${FONT_COLOR_SUFFIX}] --------------------------
${LIGHT_PURPLE_FONT_PREFIX}根下载路径:${FONT_COLOR_SUFFIX} ${DOWNLOAD_PATH}
${LIGHT_PURPLE_FONT_PREFIX}任务位置:${FONT_COLOR_SUFFIX} ${SOURCE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}首个文件位置:${FONT_COLOR_SUFFIX} ${FILE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}任务文件数量:${FONT_COLOR_SUFFIX} ${FILE_NUM}
-----------------------------------------------------------------------------------------------------------------------
"
}
