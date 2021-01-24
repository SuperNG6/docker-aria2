#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"

FILE_PATH=$3
FILE_NUM=$2

if [ "${FILE_NUM}" -eq 0 ]; then
    echo -e "$(DATE_TIME) Download Magnet OR Download Error"
    exit 0
else
    if [ "${RMTASK}" = "recycle" ]; then
        GET_BASE_PATH
        RECYCLE_PATH
        GET_PATH
        MOVE_RECYCLE
        RM_ARIA2
        exit 0
    elif [ "${RMTASK}" = "delete" ]; then
        GET_BASE_PATH
        GET_PATH
        DELETE_FILE
        RM_ARIA2
        exit 0
    elif [ "${RMTASK}" = "rmaria" ]; then
        GET_BASE_PATH
        GET_PATH
        RM_ARIA2
        exit 0
    fi
fi
