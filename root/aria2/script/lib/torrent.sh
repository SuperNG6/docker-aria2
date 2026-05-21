#!/usr/bin/env bash
# 种子文件处理库：根据 TOR 配置决定任务完成/停止后如何处理 .torrent 文件
# TORRENT_FILE 由 rpc.sh 的 GET_INFO_HASH 通过 infoHash 推算出路径
# 仅 BT 任务且 bt-save-metadata=true（SMD=true 时启用）才会有 .torrent 文件

# 根据 TOR 变量对种子文件执行对应操作
# TOR 取值说明（在 config.sh 中定义）：
#   retain        - 不做任何处理，种子文件留在原位
#   delete        - 直接删除种子文件
#   rename        - 重命名为 任务名.torrent，放回下载目录（方便再次使用）
#   backup        - 原名移动到 /config/backup-torrent 目录
#   backup-rename - 重命名为 任务名.torrent 并移动到 /config/backup-torrent 目录（默认值）
# 未知值时打印警告并保留原文件，避免静默丢失数据
HANDLE_TORRENT() {
    case "${TOR}" in
        retain)
            return
            ;;
        delete)
            echo -e "$(DATE_TIME) ${INFO} 已删除种子文件: ${TORRENT_FILE}"
            rm -f "${TORRENT_FILE}"
            ;;
        rename)
            echo -e "$(DATE_TIME) ${INFO} 重命名种子文件: ${TORRENT_FILE} -> ${DOWNLOAD_DIR}/${TASK_NAME}.torrent"
            mv -f "${TORRENT_FILE}" "${DOWNLOAD_DIR}/${TASK_NAME}.torrent"
            ;;
        backup)
            echo -e "$(DATE_TIME) ${INFO} 备份种子文件: ${TORRENT_FILE} -> ${BAK_TORRENT_DIR}/"
            mv -f "${TORRENT_FILE}" "${BAK_TORRENT_DIR}/"
            ;;
        backup-rename)
            echo -e "$(DATE_TIME) ${INFO} 重命名并备份种子文件: ${TORRENT_FILE} -> ${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
            mv -f "${TORRENT_FILE}" "${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
            ;;
        *)
            echo -e "$(DATE_TIME) ${WARNING} 未知的 TOR 值: ${TOR}（保留原文件不处理）" >&2
            ;;
    esac
}

# 检查种子文件是否存在，存在则调用 HANDLE_TORRENT 处理
# 普通 HTTP/FTP 任务没有 .torrent 文件，此函数直接跳过
CHECK_TORRENT() {
    if [ -n "${TORRENT_FILE}" ] && [ -e "${TORRENT_FILE}" ]; then
        HANDLE_TORRENT
    fi
}
