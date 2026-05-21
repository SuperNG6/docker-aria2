#!/usr/bin/env bash

. "$(dirname "$0")/lib/all.sh"

INIT_EVENT "$@"
COMPLETED_PATH
GUARD_EVENT
MOVE_FILE
CHECK_TORRENT
