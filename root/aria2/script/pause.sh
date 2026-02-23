#!/usr/bin/env bash

. "$(dirname "$0")/hook_common"

LOAD_HOOK_CONTEXT "$1" "$2" "$3" "completed"

# 下载暂停钩子：可选执行“暂停后移动”策略。
MOVE_PAUSED() {
    EXIT_IF_INVALID_TASK
    # shellcheck disable=SC2034
    MOVE=true
    MOVE_FILE
    CHECK_TORRENT
}

if [ "${MPT}" = "true" ]; then
    MOVE_PAUSED
fi
