#!/usr/bin/env bash
# 日志工具库：终端颜色常量、时间戳函数、任务信息打印模板
# 供事件脚本通过 lib/event.sh 引入；tracker 脚本也可直接 source 本文件

# ANSI 颜色前缀/后缀；所有色码统一为 1;3Xm（亮色 + 加粗），让 ERROR 与 INFO/WARNING 视觉一致
RED_FONT_PREFIX="\033[1;31m"
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

# 写入磁盘日志文件：自动加时间戳和级别标签，不带 ANSI 颜色码。
log_line() {
    local file=$1 level=$2 msg=$3
    echo -e "$(DATE_TIME) [${level}] ${msg}" >> "${file}"
}

# 打印任务信息横幅
# 调用前需设置：TASK_TYPE、DOWNLOAD_PATH、SOURCE_PATH、FILE_PATH、FILE_NUM
# 默认含"移动至目标文件夹"行（需要 TARGET_PATH）；传 no-target 隐藏，用于 DELETE_FILE 场景
TASK_INFO() {
    echo -e "
-------------------------- [${YELLOW_FONT_PREFIX} 任务信息 ${TASK_TYPE} ${FONT_COLOR_SUFFIX}] --------------------------
${LIGHT_PURPLE_FONT_PREFIX}根下载路径:${FONT_COLOR_SUFFIX} ${DOWNLOAD_PATH}
${LIGHT_PURPLE_FONT_PREFIX}任务位置:${FONT_COLOR_SUFFIX} ${SOURCE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}首个文件位置:${FONT_COLOR_SUFFIX} ${FILE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}任务文件数量:${FONT_COLOR_SUFFIX} ${FILE_NUM}"
    [ "${1:-}" = no-target ] || echo -e "${LIGHT_PURPLE_FONT_PREFIX}移动至目标文件夹:${FONT_COLOR_SUFFIX} ${TARGET_PATH}"
    echo "-----------------------------------------------------------------------------------------------------------------------"
}
