#!/usr/bin/env bash
# 下载完成事件脚本
# aria2 在任务完成时调用，参数：$1=GID $2=文件数量 $3=第一个文件路径
# 功能：按配置移动文件到 /downloads/completed，并处理种子文件

. "$(dirname "$0")/lib/all.sh"

INIT_EVENT completed "$@"  # 初始化路径、RPC 信息（目标目录：completed）
GUARD_EVENT                 # 磁力/无效任务跳过；路径错误退出
MOVE_FILE                   # 按 MOVE 配置决定是否移动文件
CHECK_TORRENT               # 按 TOR 配置处理种子文件
