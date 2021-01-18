#!/usr/bin/env bash

# Aria2下载目录
DOWNLOAD_PATH='/downloads'
DOWNLOAD_ANI_PATH=${DOWNLOAD_PATH}/${ANIDIR}
DOWNLOAD_MOV_PATH=${DOWNLOAD_PATH}/${MOVDIR}
DOWNLOAD_TVS_PATH=${DOWNLOAD_PATH}/${TVDIR}
DOWNLOAD_CUS_PATH=${DOWNLOAD_PATH}/${CUSDIR}


# 日志保存路径。注释或留空为不保存。
LOG_PATH='/config/delete.log'

# ============================================================

FILE_PATH=$3                                                    # Aria2传递给脚本的文件路径。BT下载有多个文件时该值为文件夹内第一个文件，如/root/Download/a/b/1.mp4

RELATIVE_PATH=${FILE_PATH#${DOWNLOAD_PATH}/}                    # 普通文件路径转换，去掉开头的下载路径。
RELATIVE_ANI_PATH=${FILE_PATH#${DOWNLOAD_ANI_PATH}/}            # 动画片路径转换，去掉开头的下载路径。
RELATIVE_MOV_PATH=${FILE_PATH#${DOWNLOAD_MOV_PATH}/}            # 电影路径转换，去掉开头的下载路径。
RELATIVE_TVS_PATH=${FILE_PATH#${DOWNLOAD_TVS_PATH}/}            # 电视剧、综艺路径转换，去掉开头的下载路径。
RELATIVE_CUS_PATH=${FILE_PATH#${DOWNLOAD_CUS_PATH}/}            # 自定义路径转换，去掉开头的下载路径。

CONTRAST_PATH=${DOWNLOAD_PATH}/${RELATIVE_PATH%%/*}             # 普通文件路径对比判断
CONTRAST_ANI_PATH=${DOWNLOAD_ANI_PATH}/${RELATIVE_ANI_PATH%%/*} # 动画片根文件夹路径对比判断
CONTRAST_MOV_PATH=${DOWNLOAD_MOV_PATH}/${RELATIVE_MOV_PATH%%/*} # 电影根文件夹路径对比判断
CONTRAST_TVS_PATH=${DOWNLOAD_TVS_PATH}/${RELATIVE_TVS_PATH%%/*} # 电视剧、综艺根文件夹路径对比判断
CONTRAST_CUS_PATH=${DOWNLOAD_CUS_PATH}/${RELATIVE_CUS_PATH%%/*} # 自定义路径根文件夹路径对比判断

TOP_PATH=${FILE_PATH%/*}                                        # 普通文件路径转换，BT下载文件夹时为顶层文件夹路径，普通单文件下载时与文件路径相同。
ANI_PATH=${DOWNLOAD_ANI_PATH}/${RELATIVE_ANI_PATH}              # 动画片路径判断
MOV_PATH=${DOWNLOAD_MOV_PATH}/${RELATIVE_MOV_PATH}              # 电影路径判断
TVS_PATH=${DOWNLOAD_TVS_PATH}/${RELATIVE_TVS_PATH}              # 电视剧、综艺路径判断
CUS_PATH=${DOWNLOAD_CUS_PATH}/${RELATIVE_CUS_PATH}              # 自定义路径判断

# ============================================================

RED_FONT_PREFIX="\033[31m"
LIGHT_GREEN_FONT_PREFIX="\033[1;32m"
YELLOW_FONT_PREFIX="\033[1;33m"
LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${LIGHT_GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
WARRING="[${YELLOW_FONT_PREFIX}WARRING${FONT_COLOR_SUFFIX}]"

# ============================================================

TASK_INFO() {
    echo -e "
-------------------------- [${YELLOW_FONT_PREFIX}TASK INFO${FONT_COLOR_SUFFIX}] --------------------------
${LIGHT_PURPLE_FONT_PREFIX}Download path:${FONT_COLOR_SUFFIX} ${SOURCE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}File path:${FONT_COLOR_SUFFIX} ${FILE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}.aria2 path:${FONT_COLOR_SUFFIX} ${SOURCE_PATH}.aria2
-------------------------- [${YELLOW_FONT_PREFIX}TASK INFO${FONT_COLOR_SUFFIX}] --------------------------
"
}

# =============================RM_ARIA2=============================

RM_ARIA2() {
    if [ -e "${SOURCE_PATH}.aria2" ]; then
        echo -e "$(date +"%m/%d %H:%M:%S") Clean up ${SOURCE_PATH}.aria2"
        rm -vf "${SOURCE_PATH}.aria2"
    fi
}


# ============================================================

if [ -z $2 ]; then
    echo && echo -e "${ERROR} This script can only be used by passing parameters through Aria2."
    echo && echo -e "${WARRING} 直接运行此脚本可能导致无法开机！"
    exit 1
elif [ $2 -eq 0 ]; then
    exit 0
fi

# =============================判断文件路径、执行移动文件=============================

if [ -e "${FILE_PATH}" ] && [ $2 -eq 1 ]; then # 普通单文件下载任务
    SOURCE_PATH="${FILE_PATH}"
    RM_ARIA2
    exit 0
elif [ "${ANI_PATH}" = "${FILE_PATH}" ] && [ $2 -gt 1 ]; then # BT下载（动画片文件夹内文件数大于1），移动整个文件夹到设定的文件夹。
    SOURCE_PATH="${CONTRAST_ANI_PATH}"
    RM_ARIA2
    exit 0
elif [ "${MOV_PATH}" = "${FILE_PATH}" ] && [ $2 -gt 1 ]; then # BT下载（电影文件夹内文件数大于1），移动整个文件夹到设定的文件夹。
    SOURCE_PATH="${CONTRAST_MOV_PATH}"
    RM_ARIA2
    exit 0
elif [ "${TVS_PATH}" = "${FILE_PATH}" ] && [ $2 -gt 1 ]; then # BT下载（电视剧、综艺文件夹内文件数大于1），移动整个文件夹到设定的文件夹。
    SOURCE_PATH="${CONTRAST_TVS_PATH}"
    RM_ARIA2
    exit 0
elif [ "${CUS_PATH}" = "${FILE_PATH}" ] && [ $2 -gt 1 ]; then # 自定义路径下载（自定义路径文件夹内文件数大于1），移动整个文件夹到设定的文件夹。
    SOURCE_PATH="${CONTRAST_CUS_PATH}"
    RM_ARIA2
    exit 0
elif [ "${CONTRAST_PATH}" != "${FILE_PATH}" ] && [ $2 -gt 1 ]; then # BT下载（文件夹内文件数大于1），移动整个文件夹到设定的文件夹。
    SOURCE_PATH="${TOP_PATH}"
    RM_ARIA2
    exit 0
fi

echo -e "${ERROR} Unknown error."
TASK_INFO
exit 1
