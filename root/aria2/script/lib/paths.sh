#!/usr/bin/env bash
# 路径计算库：确定下载根目录、目标目录、任务源路径等
# 调用顺序很重要：GET_BASE_PATH → COMPLETED_PATH 或 RECYCLE_PATH → GET_RPC_INFO → GET_FINAL_PATH
# 由 lib/all.sh 的 INIT_EVENT 按正确顺序调用，不建议在事件脚本里单独调用

# 设置项目全局路径常量（每次事件脚本触发时调用一次）
GET_BASE_PATH() {
    DOWNLOAD_PATH="/downloads"               # aria2 根下载目录（容器内固定路径，对应卷挂载点）
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
# SOURCE_PATH 不在 DOWNLOAD_PATH 范围内（aria2 dir 配错指到 /downloads 之外）→ 标记 error
GET_TARGET_PATH() {
    case "${SOURCE_PATH}" in
        "${DOWNLOAD_PATH}"|"${DOWNLOAD_PATH}/"*) ;;
        *)
            # 越界：拒绝在 completed/recycle 下凭空拼出 /data 之类的怪路径
            GET_PATH_INFO="error"
            return
            ;;
    esac
    RELATIVE_PATH="${SOURCE_PATH#"${DOWNLOAD_PATH}/"}"
    TARGET_PATH="${TARGET_DIR}/$(dirname "${RELATIVE_PATH}")"
    if [ "${TARGET_PATH}" = "${TARGET_DIR}//" ]; then
        # SOURCE_PATH == DOWNLOAD_PATH（仅 / 前缀剥离后变空），路径计算有误
        GET_PATH_INFO="error"
        return
    elif [ "${TARGET_PATH}" = "${TARGET_DIR}/." ]; then
        # 任务直接位于根下载目录，目标路径就是 TARGET_DIR 本身
        TARGET_PATH="${TARGET_DIR}"
    fi
}

# 根据 aria2 传入的 FILE_PATH、FILE_NUM 以及 RPC 取到的 INFO_HASH 决定任务源路径
#
# 多文件 / BT 文件夹任务 → SOURCE_PATH = 任务文件夹（整移）
#   触发条件：FILE_NUM > 1（多文件 torrent 或 多 URI 任务）
#           OR（BT 任务 INFO_HASH != null）AND（文件位于 DOWNLOAD_DIR 的子目录中）
#   语义：torrent 自身定义了文件夹结构（如 单文件种子带文件夹），整体作为一个任务单元处理
#   COMPLETED_DIR 用于 start.sh 检查是否已存在同名文件夹（RRT 重复任务检测）
#
# 单文件 HTTP/FTP 任务 → SOURCE_PATH = 文件本身（只移文件）
#   触发条件：FILE_NUM = 1 AND（非 BT 任务 OR 文件直接位于 DOWNLOAD_DIR 根）
#   语义：HTTP 单文件没有"自带文件夹"概念，--out=sub/foo.mp4 中的 sub 是用户分类目录
#         可能被多个任务共享；只移文件可避免误整窝端走未完成的兄弟任务
#   说明：单文件任务不设 COMPLETED_DIR，RRT 重复检测对它们不生效（按设计）
GET_FINAL_PATH() {
    if [ -z "${FILE_PATH}" ]; then
        # 磁力链接刚添加时 FILE_PATH 为空，等待元数据
        return
    fi
    RELATIVE_PATH="${FILE_PATH#"${DOWNLOAD_DIR}/"}"
    if [ "${FILE_NUM}" -gt 1 ] \
        || { [ "${INFO_HASH}" != "null" ] && [ "$(dirname "${FILE_PATH}")" != "${DOWNLOAD_DIR}" ]; }; then
        TASK_NAME="${RELATIVE_PATH%%/*}"
        SOURCE_PATH="${DOWNLOAD_DIR}/${TASK_NAME}"
        GET_TARGET_PATH
        COMPLETED_DIR="${TARGET_PATH}/${TASK_NAME}"
    else
        SOURCE_PATH="${FILE_PATH}"
        TASK_NAME="${RELATIVE_PATH##*/}"
        TASK_NAME="${TASK_NAME%.*}"
        GET_TARGET_PATH
    fi
}
