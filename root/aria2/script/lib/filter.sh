#!/usr/bin/env bash
# 文件过滤库：根据 /config/文件过滤.conf 的规则删除不需要的文件
# 仅在 CF=true（内容过滤启用）且任务是多文件时生效
# 由 files.sh 的 CLEAN_UP 调用

# 从文件过滤配置文件读取过滤规则到全局变量
# 支持：最小文件大小、包含/排除扩展名、关键字过滤、正则过滤
LOAD_FILTER_CONF() {
    MIN_SIZE="$(grep ^min-size "${FILTER_CONF}" | cut -d= -f2-)"              # 小于此大小的文件将被删除（如 100k）
    INCLUDE_FILE="$(grep ^include-file "${FILTER_CONF}" | cut -d= -f2-)"      # 只保留这些扩展名（如 mp4|mkv|avi）
    EXCLUDE_FILE="$(grep ^exclude-file "${FILTER_CONF}" | cut -d= -f2-)"      # 删除这些扩展名（如 txt|jpg）
    KEYWORD_FILE="$(grep ^keyword-file "${FILTER_CONF}" | cut -d= -f2-)"      # 文件名包含这些关键词则删除
    INCLUDE_FILE_REGEX="$(grep ^include-file-regex "${FILTER_CONF}" | cut -d= -f2-)"  # 只保留匹配此正则的文件
    EXCLUDE_FILE_REGEX="$(grep ^exclude-file-regex "${FILTER_CONF}" | cut -d= -f2-)"  # 删除匹配此正则的文件
}

# 按过滤规则删除任务目录内不需要的文件
# 只在多文件任务（文件夹）中运行，防止误删单文件任务
DELETE_EXCLUDE_FILE() {
    if [[ ${FILE_NUM} -gt 1 ]] && [ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ] && \
       [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} || -n ${KEYWORD_FILE} || -n ${EXCLUDE_FILE_REGEX} || -n ${INCLUDE_FILE_REGEX} ]]; then
        echo -e "$(DATE_TIME) ${INFO} 删除不需要的文件..."
        # 各规则均记录到过滤日志；多个规则可同时生效
        [[ -n ${MIN_SIZE} ]]           && find "${SOURCE_PATH}" -type f -size -${MIN_SIZE} -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n ${EXCLUDE_FILE} ]]       && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n ${KEYWORD_FILE} ]]       && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*(${KEYWORD_FILE}).*" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n ${INCLUDE_FILE} ]]       && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n ${EXCLUDE_FILE_REGEX} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex "${EXCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
        [[ -n ${INCLUDE_FILE_REGEX} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex "${INCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
    fi
}

# 删除过滤后遗留的空目录（DET=true 时启用）
DELETE_EMPTY_DIR() {
    if [ "${DET}" = "true" ]; then
        echo -e "$(DATE_TIME) ${INFO} 删除任务中空的文件夹 ..."
        # -depth 确保先处理深层目录，避免父目录未空时报错
        find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
    fi
}
