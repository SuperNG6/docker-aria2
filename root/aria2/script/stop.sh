#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"

FILE_PATH=$3
FILE_NUM=$2

GET_BASE_PATH
RECYCLE_PATH
GET_PATH

if [ "${FILE_NUM}" -eq 0 ]; then
    exit 0
elif [ "${GET_PATH_INFO}" = "error" ]; then
    echo -e "$(DATE_TIME) ${ERROR} GET TASK PATH ERROR!"
    exit 1
elif [ "${RMTASK}" = "recycle" ]; then
    MOVE_RECYCLE
    RM_ARIA2
    exit 0
elif [ "${RMTASK}" = "delete" ]; then
    DELETE_FILE
    RM_ARIA2
    exit 0
elif [ "${RMTASK}" = "rmaria" ]; then
    RM_ARIA2
    exit 0
fi
