#!/usr/bin/env bash

. "$(dirname "$0")/lib/all.sh"

INIT_EVENT recycle "$@"
GUARD_EVENT

# start.sh 可能已删除文件，SOURCE_PATH 不存在则跳过
[ -e "${SOURCE_PATH}" ] || exit 0

if   [ "${RMTASK}" = "recycle" ] && [ "${TASK_STATUS}" != "error" ]; then
    MOVE_RECYCLE; CHECK_TORRENT; RM_ARIA2
elif [ "${RMTASK}" = "delete"  ] && [ "${TASK_STATUS}" != "error" ]; then
    DELETE_FILE;  CHECK_TORRENT; RM_ARIA2
elif [ "${RMTASK}" = "rmaria"  ] && [ "${TASK_STATUS}" != "error" ]; then
    CHECK_TORRENT; RM_ARIA2
fi
