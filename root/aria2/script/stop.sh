#!/usr/bin/env bash
# 下载停止事件脚本
# aria2 在任务被手动停止/删除时调用，参数：$1=GID $2=文件数量 $3=第一个文件路径
# 功能：根据 RMTASK 配置决定如何处理已（部分）下载的文件
#   recycle - 移动到回收站（/downloads/recycle）
#   delete  - 彻底删除
#   rmaria  - 仅移除 aria2 任务记录，不动文件（默认）
# TASK_STATUS=error 时（下载出错）不执行任何文件操作，避免误删损坏文件

. "$(dirname "$0")/lib/all.sh"

INIT_EVENT recycle "$@"  # 初始化路径（目标目录：recycle）
GUARD_EVENT              # 磁力/无效任务跳过；路径错误退出

# start.sh 在重复任务检测时可能已删除文件，跳过后续操作
[ -e "${SOURCE_PATH}" ] || exit 0
# 下载出错的任务保留文件供用户排查或续传
[ "${TASK_STATUS}" = "error" ] && exit 0

# 三种处理模式分流；CHECK_TORRENT 和 RM_ARIA2 由公共尾部统一处理
case "${RMTASK}" in
    recycle) MOVE_RECYCLE ;;
    delete)  DELETE_FILE  ;;
    rmaria)  ;;  # 不动文件，仅清理 .aria2 控制文件（落到下面统一执行）
esac
CHECK_TORRENT
RM_ARIA2
