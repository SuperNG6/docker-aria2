#!/usr/bin/env bash

LOAD_SCRIPT_CONF() {
    MIN_SIZE="$(grep ^min-size "${SCRIPT_CONF}" | cut -d= -f2-)"
    INCLUDE_FILE="$(grep ^include-file "${SCRIPT_CONF}" | cut -d= -f2-)"
    EXCLUDE_FILE="$(grep ^exclude-file "${SCRIPT_CONF}" | cut -d= -f2-)"
    KEYWORD_FILE="$(grep ^keyword-file "${SCRIPT_CONF}" | cut -d= -f2-)"
    INCLUDE_FILE_REGEX="$(grep ^include-file-regex "${SCRIPT_CONF}" | cut -d= -f2-)"
    EXCLUDE_FILE_REGEX="$(grep ^exclude-file-regex "${SCRIPT_CONF}" | cut -d= -f2-)"
}

DELETE_EXCLUDE_FILE() {
    if [[ ${FILE_NUM} -gt 1 ]] && [ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ] && \
       [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} || -n ${KEYWORD_FILE} || -n ${EXCLUDE_FILE_REGEX} || -n ${INCLUDE_FILE_REGEX} ]]; then
        echo -e "$(DATE_TIME) ${INFO} 删除不需要的文件..."
        [[ -n ${MIN_SIZE} ]]           && find "${SOURCE_PATH}" -type f -size -${MIN_SIZE} -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n ${EXCLUDE_FILE} ]]       && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n ${KEYWORD_FILE} ]]       && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*(${KEYWORD_FILE}).*" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n ${INCLUDE_FILE} ]]       && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n ${EXCLUDE_FILE_REGEX} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex "${EXCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n ${INCLUDE_FILE_REGEX} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex "${INCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
    fi
}

DELETE_EMPTY_DIR() {
    if [ "${DET}" = "true" ]; then
        echo -e "$(DATE_TIME) ${INFO} 删除任务中空的文件夹 ..."
        find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
    fi
}
