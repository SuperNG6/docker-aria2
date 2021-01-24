#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"

FILE_PATH=$3
FILE_NUM=$2

GET_BASE_PATH

if [ "${RMTASK}" = "recycle" ]; then
    RECYCLE_PATH
    GET_PATH
    MOVE_RECYCLE
    RM_ARIA2
    exit 0
elif [ "${RMTASK}" = "delete" ]; then
    GET_PATH
    DELETE_FILE
    RM_ARIA2
    exit 0
fi
RM_ARIA2
exit 0
