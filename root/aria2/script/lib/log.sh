#!/usr/bin/env bash

RED_FONT_PREFIX="\033[31m"
LIGHT_GREEN_FONT_PREFIX="\033[1;32m"
YELLOW_FONT_PREFIX="\033[1;33m"
LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${LIGHT_GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
WARNING="[${YELLOW_FONT_PREFIX}WARNING${FONT_COLOR_SUFFIX}]"

DATE_TIME() {
    date +"%Y/%m/%d %H:%M:%S"
}

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
