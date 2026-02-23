#!/usr/bin/env bash

. "$(dirname "$0")/hook_common"

# 下载完成钩子：按配置执行移动、过滤与种子处理。
LOAD_HOOK_CONTEXT "$1" "$2" "$3" "completed"
EXIT_IF_INVALID_TASK
MOVE_FILE
CHECK_TORRENT
