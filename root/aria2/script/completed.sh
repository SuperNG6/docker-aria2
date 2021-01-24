#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"

FILE_PATH=$3
FILE_NUM=$2

if [ "${FILE_NUM}" -eq 0 ]; then
    echo -e "$(DATE_TIME) Download Magnet OR Download Error"
    exit 0
else
    GET_BASE_PATH
    COMPLETED_PATH
    GET_PATH
    MOVE_FILE
fi
