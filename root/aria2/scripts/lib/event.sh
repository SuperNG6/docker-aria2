#!/usr/bin/env bash
# 事件脚本入口：引入公共库，并定义事件初始化、前置检查和路径计算
# 使用 BASH_SOURCE[0] 而非 $0，确保被 source 时路径仍然正确（$0 指向调用者）

_LIB="$(dirname "${BASH_SOURCE[0]}")"
. "${_LIB}/log.sh"     # 颜色常量、DATE_TIME、TASK_INFO
. "${_LIB}/config.sh"  # 读取 setting.conf（LOAD_CONF 在 source 时自动执行）
. "${_LIB}/files.sh"   # RM_ARIA2、CLEAN_UP、MOVE_FILE、DELETE_FILE、MOVE_RECYCLE
. "${_LIB}/filter.sh"  # LOAD_FILTER_CONF、DELETE_EXCLUDE_FILE、DELETE_EMPTY_DIR
. "${_LIB}/torrent.sh" # HANDLE_TORRENT、CHECK_TORRENT
. "${_LIB}/rpc.sh"     # GET_RPC_INFO 及所有 RPC 子函数

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
    if ! IS_TASK_SOURCE_PATH "${SOURCE_PATH}"; then
        # 越界或根目录：拒绝在 completed/recycle 下凭空拼出怪路径，也避免操作 /downloads 本身
        GET_PATH_INFO="error"
        return 1
    fi
    SOURCE_PATH="${SOURCE_PATH%/}"
    RELATIVE_PATH="${SOURCE_PATH#"${DOWNLOAD_PATH}/"}"
    TARGET_PATH="${TARGET_DIR}/$(dirname "${RELATIVE_PATH}")"
    if [ "${TARGET_PATH}" = "${TARGET_DIR}/." ]; then
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
        GET_TARGET_PATH || return
        COMPLETED_DIR="${TARGET_PATH}/${TASK_NAME}"
    else
        SOURCE_PATH="${FILE_PATH}"
        TASK_NAME="${RELATIVE_PATH##*/}"
        TASK_NAME="${TASK_NAME%.*}"
        GET_TARGET_PATH || return
    fi
}

# 事件脚本公共初始化
# path_type：completed（移动到已完成目录）或 recycle（移动到回收站）
# 其余参数 $2 $3 $4 对应 aria2 传入的 GID、文件数量、第一个文件路径
# 调用顺序：GET_BASE_PATH → 路径目录设置 → GET_RPC_INFO → GET_FINAL_PATH
# 顺序不能打乱：GET_FINAL_PATH 依赖 TARGET_DIR（由路径函数设置）和 DOWNLOAD_DIR（由 RPC 返回）
INIT_EVENT() {
    local path_type=$1
    TASK_GID=$2
    FILE_NUM=$3
    FILE_PATH=$4
    GET_BASE_PATH
    if [ "${path_type}" = "recycle" ]; then
        RECYCLE_PATH
    else
        COMPLETED_PATH
    fi
    GET_RPC_INFO || exit 1
    GET_FINAL_PATH
}

# 事件脚本公共前置检查
# 磁力链接任务（FILE_NUM=0）或路径为空时直接退出（正常情况，不是错误）
# 路径计算失败（GET_PATH_INFO=error）时报错退出，避免对错误路径执行文件操作
GUARD_EVENT() {
    # 显式声明环境契约：未传参数（异常路径调用、aria2 极端情况）也不让 -eq 报错
    : "${FILE_NUM:=0}" "${FILE_PATH:=}"
    if [ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ]; then
        exit 0
    elif [ "${GET_PATH_INFO}" = "error" ]; then
        echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!" >&2
        exit 1
    fi
}
