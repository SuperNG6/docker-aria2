#!/usr/bin/env bash

FILE_NUM=$2
FILE_PATH=$3

SCRIPT_CONF="config/文件过滤.conf"

LOAD_SCRIPT_CONF() {
    MIN_SIZE="$(grep ^min-size "${SCRIPT_CONF}" | cut -d= -f2-)"
    INCLUDE_FILE="$(grep ^include-file "${SCRIPT_CONF}" | cut -d= -f2-)"
    EXCLUDE_FILE="$(grep ^exclude-file "${SCRIPT_CONF}" | cut -d= -f2-)"
}

DELETE_EXCLUDE_FILE() {
    if [[ ${FILE_NUM} -gt 1 ]] && [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} ]]; then
        echo -e "${INFO} Deleting excluded files ..."
        [[ -n ${MIN_SIZE} ]] && find "${TASK_PATH}" -type f -size -${MIN_SIZE} -print0 | xargs -0 rm -vf
        [[ -n ${EXCLUDE_FILE} ]] && find "${TASK_PATH}" -type f -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})" -print0 | xargs -0 rm -vf
        [[ -n ${INCLUDE_FILE} ]] && find "${TASK_PATH}" -type f -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})" -print0 | xargs -0 rm -vf
    fi
}

CLEAN_UP() {
    DELETE_EXCLUDE_FILE
}