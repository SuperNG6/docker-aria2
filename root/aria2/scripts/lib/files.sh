#!/usr/bin/env bash
# 文件操作库：移动、删除、回收站、清理 .aria2 控制文件
# 所有函数依赖 log.sh 的颜色变量和 DATE_TIME()，事件脚本通过 lib/event.sh 引入
#
# 颜色规约（与 TASK_INFO 一致，让 docker logs 中关键信息一眼可见）：
#   绿色 LIGHT_GREEN：正常路径（SOURCE_PATH / TARGET_PATH / 数值）
#   黄色 YELLOW：警示路径（move-failed 退路目录、未知值）
#   紫色 LIGHT_PURPLE：种子相关（TORRENT_FILE，与 TASK_INFO 紫色字段一致）

# 判断 SOURCE_PATH 是否是 /downloads 下的具体任务路径。
# 除根目录外，也拒绝项目共享目录本身；BT 根目录若与这些名称撞名，
# 不能把历史 completed/recycle/move-failed 内容当成本次任务整体操作。
IS_TASK_SOURCE_PATH() {
    local root="${DOWNLOAD_PATH%/}" path="${1:-}"
    path="${path%/}"
    [ -n "${root}" ] && [ -n "${path}" ] || return 1
    case "${path}" in
        "${root}"|"${root}/completed"|"${root}/recycle"|"${root}/move-failed")
            return 1
            ;;
        "${root}/"*) return 0 ;;
        *)           return 1 ;;
    esac
}

REMOVE_SOURCE_PATH() {
    IS_TASK_SOURCE_PATH "${SOURCE_PATH:-}" || return 1
    rm -rf "${SOURCE_PATH}"
}

MOVE_SOURCE_PATH() {
    local target=$1
    IS_TASK_SOURCE_PATH "${SOURCE_PATH:-}" || return 1
    mv -f "${SOURCE_PATH}" "${target}"
}

# 删除 aria2 下载控制文件（.aria2 后缀），任务结束后清理用
RM_ARIA2() {
    if [ -e "${SOURCE_PATH}.aria2" ]; then
        rm -f "${SOURCE_PATH}.aria2"
        echo -e "$(DATE_TIME) ${INFO} 已删除文件: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}.aria2${FONT_COLOR_SUFFIX}"
    fi
}

# 下载完成后的清理：删除 .aria2 控制文件，并按配置过滤不需要的文件
# CF=true 且任务目录内探测到多个真实文件时才执行内容过滤
CLEAN_UP() {
    RM_ARIA2
    if [ "$CF" = "true" ]; then
        LOAD_FILTER_CONF
        # DELETE_EXCLUDE_FILE 内部探测一次真实文件数，并据此决定是否过滤。
        DELETE_EXCLUDE_FILE
        [ "${REAL_FILE_NUM}" -gt 1 ] && DELETE_EMPTY_DIR
    fi
}

# 判断源路径与目标路径是否跨磁盘（不同设备号即跨盘）
# 跨盘 mv 实际是 cp + rm，耗时随文件大小线性增长，需要预先校验目标盘空间
_IS_CROSS_DEVICE() {
    [ "$(stat -c %d "$1")" != "$(stat -c %d "$2")" ]
}

# 检查目标路径所在文件系统的可用空间是否容得下源路径全部数据
# 返回 0=够；返回 1=不够，并打印 GB 单位的对比 + 写入 MOVE_LOG
_CHECK_SPACE() {
    local src=$1 dst=$2 required available required_gb available_gb
    required=$(du -sb "${src}" | awk '{print $1}')
    available=$(df --output=avail -B1 "${dst}" | sed '1d')
    (( available >= required )) && return 0
    required_gb=$(awk "BEGIN {printf \"%.2f\", ${required}/1024/1024/1024}")
    available_gb=$(awk "BEGIN {printf \"%.2f\", ${available}/1024/1024/1024}")
    echo -e "$(DATE_TIME) ${ERROR} 目标磁盘空间不足！需 ${LIGHT_GREEN_FONT_PREFIX}${required_gb}${FONT_COLOR_SUFFIX} GB，可用 ${LIGHT_GREEN_FONT_PREFIX}${available_gb}${FONT_COLOR_SUFFIX} GB" >&2
    log_line "${MOVE_LOG}" ERROR "目标磁盘空间不足。需:${required_gb}G 可用:${available_gb}G 源:${src} -> 目标:${dst}"
    return 1
}

# 把任务移到 /downloads/move-failed 回退目录
# 两种情况调用：跨盘前空间不足、主路径 mv 失败
# 传入 reason 描述会出现在日志前缀，区分调用上下文
_MOVE_TO_FAILED() {
    local reason=${1:-}
    local fail_dir="${DOWNLOAD_PATH}/move-failed"
    mkdir -p "${fail_dir}"
    if MOVE_SOURCE_PATH "${fail_dir}"; then
        echo -e "$(DATE_TIME) ${INFO} ${reason}已将文件移动至: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX} -> ${YELLOW_FONT_PREFIX}${fail_dir}${FONT_COLOR_SUFFIX}"
        log_line "${MOVE_LOG}" INFO "${reason}已将文件移动至: ${SOURCE_PATH} -> ${fail_dir}"
    else
        echo -e "$(DATE_TIME) ${ERROR} 移动到 ${YELLOW_FONT_PREFIX}${fail_dir}${FONT_COLOR_SUFFIX} 依然失败: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
        log_line "${MOVE_LOG}" ERROR "移动到 ${fail_dir} 依然失败: ${SOURCE_PATH}"
    fi
}

# 将已完成任务移动到目标目录（MOVE 变量控制行为）
# MOVE=false：不移动，只清理控制文件
# MOVE=dmof：根目录的单文件任务不移动（防止把散落在 /downloads 的文件误移）
# MOVE=true 或 dmof（非根目录/多文件）：正常移动
# 其他值：什么也不做（保留向后兼容，未来扩展新模式不影响当前行为）
# 跨磁盘移动时先检查目标磁盘剩余空间，不足则移至 /downloads/move-failed
MOVE_FILE() {
    case "${MOVE}" in
        false)
            RM_ARIA2
            return
            ;;
        dmof)
            # 根目录单文件不移动
            if [ "${DOWNLOAD_DIR}" = "${DOWNLOAD_PATH}" ] && [ "${FILE_NUM}" -eq 1 ]; then
                RM_ARIA2
                return
            fi
            ;;
        true) ;;
        *) return ;;
    esac

    TASK_TYPE=": 移动任务文件"
    TASK_INFO
    CLEAN_UP
    echo -e "$(DATE_TIME) ${INFO} 开始移动该任务文件到: ${LIGHT_GREEN_FONT_PREFIX}${TARGET_PATH}${FONT_COLOR_SUFFIX}"
    mkdir -p "${TARGET_PATH}"

    # 跨盘前先验空间，空间不足走 move-failed 回退避免半成品
    if _IS_CROSS_DEVICE "${SOURCE_PATH}" "${TARGET_PATH}"; then
        echo -e "$(DATE_TIME) ${INFO} 检测到跨磁盘移动，正在检查目标磁盘空间..."
        if ! _CHECK_SPACE "${SOURCE_PATH}" "${TARGET_PATH}"; then
            echo -e "$(DATE_TIME) ${WARNING} 尝试将任务移动到: ${YELLOW_FONT_PREFIX}${DOWNLOAD_PATH}/move-failed${FONT_COLOR_SUFFIX}"
            _MOVE_TO_FAILED "因目标磁盘空间不足，"
            return 1
        fi
        echo -e "$(DATE_TIME) ${INFO} 目标磁盘空间充足。"
    fi

    # 执行移动；失败回退到 move-failed 目录
    if MOVE_SOURCE_PATH "${TARGET_PATH}"; then
        echo -e "$(DATE_TIME) ${INFO} 已移动文件至目标文件夹: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX} -> ${LIGHT_GREEN_FONT_PREFIX}${TARGET_PATH}${FONT_COLOR_SUFFIX}"
        log_line "${MOVE_LOG}" INFO "已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}"
    else
        echo -e "$(DATE_TIME) ${ERROR} 文件移动失败: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
        log_line "${MOVE_LOG}" ERROR "文件移动失败: ${SOURCE_PATH}"
        _MOVE_TO_FAILED
    fi
}

# 彻底删除任务文件（RMTASK=delete 时由 stop.sh 调用）
DELETE_FILE() {
    TASK_TYPE=": 删除任务文件"
    TASK_INFO no-target    # 删除场景无目标路径，传 no-target 隐藏对应行
    echo -e "$(DATE_TIME) ${INFO} 下载已停止，开始删除文件..."
    if REMOVE_SOURCE_PATH; then
        echo -e "$(DATE_TIME) ${INFO} 已删除文件: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
        log_line "${DELETE_LOG}" INFO "文件删除成功: ${SOURCE_PATH}"
    else
        echo -e "$(DATE_TIME) ${ERROR} 文件删除失败: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
        log_line "${DELETE_LOG}" ERROR "文件删除失败: ${SOURCE_PATH}"
    fi
}

# 将任务文件移动到回收站（RMTASK=recycle 时由 stop.sh 调用）
# 移动失败时降级为直接删除，避免文件滞留在下载目录
MOVE_RECYCLE() {
    TASK_TYPE=": 移动任务文件至回收站"
    TASK_INFO
    echo -e "$(DATE_TIME) ${INFO} 开始移动已下载的任务至回收站 ${LIGHT_GREEN_FONT_PREFIX}${TARGET_PATH}${FONT_COLOR_SUFFIX}"
    mkdir -p "${TARGET_PATH}"
    if MOVE_SOURCE_PATH "${TARGET_PATH}"; then
        echo -e "$(DATE_TIME) ${INFO} 已移至回收站: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX} -> ${LIGHT_GREEN_FONT_PREFIX}${TARGET_PATH}${FONT_COLOR_SUFFIX}"
        log_line "${RECYCLE_LOG}" INFO "成功移动文件到回收站: ${SOURCE_PATH} -> ${TARGET_PATH}"
        return
    fi

    # 移到回收站失败，降级为删除
    echo -e "$(DATE_TIME) ${ERROR} 移动文件到回收站失败: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
    echo -e "$(DATE_TIME) ${INFO} 尝试删除文件: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
    if REMOVE_SOURCE_PATH; then
        echo -e "$(DATE_TIME) ${INFO} 已删除文件: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
        log_line "${RECYCLE_LOG}" WARNING "移动文件到回收站失败，已删除文件: ${SOURCE_PATH}"
    else
        echo -e "$(DATE_TIME) ${ERROR} 删除文件也失败: ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
        log_line "${RECYCLE_LOG}" ERROR "移动到回收站和删除文件都失败: ${SOURCE_PATH}"
    fi
}

# stop.sh 的 RMTASK 分流。未知值必须不触碰 .aria2 / .torrent，
# 否则用户拼错配置会破坏断点续传或种子保留语义。
HANDLE_STOP_TASK() {
    case "${RMTASK}" in
        recycle)
            MOVE_RECYCLE
            CHECK_TORRENT
            RM_ARIA2
            ;;
        delete)
            DELETE_FILE
            CHECK_TORRENT
            RM_ARIA2
            ;;
        rmaria)
            CHECK_TORRENT
            RM_ARIA2
            ;;
        *)
            echo -e "$(DATE_TIME) ${WARNING} 未知的 RMTASK 值: ${YELLOW_FONT_PREFIX}${RMTASK}${FONT_COLOR_SUFFIX}（不处理文件、.aria2 或种子）" >&2
            ;;
    esac
}
