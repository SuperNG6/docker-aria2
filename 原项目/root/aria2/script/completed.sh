#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"
. "$(dirname $0)/rpc_info"

TASK_GID=$1
FILE_NUM=$2
FILE_PATH=$3

GET_BASE_PATH
COMPLETED_PATH
GET_RPC_INFO
GET_FINAL_PATH

if [ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ]; then
    exit 0
elif [ "${GET_PATH_INFO}" = "error" ]; then
    echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"
    exit 1
else
    MOVE_FILE
    CHECK_TORRENT
fi
