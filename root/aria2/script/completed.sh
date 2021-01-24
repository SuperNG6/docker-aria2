#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"

FILE_PATH=$3
FILE_NUM=$2

GET_BASE_PATH
COMPLETED_PATH
GET_PATH
MOVE_FILE
exit 0
