#!/usr/bin/env bash

RM_ARIA2() {
    if [ -e "${SOURCE_PATH}.aria2" ]; then
        rm -f "${SOURCE_PATH}.aria2"
        echo -e "$(DATE_TIME) ${INFO} 已删除文件: ${SOURCE_PATH}.aria2"
    fi
}

CLEAN_UP() {
    RM_ARIA2
    if [ "$CF" == "true" ] && [ ${FILE_NUM} -gt 1 ] && [ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]; then
        echo -e "$(DATE_TIME) ${INFO} 被过滤文件的任务路径: ${SOURCE_PATH}" | tee -a "${CF_LOG}"
        LOAD_SCRIPT_CONF
        DELETE_EXCLUDE_FILE
        DELETE_EMPTY_DIR
    fi
}

MOVE_FILE() {
    if [ "${MOVE}" = "false" ]; then
        RM_ARIA2
        return
    elif [ "${MOVE}" = "dmof" ] && [ "${DOWNLOAD_DIR}" = "${DOWNLOAD_PATH}" ] && [ ${FILE_NUM} -eq 1 ]; then
        RM_ARIA2
        return
    elif [ "${MOVE}" = "true" ] || [ "${MOVE}" = "dmof" ]; then
        TASK_TYPE=": 移动任务文件"
        TASK_INFO
        CLEAN_UP
        echo -e "$(DATE_TIME) ${INFO} 开始移动该任务文件到: ${LIGHT_GREEN_FONT_PREFIX}${TARGET_PATH}${FONT_COLOR_SUFFIX}"
        mkdir -p "${TARGET_PATH}"

        SOURCE_DEVICE=$(stat -c %d "${SOURCE_PATH}")
        TARGET_DEVICE=$(stat -c %d "${TARGET_PATH}")

        if [ "${SOURCE_DEVICE}" != "${TARGET_DEVICE}" ]; then
            echo -e "$(DATE_TIME) ${INFO} 检测到跨磁盘移动，正在检查目标磁盘空间..."
            REQUIRED_SPACE=$(du -sb "${SOURCE_PATH}" | awk '{print $1}')
            AVAILABLE_SPACE=$(df --output=avail -B1 "${TARGET_PATH}" | sed '1d')

            if (( AVAILABLE_SPACE < REQUIRED_SPACE )); then
                REQUIRED_GB=$(awk "BEGIN {printf \"%.2f\", ${REQUIRED_SPACE}/1024/1024/1024}")
                AVAILABLE_GB=$(awk "BEGIN {printf \"%.2f\", ${AVAILABLE_SPACE}/1024/1024/1024}")
                echo -e "$(DATE_TIME) ${ERROR} 目标磁盘空间不足！无法移动文件。"
                echo -e "$(DATE_TIME) ${ERROR} 所需空间: ${REQUIRED_GB} GB, 目标可用空间: ${AVAILABLE_GB} GB."
                [ "${MOVE_LOG}" ] && echo -e "$(DATE_TIME) [ERROR] 目标磁盘空间不足，移动失败。所需空间:${REQUIRED_GB} GB, 可用空间:${AVAILABLE_GB} GB. 源:${SOURCE_PATH} -> 目标:${TARGET_PATH}" >>"${MOVE_LOG}"

                FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
                echo -e "$(DATE_TIME) ${WARNING} 尝试将任务移动到: ${FAIL_DIR}"
                mkdir -p "${FAIL_DIR}"
                mv -f "${SOURCE_PATH}" "${FAIL_DIR}"
                MOVE_FAIL_EXIT_CODE=$?
                if [ ${MOVE_FAIL_EXIT_CODE} -eq 0 ]; then
                    echo -e "$(DATE_TIME) ${INFO} 因目标磁盘空间不足，已将文件移动至: ${SOURCE_PATH} -> ${FAIL_DIR}"
                    [ "${MOVE_LOG}" ] && echo -e "$(DATE_TIME) [INFO] 因目标磁盘空间不足，已将文件移动至: ${SOURCE_PATH} -> ${FAIL_DIR}" >>"${MOVE_LOG}"
                else
                    echo -e "$(DATE_TIME) ${ERROR} 移动到 ${FAIL_DIR} 依然失败: ${SOURCE_PATH}"
                    [ "${MOVE_LOG}" ] && echo -e "$(DATE_TIME) [ERROR] 移动到 ${FAIL_DIR} 依然失败: ${SOURCE_PATH}" >>"${MOVE_LOG}"
                fi
                return 1
            fi
            echo -e "$(DATE_TIME) ${INFO} 目标磁盘空间充足。"
        else
            echo -e "$(DATE_TIME) ${INFO} 检测为同磁盘移动，无需检查空间。"
        fi

        mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
        MOVE_EXIT_CODE=$?
        if [ ${MOVE_EXIT_CODE} -eq 0 ]; then
            echo -e "$(DATE_TIME) ${INFO} 已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}"
            [ "${MOVE_LOG}" ] && echo -e "$(DATE_TIME) [INFO] 已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}" >>"${MOVE_LOG}"
        else
            echo -e "$(DATE_TIME) ${ERROR} 文件移动失败: ${SOURCE_PATH}"
            [ "${MOVE_LOG}" ] && echo -e "$(DATE_TIME) [ERROR] 文件移动失败: ${SOURCE_PATH}" >>"${MOVE_LOG}"

            FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
            mkdir -p "${FAIL_DIR}"
            mv -f "${SOURCE_PATH}" "${FAIL_DIR}"
            MOVE_FAIL_EXIT_CODE=$?
            if [ ${MOVE_FAIL_EXIT_CODE} -eq 0 ]; then
                echo -e "$(DATE_TIME) ${INFO} 已将文件移动至: ${SOURCE_PATH} -> ${FAIL_DIR}"
                [ "${MOVE_LOG}" ] && echo -e "$(DATE_TIME) [INFO] 已将文件移动至: ${SOURCE_PATH} -> ${FAIL_DIR}" >>"${MOVE_LOG}"
            else
                echo -e "$(DATE_TIME) ${ERROR} 移动到 ${FAIL_DIR} 依然失败: ${SOURCE_PATH}"
                [ "${MOVE_LOG}" ] && echo -e "$(DATE_TIME) [ERROR] 移动到 ${FAIL_DIR} 依然失败: ${SOURCE_PATH}" >>"${MOVE_LOG}"
            fi
        fi
    fi
}

DELETE_FILE() {
    TASK_TYPE=": 删除任务文件"
    DELETE_INFO
    echo -e "$(DATE_TIME) ${INFO} 下载已停止，开始删除文件..."
    rm -rf "${SOURCE_PATH}"
    DELETE_EXIT_CODE=$?
    if [ ${DELETE_EXIT_CODE} -eq 0 ]; then
        echo -e "$(DATE_TIME) ${INFO} 已删除文件: ${SOURCE_PATH}"
        [ ${DELETE_LOG} ] && echo -e "$(DATE_TIME) [INFO] 文件删除成功: ${SOURCE_PATH}" >>"${DELETE_LOG}"
    else
        echo -e "$(DATE_TIME) ${ERROR} delete failed: ${SOURCE_PATH}"
        [ ${DELETE_LOG} ] && echo -e "$(DATE_TIME) [ERROR] 文件删除失败: ${SOURCE_PATH}" >>"${DELETE_LOG}"
    fi
}

MOVE_RECYCLE() {
    TASK_TYPE=": 移动任务文件至回收站"
    TASK_INFO
    echo -e "$(DATE_TIME) ${INFO} 开始移动已下载的任务至回收站 ${LIGHT_GREEN_FONT_PREFIX}${TARGET_PATH}${FONT_COLOR_SUFFIX}"
    mkdir -p "${TARGET_PATH}"
    mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
    MOVE_EXIT_CODE=$?
    if [ ${MOVE_EXIT_CODE} -eq 0 ]; then
        echo -e "$(DATE_TIME) ${INFO} 已移至回收站: ${SOURCE_PATH} -> ${TARGET_PATH}"
        [ ${RECYCLE_LOG} ] && echo -e "$(DATE_TIME) [INFO] 成功移动文件到回收站: ${SOURCE_PATH} -> ${TARGET_PATH}" >>"${RECYCLE_LOG}"
    else
        echo -e "$(DATE_TIME) ${ERROR} 移动文件到回收站失败: ${SOURCE_PATH}"
        echo -e "$(DATE_TIME) ${INFO} 尝试删除文件: ${SOURCE_PATH}"
        rm -rf "${SOURCE_PATH}"
        DELETE_EXIT_CODE=$?
        if [ ${DELETE_EXIT_CODE} -eq 0 ]; then
            echo -e "$(DATE_TIME) ${INFO} 已删除文件: ${SOURCE_PATH}"
            [ ${RECYCLE_LOG} ] && echo -e "$(DATE_TIME) [WARNING] 移动文件到回收站失败，已删除文件: ${SOURCE_PATH}" >>"${RECYCLE_LOG}"
        else
            echo -e "$(DATE_TIME) ${ERROR} 删除文件也失败: ${SOURCE_PATH}"
            [ ${RECYCLE_LOG} ] && echo -e "$(DATE_TIME) [ERROR] 移动到回收站和删除文件都失败: ${SOURCE_PATH}" >>"${RECYCLE_LOG}"
        fi
    fi
}
