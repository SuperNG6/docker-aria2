#!/usr/bin/env bash
# 下载停止事件脚本
# aria2 在活动任务被删除或出错停止时调用（删除已暂停任务、移除已完成记录不会触发），
# 参数：$1=GID $2=文件数量 $3=第一个文件路径
# 功能：根据 RMTASK 配置决定如何处理已（部分）下载的文件
#   recycle - 移动到回收站（/downloads/recycle）
#   delete  - 彻底删除
#   rmaria  - 仅删除 .aria2 控制文件，不动下载内容（默认）
# TASK_STATUS=error 时（下载出错）不执行任何文件操作，避免误删损坏文件

. "$(dirname "${BASH_SOURCE[0]}")/lib/event.sh"

INIT_EVENT recycle "$@"  # 初始化路径（目标目录：recycle）
GUARD_EVENT              # 磁力/无效任务跳过；路径错误退出

# start.sh 在重复任务检测时可能已删除文件，跳过后续操作
[ -e "${SOURCE_PATH}" ] || exit 0
# 下载出错的任务保留文件供用户排查或续传
[ "${TASK_STATUS}" = "error" ] && exit 0

# RMTASK 未知值由库函数直接跳过，避免误删断点续传控制文件
HANDLE_STOP_TASK
