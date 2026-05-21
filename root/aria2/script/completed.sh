#!/usr/bin/env bash

. "$(dirname "$0")/lib/all.sh"

INIT_EVENT completed "$@"
GUARD_EVENT
MOVE_FILE
CHECK_TORRENT
