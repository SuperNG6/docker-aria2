#!/usr/bin/env bash

# Aria2下载目录
DOWNLOAD_PATH='/downloads'
DOWNLOAD_ANI_PATH=${DOWNLOAD_PATH}/${ANIDIR}
DOWNLOAD_MOV_PATH=${DOWNLOAD_PATH}/${MOVDIR}
DOWNLOAD_TVS_PATH=${DOWNLOAD_PATH}/${TVDIR}
DOWNLOAD_CUS_PATH=${DOWNLOAD_PATH}/${CUSDIR}

# 目标目录
TARGET_DIR='/downloads/completed'
TARGET_ANI_DIR=${TARGET_DIR}/${ANIDIR}
TARGET_MOV_DIR=${TARGET_DIR}/${MOVDIR}
TARGET_TVS_DIR=${TARGET_DIR}/${TVDIR}
TARGET_CUS_DIR=${TARGET_DIR}/${CUSDIR}


# 日志保存路径。注释或留空为不保存。
SCRIPT_CONF="/config/文件过滤.conf"
LOG_PATH='/config/move.log'
CF_LOG_PATH='/config/文件过滤日志.log'

#============================================================

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
${LIGHT_PURPLE_FONT_PREFIX}Download path:${FONT_COLOR_SUFFIX} ${DOWNLOAD_PATH}
${LIGHT_PURPLE_FONT_PREFIX}File path:${FONT_COLOR_SUFFIX} ${FILE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}Source path:${FONT_COLOR_SUFFIX} ${SOURCE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}Target path:${FONT_COLOR_SUFFIX} ${TARGET_PATH}
-------------------------- [${YELLOW_FONT_PREFIX}TASK INFO${FONT_COLOR_SUFFIX}] --------------------------
"
}

# =============================移动文件=============================

MOVE_FILE() {
    echo -e "$(date +"%m/%d %H:%M:%S") ${INFO} Start move files ..."
    TASK_INFO
    mkdir -p ${TARGET_PATH}
    mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
    MOVE_EXIT_CODE=$?
    if [ ${MOVE_EXIT_CODE} -eq 0 ]; then
        echo -e "$(date +"%m/%d %H:%M:%S") ${INFO} Move done: ${SOURCE_PATH} -> ${TARGET_PATH}"
        [ $LOG_PATH ] && echo -e "$(date +"%m/%d %H:%M:%S") [INFO] Move done: ${SOURCE_PATH} -> ${TARGET_PATH}" >>${LOG_PATH}
    else
        echo -e "$(date +"%m/%d %H:%M:%S") ${ERROR} Move failed: ${SOURCE_PATH}"
        [ $LOG_PATH ] && echo -e "$(date +"%m/%d %H:%M:%S") [ERROR] Move failed: ${SOURCE_PATH}" >>${LOG_PATH}
    fi
    RM_AIRA2
}

# =============================RM_AIRA2=============================

RM_ARIA_INFO() {
    echo -e "
-------------------------- [${YELLOW_FONT_PREFIX}RM .ARIA2 INFO${FONT_COLOR_SUFFIX}] --------------------------
${LIGHT_PURPLE_FONT_PREFIX}Download path:${FONT_COLOR_SUFFIX} ${DOWNLOAD_PATH}
${LIGHT_PURPLE_FONT_PREFIX}File path:${FONT_COLOR_SUFFIX} ${FILE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}.aria2 path:${FONT_COLOR_SUFFIX} ${SOURCE_PATH}.aria2
-------------------------- [${YELLOW_FONT_PREFIX}RM .ARIA2 INFO${FONT_COLOR_SUFFIX}] --------------------------
"
}

RM_AIRA2() {
    RM_ARIA_INFO
    echo -e "$(date +"%m/%d %H:%M:%S") Clean up extra files ..."
    if [ -e "${SOURCE_PATH}.aria2" ]; then
        DOT_ARIA2_FILE="${SOURCE_PATH}.aria2"
        [ -e "${DOT_ARIA2_FILE}" ] && rm -vf "${SOURCE_PATH}.aria2"
    fi
}

# =============================读取conf文件设置=============================

LOAD_SCRIPT_CONF() {
    MIN_SIZE="$(grep ^min-size "${SCRIPT_CONF}" | cut -d= -f2-)"
    INCLUDE_FILE="$(grep ^include-file "${SCRIPT_CONF}" | cut -d= -f2-)"
    EXCLUDE_FILE="$(grep ^exclude-file "${SCRIPT_CONF}" | cut -d= -f2-)"
}

DELETE_EXCLUDE_FILE() {
    if [[ ${FILE_NUM} -gt 1 ]] && [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} ]]; then
        echo -e "${INFO} Deleting excluded files ..."
        [[ -n ${MIN_SIZE} ]] && find "${SOURCE_PATH}" -type f -size -${MIN_SIZE} -print0 | xargs -0 rm -vf | tee -a ${CF_LOG_PATH}
        [[ -n ${EXCLUDE_FILE} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a ${CF_LOG_PATH}
        [[ -n ${INCLUDE_FILE} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a ${CF_LOG_PATH}
    fi
}

DELETE_EMPTY_DIR() {
    if [[ "${DET}" = "true" ]]; then
        echo -e "Deleting empty directory ..."
        find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
    fi
}

# =============================内容过滤=============================

CLEAN_UP() {
    if [ "$CF" == "true" ]; then
        echo -e "$(date +"%m/%d %H:%M:%S") 被过滤文件的任务路径: ${SOURCE_PATH}" | tee -a ${CF_LOG_PATH}
        LOAD_SCRIPT_CONF
        DELETE_EXCLUDE_FILE
        DELETE_EMPTY_DIR
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


if [ "${CONTRAST_PATH}" = "${FILE_PATH}" ] && [ $2 -eq 1 ]; then # 普通单文件下载，不进行任何移动。
    SOURCE_PATH="${FILE_PATH}"
    RM_AIRA2
    exit 0
elif [ "${ANI_PATH}" = "${FILE_PATH}" ] && [ $2 -eq 1 ]; then # 动画片目录中的单文件下载，保留目录结构移动
    SOURCE_PATH="${FILE_PATH}"
    TARGET_PATH="${TARGET_ANI_DIR}"
    MOVE_FILE
    exit 0
elif [ "${MOV_PATH}" = "${FILE_PATH}" ] && [ $2 -eq 1 ]; then # 电影目录中的单文件下载，保留目录结构移动
    SOURCE_PATH="${FILE_PATH}"
    TARGET_PATH="${TARGET_MOV_DIR}"
    MOVE_FILE
    exit 0
elif [ "${TVS_PATH}" = "${FILE_PATH}" ] && [ $2 -eq 1 ]; then # 电视剧目录中的单文件下载，保留目录结构移动
    SOURCE_PATH="${FILE_PATH}"
    TARGET_PATH="${TARGET_TVS_DIR}"
    MOVE_FILE
    exit 0
elif [ "${CUS_PATH}" = "${FILE_PATH}" ] && [ $2 -eq 1 ]; then # 自定义目录中的单文件下载，保留目录结构移动
    SOURCE_PATH="${FILE_PATH}"
    TARGET_PATH="${TARGET_CUS_DIR}"
    MOVE_FILE
    exit 0
elif [ "${ANI_PATH}" = "${FILE_PATH}" ] && [ $2 -gt 1 ]; then # BT下载（动画片文件夹内文件数大于1），移动整个文件夹到设定的文件夹。
    SOURCE_PATH="${CONTRAST_ANI_PATH}"
    TARGET_PATH="${TARGET_ANI_DIR}"
    CLEAN_UP
    MOVE_FILE
    exit 0
elif [ "${MOV_PATH}" = "${FILE_PATH}" ] && [ $2 -gt 1 ]; then # BT下载（电影文件夹内文件数大于1），移动整个文件夹到设定的文件夹。
    SOURCE_PATH="${CONTRAST_MOV_PATH}"
    TARGET_PATH="${TARGET_MOV_DIR}"
    CLEAN_UP
    MOVE_FILE
    exit 0
elif [ "${TVS_PATH}" = "${FILE_PATH}" ] && [ $2 -gt 1 ]; then # BT下载（电视剧、综艺文件夹内文件数大于1），移动整个文件夹到设定的文件夹。
    SOURCE_PATH="${CONTRAST_TVS_PATH}"
    TARGET_PATH="${TARGET_TVS_DIR}"
    CLEAN_UP
    MOVE_FILE
    exit 0
elif [ "${CUS_PATH}" = "${FILE_PATH}" ] && [ $2 -gt 1 ]; then # 自定义路径下载（自定义路径文件夹内文件数大于1），移动整个文件夹到设定的文件夹。
    SOURCE_PATH="${CONTRAST_CUS_PATH}"
    TARGET_PATH="${TARGET_CUS_DIR}"
    CLEAN_UP
    MOVE_FILE
    exit 0
elif [ "${CONTRAST_PATH}" != "${FILE_PATH}" ] && [ $2 -gt 1 ]; then # BT下载（文件夹内文件数大于1），移动整个文件夹到设定的文件夹。
    SOURCE_PATH="${TOP_PATH}"
    TARGET_PATH_ORIGINAL="${TARGET_DIR}/${RELATIVE_PATH%/*}"
    TARGET_PATH="${TARGET_PATH_ORIGINAL%/*}"
    CLEAN_UP
    MOVE_FILE
    exit 0
elif [ "${CONTRAST_PATH}" != "${FILE_PATH}" ] && [ $2 -eq 1 ]; then # 第三方度盘工具下载（子文件夹或多级目录等情况下的单文件下载）、BT下载（文件夹内文件数等于1），移动文件到设定的文件夹下的相同路径文件夹。
    SOURCE_PATH="${TOP_PATH}"
    TARGET_PATH_ORIGINAL="${TARGET_DIR}/${RELATIVE_PATH%/*}"
    TARGET_PATH="${TARGET_PATH_ORIGINAL%/*}"
    MOVE_FILE
    exit 0
fi

echo -e "${ERROR} Unknown error."
TASK_INFO
exit 1
