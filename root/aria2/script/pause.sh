#!/usr/bin/env bash
# 下载暂停事件脚本
# aria2 在任务暂停时调用，参数：$1=GID $2=文件数量 $3=第一个文件路径
# 功能：MPT=true 时将暂停的任务也移动到 /downloads/completed 目录
# 适用场景：需要暂停后手动整理文件，但希望文件已位于目标目录

. "$(dirname "$0")/lib/all.sh"

INIT_EVENT completed "$@"  # 初始化路径（目标目录：completed）
GUARD_EVENT                 # 磁力/无效任务跳过；路径错误退出

if [ "${MPT}" = "true" ]; then
    MOVE=true   # 强制开启移动（覆盖 setting.conf 中的 move-task 设置）
    MOVE_FILE
    CHECK_TORRENT
fi
