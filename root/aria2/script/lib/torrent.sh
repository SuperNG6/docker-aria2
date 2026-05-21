#!/usr/bin/env bash

HANDLE_TORRENT() {
    if [ "${TOR}" = "retain" ]; then
        return
    elif [ "${TOR}" = "delete" ]; then
        echo -e "$(DATE_TIME) ${INFO} 已删除种子文件: ${TORRENT_FILE}"
        rm -f "${TORRENT_FILE}"
        return
    elif [ "${TOR}" = "rename" ]; then
        echo -e "$(DATE_TIME) ${INFO} 重命名种子文件: ${TORRENT_FILE} -> ${DOWNLOAD_DIR}/${TASK_NAME}.torrent"
        mv -f "${TORRENT_FILE}" "${DOWNLOAD_DIR}/${TASK_NAME}.torrent"
    elif [ "${TOR}" = "backup" ]; then
        echo -e "$(DATE_TIME) ${INFO} 备份种子文件: ${TORRENT_FILE}"
        mv -vf "${TORRENT_FILE}" "${BAK_TORRENT_DIR}"
    elif [ "${TOR}" = "backup-rename" ]; then
        echo -e "$(DATE_TIME) ${INFO} 重命名并备份种子文件: ${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
        mv -f "${TORRENT_FILE}" "${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
    fi
}

CHECK_TORRENT() {
    if [ -e "${TORRENT_FILE}" ]; then
        HANDLE_TORRENT
    fi
}
