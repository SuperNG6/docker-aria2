#!/usr/bin/env bash

GET_BASE_PATH() {
    DOWNLOAD_PATH="/downloads"
    BAK_TORRENT_DIR="/config/backup-torrent"
    SCRIPT_CONF="/config/文件过滤.conf"
    CF_LOG="/config/logs/文件过滤日志.log"
    MOVE_LOG="/config/logs/move.log"
    DELETE_LOG="/config/logs/delete.log"
    RECYCLE_LOG="/config/logs/recycle.log"
}

COMPLETED_PATH() {
    TARGET_DIR="${DOWNLOAD_PATH}/completed"
}

RECYCLE_PATH() {
    TARGET_DIR="${DOWNLOAD_PATH}/recycle"
}

GET_TARGET_PATH() {
    RELATIVE_PATH="${SOURCE_PATH#"${DOWNLOAD_PATH}/"}"
    TARGET_PATH="${TARGET_DIR}/$(dirname "${RELATIVE_PATH}")"
    if [ "${TARGET_PATH}" == "${TARGET_DIR}//" ]; then
        GET_PATH_INFO="error"
        return
    elif [ "${TARGET_PATH}" = "${TARGET_DIR}/." ]; then
        TARGET_PATH="${TARGET_DIR}"
    fi
}

GET_FINAL_PATH() {
    if [ -z "${FILE_PATH}" ]; then
        return
    elif [ "${FILE_NUM}" -gt 1 ] || [ "$(dirname "${FILE_PATH}")" != "${DOWNLOAD_DIR}" ]; then
        RELATIVE_PATH="${FILE_PATH#"${DOWNLOAD_DIR}/"}"
        TASK_NAME="${RELATIVE_PATH%%/*}"
        SOURCE_PATH="${DOWNLOAD_DIR}/${TASK_NAME}"
        GET_TARGET_PATH
        COMPLETED_DIR="${TARGET_PATH}/${TASK_NAME}"
        return
    elif [ "${FILE_NUM}" -eq 1 ]; then
        SOURCE_PATH="${FILE_PATH}"
        RELATIVE_PATH="${FILE_PATH#"${DOWNLOAD_DIR}/"}"
        TASK_NAME="${RELATIVE_PATH##*/}"
        TASK_NAME="${TASK_NAME%.*}"
        GET_TARGET_PATH
        return
    fi
}
