#!/usr/bin/env bash
# 路径计算库：确定下载根目录、目标目录、任务源路径等
# 调用顺序很重要：GET_BASE_PATH → COMPLETED_PATH 或 RECYCLE_PATH → GET_RPC_INFO → GET_FINAL_PATH
# 由 lib/all.sh 的 INIT_EVENT 按正确顺序调用，不建议在事件脚本里单独调用

# 设置项目全局路径常量（每次事件脚本触发时调用一次）
GET_BASE_PATH() {
    DOWNLOAD_PATH="/downloads"               # aria2 根下载目录（容器内固定路径）
    BAK_TORRENT_DIR="/config/backup-torrent" # 种子文件备份目录
    FILTER_CONF="/config/文件过滤.conf"        # 文件内容过滤规则配置文件（由 lib/filter.sh 的 LOAD_FILTER_CONF 读取）
    CF_LOG="/config/logs/文件过滤日志.log"    # 过滤操作日志
    MOVE_LOG="/config/logs/move.log"          # 移动操作日志
    DELETE_LOG="/config/logs/delete.log"      # 删除操作日志
    RECYCLE_LOG="/config/logs/recycle.log"    # 回收站操作日志
}

# 设置"移动到已完成"模式的目标根目录
COMPLETED_PATH() {
    TARGET_DIR="${DOWNLOAD_PATH}/completed"
}

# 设置"移动到回收站"模式的目标根目录
RECYCLE_PATH() {
    TARGET_DIR="${DOWNLOAD_PATH}/recycle"
}

# 根据 SOURCE_PATH 计算文件在目标目录中的子路径
# 保留下载目录内的相对层级，使 completed/recycle 目录结构与下载目录一致
# 若 SOURCE_PATH 不在 DOWNLOAD_PATH 下（路径计算错误）则标记为 error
GET_TARGET_PATH() {
    RELATIVE_PATH="${SOURCE_PATH#"${DOWNLOAD_PATH}/"}"
    TARGET_PATH="${TARGET_DIR}/$(dirname "${RELATIVE_PATH}")"
    if [ "${TARGET_PATH}" == "${TARGET_DIR}//" ]; then
        # SOURCE_PATH 不包含 DOWNLOAD_PATH 前缀，说明路径计算有误
        GET_PATH_INFO="error"
        return
    elif [ "${TARGET_PATH}" = "${TARGET_DIR}/." ]; then
        # 任务直接位于根下载目录，目标路径就是 TARGET_DIR 本身
        TARGET_PATH="${TARGET_DIR}"
    fi
}

# 根据 aria2 传入的 FILE_PATH 和 FILE_NUM 确定任务源路径和最终目标路径
# 多文件任务（FILE_NUM > 1 或文件在子目录中）：SOURCE_PATH = 任务文件夹
# 单文件任务（FILE_NUM = 1 且文件直接在下载目录）：SOURCE_PATH = 文件本身
# COMPLETED_DIR 用于 start.sh 判断重复任务时检查目标是否已存在
GET_FINAL_PATH() {
    if [ -z "${FILE_PATH}" ]; then
        # 磁力链接刚添加时 FILE_PATH 为空，等待元数据，跳过
        return
    elif [ "${FILE_NUM}" -gt 1 ] || [ "$(dirname "${FILE_PATH}")" != "${DOWNLOAD_DIR}" ]; then
        # 多文件任务或文件位于子目录：取第一个文件路径中的顶层文件夹名作为任务名
        RELATIVE_PATH="${FILE_PATH#"${DOWNLOAD_DIR}/"}"
        TASK_NAME="${RELATIVE_PATH%%/*}"
        SOURCE_PATH="${DOWNLOAD_DIR}/${TASK_NAME}"
        GET_TARGET_PATH
        COMPLETED_DIR="${TARGET_PATH}/${TASK_NAME}"
        return
    elif [ "${FILE_NUM}" -eq 1 ]; then
        # 单文件任务：SOURCE_PATH 就是文件本身，TASK_NAME 去掉扩展名
        SOURCE_PATH="${FILE_PATH}"
        RELATIVE_PATH="${FILE_PATH#"${DOWNLOAD_DIR}/"}"
        TASK_NAME="${RELATIVE_PATH##*/}"
        TASK_NAME="${TASK_NAME%.*}"
        GET_TARGET_PATH
        return
    fi
}
