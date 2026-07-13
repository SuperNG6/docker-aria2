#!/usr/bin/env bash
# 下载暂停事件脚本
# aria2 在任务暂停时调用，参数：$1=GID $2=文件数量 $3=第一个文件路径
# 功能：MPT=true 时，确认任务持续暂停 30 秒后才移动到 /downloads/completed 目录
# 适用场景：暂停后手动整理文件，且不再恢复该任务
#
# ⚠ 重要：MPT=true 会破坏 aria2 的"暂停后恢复"能力
#    aria2 的恢复依赖原始 --dir 下的文件 + .aria2 控制文件；本脚本把整个任务文件夹移到
#    completed 后，后续 resume 找不到文件，会从头下载（除非 continue=true + 控制文件保留路径）。
#    仅在确认"暂停 = 任务终结"语义时启用 MPT=true。

. "$(dirname "${BASH_SOURCE[0]}")/lib/event.sh"

# aria2 的 on-download-pause 不提供暂停原因。BT 文件筛选会短暂暂停任务以变更 select-file，
# 因此先等待 30 秒再查状态：已经恢复为 active/waiting 的任务不移动；仍 paused 才执行移动。
# 在后台执行，避免等待时间阻塞 aria2 对暂停 RPC 的响应。
RUN_PAUSE_HOOK() {
    INIT_EVENT completed "$@"  # 初始化路径（目标目录：completed）
    GUARD_EVENT                 # 磁力/无效任务跳过；路径错误退出

    if [ "${MPT}" = "true" ]; then
        sleep 30
        LOAD_CONF
        if ! GET_RPC_RESULT || ! GET_TASK_STATUS; then
            echo -e "$(DATE_TIME) ${WARNING} 无法确认暂停任务状态，跳过移动（GID=${TASK_GID}）" >&2
            return 0
        fi
        if [ "${TASK_STATUS}" != "paused" ]; then
            echo -e "$(DATE_TIME) ${INFO} 暂停任务已恢复（状态=${TASK_STATUS}），跳过移动（GID=${TASK_GID}）"
            return 0
        fi
        MOVE=true   # 强制开启移动（覆盖 setting.conf 中的 move-task 设置）
        MOVE_FILE
        CHECK_TORRENT
    fi
}

# 可被库测试 source；作为 aria2 hook 直接运行时才执行。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [ "${MPT}" = "true" ]; then
        RUN_PAUSE_HOOK "$@" &
    else
        RUN_PAUSE_HOOK "$@"
    fi
fi
