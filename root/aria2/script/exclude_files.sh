#!/usr/bin/env bash

SCRIPT_CONF="/config/文件过滤.conf"

# Aria2下载目录
DOWNLOAD_PATH='/downloads'
DOWNLOAD_ANI_PATH=${DOWNLOAD_PATH}/${ANIDIR}
DOWNLOAD_MOV_PATH=${DOWNLOAD_PATH}/${MOVDIR}
DOWNLOAD_TVS_PATH=${DOWNLOAD_PATH}/${TVDIR}
DOWNLOAD_CUS_PATH=${DOWNLOAD_PATH}/${CUSDIR}

# 日志保存路径。注释或留空为不保存。
LOG_PATH='/config/文件过滤日志.log'

# ============================================================

FILE_PATH=$3                                                    # Aria2传递给脚本的文件路径。BT下载有多个文件时该值为文件夹内第一个文件，如/root/Download/a/b/1.mp4
FILE_NUM=$2
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



# =============================获取文件夹路径=============================

if [ -e "${FILE_PATH}.aria2" ]; then
    TASK_PATH="${FILE_PATH}"
elif [ -e "${CONTRAST_PATH}.aria2" ]; then
    TASK_PATH="${CONTRAST_PATH}"
elif [ -e "${CONTRAST_ANI_PATH}.aria2" ]; then
    TASK_PATH="${CONTRAST_ANI_PATH}"
elif [ -e "${CONTRAST_MOV_PATH}.aria2" ]; then
    TASK_PATH="${CONTRAST_MOV_PATH}"
elif [ -e "${CONTRAST_TVS_PATH}.aria2" ]; then
    TASK_PATH="${CONTRAST_TVS_PATH}"
elif [ -e "${CONTRAST_CUS_PATH}.aria2" ]; then
    TASK_PATH="${CONTRAST_CUS_PATH}"
elif [ -e "${TOP_PATH}.aria2" ]; then
    TASK_PATH="${TOP_PATH}"
fi

# =============================判断文件路径、执行移动文件=============================


LOAD_SCRIPT_CONF() {
    MIN_SIZE="$(grep ^min-size "${SCRIPT_CONF}" | cut -d= -f2-)"
    INCLUDE_FILE="$(grep ^include-file "${SCRIPT_CONF}" | cut -d= -f2-)"
    EXCLUDE_FILE="$(grep ^exclude-file "${SCRIPT_CONF}" | cut -d= -f2-)"
}

DELETE_EXCLUDE_FILE() {
    if [[ ${FILE_NUM} -gt 1 ]] && [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} ]]; then
        echo -e "${INFO} Deleting excluded files ..."
        [[ -n ${MIN_SIZE} ]] && find "${TASK_PATH}" -type f -size -${MIN_SIZE} -print0 | xargs -0 rm -vf
        [[ -n ${EXCLUDE_FILE} ]] && find "${TASK_PATH}" -type f -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a ${LOG_PATH}
        [[ -n ${INCLUDE_FILE} ]] && find "${TASK_PATH}" -type f -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a ${LOG_PATH}
    fi
}

CLEAN_UP() {
    echo -e "$(date +"%m/%d %H:%M:%S") ${INFO} 被移出文件的路径: ${TASK_PATH}" >> ${LOG_PATH}
    DELETE_EXCLUDE_FILE
}