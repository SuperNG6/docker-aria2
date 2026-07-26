#!/usr/bin/env bash
# 文件过滤库：根据 /config/文件过滤.conf 的规则删除不需要的文件
# 仅在 CF=true（内容过滤启用）且任务目录内确有多个文件时生效
# 由 files.sh 的 CLEAN_UP 调用

# 探测任务源路径中的真实文件数。
# aria2 hook 传入的 FILE_NUM 偶尔与落盘内容不一致，不能用它决定是否过滤。
DETECT_REAL_FILE_NUM() {
    if [ -d "${SOURCE_PATH:-}" ] && IS_TASK_SOURCE_PATH "${SOURCE_PATH}"; then
        # NUL 分隔避免文件名中的换行影响计数，也不依赖 GNU find 的 -printf。
        REAL_FILE_NUM=$(find "${SOURCE_PATH}" -type f -print0 | tr -cd '\0' | wc -c)
        REAL_FILE_NUM=${REAL_FILE_NUM//[[:space:]]/}
    elif [ -f "${SOURCE_PATH:-}" ] && IS_TASK_SOURCE_PATH "${SOURCE_PATH}"; then
        REAL_FILE_NUM=1
    else
        REAL_FILE_NUM=0
    fi
}

# 从文件过滤配置文件读取过滤规则到全局变量
# 支持：最小文件大小、包含/排除扩展名、关键字过滤、正则过滤
#
# 每条 grep 都用 ^key= 精确锚定：include-file 是 include-file-regex 的前缀，
# 若只锚 ^include-file 会把 regex 行的值也吞进 INCLUDE_FILE，拼进 find -iregex 后
# 正则中间夹换行符而整条失效。用 = 作为精确边界根除前缀污染（项目规范：grep 必须锚定 ^key=）。
_STRIP_OPTIONAL_QUOTES() {
    local value=$1
    case "${value}" in
        \"*\") value=${value:1:${#value}-2} ;;
        \'*\') value=${value:1:${#value}-2} ;;
    esac
    printf '%s' "${value}"
}

LOAD_FILTER_CONF() {
    MIN_SIZE="$(grep '^min-size=' "${FILTER_CONF}" | cut -d= -f2-)"                     # 小于此大小的文件将被删除（如 100k）
    INCLUDE_FILE="$(grep '^include-file=' "${FILTER_CONF}" | cut -d= -f2-)"             # 只保留这些扩展名（如 mp4|mkv|avi）
    EXCLUDE_FILE="$(grep '^exclude-file=' "${FILTER_CONF}" | cut -d= -f2-)"             # 删除这些扩展名（如 txt|jpg）
    KEYWORD_FILE="$(grep '^keyword-file=' "${FILTER_CONF}" | cut -d= -f2-)"             # 文件名包含这些关键词则删除
    INCLUDE_FILE_REGEX="$(grep '^include-file-regex=' "${FILTER_CONF}" | cut -d= -f2-)" # 只保留匹配此正则的文件
    EXCLUDE_FILE_REGEX="$(grep '^exclude-file-regex=' "${FILTER_CONF}" | cut -d= -f2-)" # 删除匹配此正则的文件
    # 模板中的正则示例历史上带双引号；兼容已有配置，避免引号成为正则本身。
    INCLUDE_FILE_REGEX=$(_STRIP_OPTIONAL_QUOTES "${INCLUDE_FILE_REGEX}")
    EXCLUDE_FILE_REGEX=$(_STRIP_OPTIONAL_QUOTES "${EXCLUDE_FILE_REGEX}")
}

# 按相同的 find 条件预览或删除匹配文件。
# 预览使用 NUL 分隔，既能安全处理特殊文件名，也能让多条规则的结果准确去重。
_filter_rule() {
    local action=$1
    shift
    if [ "${action}" = "preview" ]; then
        find "${SOURCE_PATH}" -type f "$@" -print0
    else
        find "${SOURCE_PATH}" -type f "$@" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}"
    fi
}

# 所有规则集中在这里，确保预判和实际删除使用完全相同的匹配条件。
_run_filter_rules() {
    local action=$1
    [ -n "${MIN_SIZE}" ]           && _filter_rule "${action}" -size "-${MIN_SIZE}"
    [ -n "${EXCLUDE_FILE}" ]       && _filter_rule "${action}" -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})"
    # find 的 -iregex 匹配完整路径；限定最后一个路径段，避免任务目录名命中后删光整个任务。
    [ -n "${KEYWORD_FILE}" ]       && _filter_rule "${action}" -regextype posix-extended -iregex ".*/[^/]*(${KEYWORD_FILE})[^/]*"
    [ -n "${INCLUDE_FILE}" ]       && _filter_rule "${action}" -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})"
    [ -n "${EXCLUDE_FILE_REGEX}" ] && _filter_rule "${action}" -regextype posix-extended -iregex "${EXCLUDE_FILE_REGEX}"
    [ -n "${INCLUDE_FILE_REGEX}" ] && _filter_rule "${action}" -regextype posix-extended ! -iregex "${INCLUDE_FILE_REGEX}"
    return 0
}

# 按过滤规则删除任务目录内不需要的文件
# 只在真实多文件任务（文件夹）中运行，防止 aria2 文件数错误导致误删或漏删
DELETE_EXCLUDE_FILE() {
    local candidate_file candidate_num
    FILTER_DELETE_BLOCKED=false
    DETECT_REAL_FILE_NUM
    [ "${REAL_FILE_NUM}" -gt 1 ] || return
    # 任一规则非空即进入删除流程（拼接判定比 6 个独立 -n 更紧凑）
    [ -n "${MIN_SIZE}${INCLUDE_FILE}${EXCLUDE_FILE}${KEYWORD_FILE}${EXCLUDE_FILE_REGEX}${INCLUDE_FILE_REGEX}" ] || return

    # 先汇总所有规则将删除的路径。只有确认至少会保留一个文件，才真正执行删除。
    FILTER_DELETE_BLOCKED=true
    if ! candidate_file=$(mktemp); then
        echo -e "$(DATE_TIME) ${WARNING} 无法预检过滤结果，已跳过本次文件过滤。" >&2
        return
    fi
    _run_filter_rules preview > "${candidate_file}"
    candidate_num=$(sort -zu "${candidate_file}" | tr -cd '\0' | wc -c)
    candidate_num=${candidate_num//[[:space:]]/}
    rm -f "${candidate_file}"

    if [ "${candidate_num}" -ge "${REAL_FILE_NUM}" ]; then
        echo -e "$(DATE_TIME) ${WARNING} 检测到过滤规则会删除当前任务全部文件，已跳过本次文件过滤。"
        log_line "${CF_LOG}" WARNING "过滤规则会删除当前任务全部文件，已跳过本次文件过滤: ${SOURCE_PATH}"
        return
    fi

    FILTER_DELETE_BLOCKED=false
    echo -e "$(DATE_TIME) ${INFO} 删除不需要的文件..."
    _run_filter_rules delete
}

# 删除过滤后遗留的空目录（DET=true 时启用）
DELETE_EMPTY_DIR() {
    if [ "${FILTER_DELETE_BLOCKED:-false}" != "true" ] \
        && [ "${DET}" = "true" ] && IS_TASK_SOURCE_PATH "${SOURCE_PATH}"; then
        echo -e "$(DATE_TIME) ${INFO} 删除任务中空的文件夹 ..."
        # -depth 确保先处理深层目录，避免父目录未空时报错
        find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
    fi
}
