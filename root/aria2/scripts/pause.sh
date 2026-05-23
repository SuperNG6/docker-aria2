#!/usr/bin/env bash
# 下载暂停事件脚本
# aria2 在任务暂停时调用，参数：$1=GID $2=文件数量 $3=第一个文件路径
# 功能：MPT=true 时将暂停的任务也移动到 /downloads/completed 目录
# 适用场景：暂停后手动整理文件，且不再恢复该任务
#
# ⚠ 重要：MPT=true 会破坏 aria2 的"暂停后恢复"能力
#    aria2 的恢复依赖原始 --dir 下的文件 + .aria2 控制文件；本脚本把整个任务文件夹移到
#    completed 后，后续 resume 找不到文件，会从头下载（除非 continue=true + 控制文件保留路径）。
#    仅在确认"暂停 = 任务终结"语义时启用 MPT=true。

. "$(dirname "$0")/lib/event.sh"

INIT_EVENT completed "$@"  # 初始化路径（目标目录：completed）
GUARD_EVENT                 # 磁力/无效任务跳过；路径错误退出

if [ "${MPT}" = "true" ]; then
    MOVE=true   # 强制开启移动（覆盖 setting.conf 中的 move-task 设置）
    MOVE_FILE
    CHECK_TORRENT
fi
