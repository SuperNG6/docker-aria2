#!/usr/bin/env bash
# 文件过滤库：根据 /config/文件过滤.conf 的规则删除不需要的文件
# 仅在 CF=true（内容过滤启用）且任务是多文件时生效
# 由 files.sh 的 CLEAN_UP 调用

# 从文件过滤配置文件读取过滤规则到全局变量
# 支持：最小文件大小、包含/排除扩展名、关键字过滤、正则过滤
LOAD_FILTER_CONF() {
    MIN_SIZE="$(grep ^min-size "${FILTER_CONF}" | cut -d= -f2-)"                     # 小于此大小的文件将被删除（如 100k）
    INCLUDE_FILE="$(grep ^include-file "${FILTER_CONF}" | cut -d= -f2-)"             # 只保留这些扩展名（如 mp4|mkv|avi）
    EXCLUDE_FILE="$(grep ^exclude-file "${FILTER_CONF}" | cut -d= -f2-)"             # 删除这些扩展名（如 txt|jpg）
    KEYWORD_FILE="$(grep ^keyword-file "${FILTER_CONF}" | cut -d= -f2-)"             # 文件名包含这些关键词则删除
    INCLUDE_FILE_REGEX="$(grep ^include-file-regex "${FILTER_CONF}" | cut -d= -f2-)" # 只保留匹配此正则的文件
    EXCLUDE_FILE_REGEX="$(grep ^exclude-file-regex "${FILTER_CONF}" | cut -d= -f2-)" # 删除匹配此正则的文件
}

# 共用的删除-记日志管道：按 find 参数批量删除并把结果 tee 到过滤日志
# 调用方按需拼出 -size / -iregex / ! -iregex 等参数
_filter_rule() {
    find "${SOURCE_PATH}" -type f "$@" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
}

# 按过滤规则删除任务目录内不需要的文件
# 只在多文件任务（文件夹）中运行，防止误删单文件任务
DELETE_EXCLUDE_FILE() {
    [ "${FILE_NUM}" -gt 1 ] && [ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ] || return
    # 任一规则非空即进入删除流程（拼接判定比 6 个独立 -n 更紧凑）
    [ -n "${MIN_SIZE}${INCLUDE_FILE}${EXCLUDE_FILE}${KEYWORD_FILE}${EXCLUDE_FILE_REGEX}${INCLUDE_FILE_REGEX}" ] || return

    echo -e "$(DATE_TIME) ${INFO} 删除不需要的文件..."
    [ -n "${MIN_SIZE}" ]           && _filter_rule -size "-${MIN_SIZE}"
    [ -n "${EXCLUDE_FILE}" ]       && _filter_rule -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})"
    [ -n "${KEYWORD_FILE}" ]       && _filter_rule -regextype posix-extended -iregex ".*(${KEYWORD_FILE}).*"
    [ -n "${INCLUDE_FILE}" ]       && _filter_rule -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})"
    [ -n "${EXCLUDE_FILE_REGEX}" ] && _filter_rule -regextype posix-extended -iregex "${EXCLUDE_FILE_REGEX}"
    [ -n "${INCLUDE_FILE_REGEX}" ] && _filter_rule -regextype posix-extended ! -iregex "${INCLUDE_FILE_REGEX}"
}

# 删除过滤后遗留的空目录（DET=true 时启用）
DELETE_EMPTY_DIR() {
    if [ "${DET}" = "true" ]; then
        echo -e "$(DATE_TIME) ${INFO} 删除任务中空的文件夹 ..."
        # -depth 确保先处理深层目录，避免父目录未空时报错
        find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
    fi
}
