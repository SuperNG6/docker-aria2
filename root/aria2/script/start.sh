#!/usr/bin/env bash
# 下载开始事件脚本
# aria2 在任务开始时调用，参数：$1=GID $2=文件数量 $3=第一个文件路径
# 功能：检测重复任务（RRT=true 时，若 completed 目录已有同名文件夹则取消本次任务）
# 注意：单文件任务开始时 FILE_PATH 为空，磁力链接开始时 FILE_NUM=0，这两种情况由 GUARD_EVENT 跳过
#
# 已知 corner case（不修，文档化）：
#   on-download-start 在 aria2 重启 / 暂停恢复时也会重新触发。
#   若任务 A 正在下载（partial 在 /downloads/A/），而同名 /downloads/completed/A/
#   因不相关历史任务残留，RRT 会误判 A 为重复并取消之。
#   触发面较窄（任务命名撞车 + 用户保留旧副本），用户遇到时可临时设 RRT=false 绕开。

. "$(dirname "$0")/lib/all.sh"

INIT_EVENT completed "$@"  # 初始化路径（目标目录：completed，用于检查是否已存在）
GUARD_EVENT                 # 磁力/无效任务跳过；路径错误退出

# RRT=true 时：发现 completed 目录已有同名文件夹，说明是重复任务
# 删除本地已下载的部分文件，按 TOR 配置处理 .torrent，然后通过 RPC 取消 aria2 中的任务
# 注：原版本未调 CHECK_TORRENT，当 SMD=true 且 BT 重复任务命中时，.torrent 文件会残留在 /downloads 根目录
if [ "${RRT}" = "true" ] && [ -d "${COMPLETED_DIR}" ] && [ "${TASK_STATUS}" != "error" ]; then
    echo -e "$(DATE_TIME) ${WARNING} 发现目标文件夹已存在当前任务 ${LIGHT_GREEN_FONT_PREFIX}${COMPLETED_DIR}${FONT_COLOR_SUFFIX}"
    echo -e "$(DATE_TIME) ${WARNING} 正在删除该任务，并清除相关文件... ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
    CHECK_TORRENT
    RM_ARIA2
    rm -rf "${SOURCE_PATH}"
    REMOVE_REPEAT_TASK
    exit 0
fi
