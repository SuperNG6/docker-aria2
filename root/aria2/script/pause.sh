#!/usr/bin/env bash

. "$(dirname "$0")/lib/all.sh"

INIT_EVENT "$@"
COMPLETED_PATH
GUARD_EVENT

if [ "${MPT}" = "true" ]; then
    MOVE=true
    MOVE_FILE
    CHECK_TORRENT
fi
