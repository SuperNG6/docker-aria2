#!/usr/bin/env bash
# 种子文件处理库：根据 TOR 配置决定任务完成/停止后如何处理 .torrent 文件
# TORRENT_FILE 由 rpc.sh 的 GET_INFO_HASH 通过 infoHash 推算出路径

# 根据 TOR 变量对种子文件执行对应操作
# TOR 取值说明（在 config.sh 中定义）：
#   retain       - 不做任何处理，种子文件留在原位
#   delete       - 直接删除种子文件
#   rename       - 重命名为 任务名.torrent，放回下载目录（方便再次使用）
#   backup       - 原名移动到 /config/backup-torrent 目录
#   backup-rename - 重命名为 任务名.torrent 并移动到 /config/backup-torrent 目录（默认值）
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

# 检查种子文件是否存在，存在则调用 HANDLE_TORRENT 处理
# 普通 HTTP/FTP 任务没有 .torrent 文件，此函数直接跳过
CHECK_TORRENT() {
    if [ -e "${TORRENT_FILE}" ]; then
        HANDLE_TORRENT
    fi
}
