#!/usr/bin/env bash
# 纯规则组；生产全局变量只允许在库层构造。
reset_filter_vars() {
    MIN_SIZE=""
    INCLUDE_FILE=""
    EXCLUDE_FILE=""
    KEYWORD_FILE=""
    INCLUDE_FILE_REGEX=""
    EXCLUDE_FILE_REGEX=""
}

make_task() {
    local name=$1
    shift
    local task="${TEST_ROOT}/${name}" spec file size
    assert "清理规则夹具 ${name}" rm -rf "${task}"
    assert "创建规则夹具 ${name}" mkdir -p "${task}"
    for spec in "$@"; do
        file=${spec%%:*}
        size=${spec##*:}
        assert "写入规则夹具 ${file}" dd if=/dev/zero of="${task}/${file}" bs=1024 count="${size}" 2>/dev/null
    done
    printf '%s' "${task}"
}

t_filter_rules() {
    hdr "1. 过滤规则与文件名边界"
    local fail="" task conf

    task=$(make_task filter-ext \
        movie.mp4:2 cover.jpg:1 readme.txt:1 sub.srt:1) || die "规则夹具准备失败"
    SOURCE_PATH="${task}"
    reset_filter_vars
    EXCLUDE_FILE='txt|jpg'
    DELETE_EXCLUDE_FILE >/dev/null
    [ -f "${task}/movie.mp4" ] \
        && [ -f "${task}/sub.srt" ] \
        && [ ! -e "${task}/cover.jpg" ] \
        && [ ! -e "${task}/readme.txt" ] \
        || fail+=" extension"

    task=$(make_task 广告合集 movie.mp4:2 sample.mp4:1 episode.mkv:1) || die "规则夹具准备失败"
    SOURCE_PATH="${task}"
    reset_filter_vars
    KEYWORD_FILE='广告|sample'
    DELETE_EXCLUDE_FILE >/dev/null
    [ -f "${task}/movie.mp4" ] \
        && [ -f "${task}/episode.mkv" ] \
        && [ ! -e "${task}/sample.mp4" ] \
        || fail+=" basename"

    task=$(make_task filter-size big.bin:10 exact.bin:5 small.bin:3) || die "规则夹具准备失败"
    SOURCE_PATH="${task}"
    reset_filter_vars
    MIN_SIZE=5k
    DELETE_EXCLUDE_FILE >/dev/null
    [ -f "${task}/big.bin" ] \
        && [ -f "${task}/exact.bin" ] \
        && [ ! -e "${task}/small.bin" ] \
        || fail+=" size-boundary"

    conf="${LOG_DIR}/quoted-filter.conf"
    printf '%s\n' \
        'include-file=mp4|mkv' \
        'include-file-regex=^.*\.(mp4|mkv)$' \
        'exclude-file-regex="(.*/)_+(padding)(_*)(file)(.*)(_+)"' \
        > "${conf}"
    FILTER_CONF="${conf}"
    reset_filter_vars
    LOAD_FILTER_CONF
    [ "${INCLUDE_FILE}" = 'mp4|mkv' ] \
        && [ "${INCLUDE_FILE_REGEX}" = '^.*\.(mp4|mkv)$' ] \
        && [ "${EXCLUDE_FILE_REGEX}" = '(.*/)_+(padding)(_*)(file)(.*)(_+)' ] \
        || fail+=" config-parse"
    FILTER_CONF=/config/文件过滤.conf

    if [ -z "${fail}" ]; then
        ok "扩展名、文件名关键词、大小边界和配置解析正确"
    else
        ng "过滤规则组异常:${fail}"
    fi
}

t_filter_eligibility_and_guard() {
    hdr "2. 多文件判定与全部文件保护"
    local fail="" task output

    task=$(make_task filter-single only.txt:1) || die "规则夹具准备失败"
    SOURCE_PATH="${task}"
    reset_filter_vars
    EXCLUDE_FILE=txt
    DELETE_EXCLUDE_FILE >/dev/null
    [ -f "${task}/only.txt" ] && [ "${REAL_FILE_NUM}" -eq 1 ] \
        || fail+=" single-file"

    task=$(make_task filter-all keep.mp4:2 remove.txt:1) || die "规则夹具准备失败"
    mkdir -p "${task}/empty-dir"
    SOURCE_PATH="${task}"
    DET=true
    reset_filter_vars
    EXCLUDE_FILE=txt
    KEYWORD_FILE=keep
    : > "${CF_LOG}"
    output="${LOG_DIR}/filter-output.log"
    DELETE_EXCLUDE_FILE > "${output}" 2>&1
    DELETE_EMPTY_DIR >/dev/null
    [ -f "${task}/keep.mp4" ] \
        && [ -f "${task}/remove.txt" ] \
        && [ -d "${task}/empty-dir" ] \
        && [ "${FILTER_DELETE_BLOCKED}" = true ] \
        && grep -Fq '会删除当前任务全部文件' "${output}" \
        || fail+=" all-file-guard"

    task=$(make_task filter-dedup ad.txt:1 keep.mp4:2) || die "规则夹具准备失败"
    SOURCE_PATH="${task}"
    DET=false
    reset_filter_vars
    EXCLUDE_FILE=txt
    KEYWORD_FILE=ad
    DELETE_EXCLUDE_FILE >/dev/null
    [ ! -e "${task}/ad.txt" ] \
        && [ -f "${task}/keep.mp4" ] \
        && [ "${FILTER_DELETE_BLOCKED}" = false ] \
        || fail+=" candidate-dedup"

    if [ -z "${fail}" ]; then
        ok "单文件跳过、组合规则保护和重复候选去重正确"
    else
        ng "过滤资格与保护组异常:${fail}"
    fi
}

t_path_contracts() {
    hdr "3. 任务路径计算与操作边界"
    local fail="" result

    result=$(
        DOWNLOAD_PATH=/downloads
        DOWNLOAD_DIR=/downloads
        TARGET_DIR=/downloads/completed
        FILE_PATH=/downloads/movie.mp4
        FILE_NUM=1
        INFO_HASH=null
        GET_FINAL_PATH
        printf '%s|%s|%s' "${SOURCE_PATH}" "${TARGET_PATH}" "${TASK_NAME}"
    )
    [ "${result}" = '/downloads/movie.mp4|/downloads/completed|movie' ] \
        || fail+=" http-root"

    result=$(
        DOWNLOAD_PATH=/downloads
        DOWNLOAD_DIR=/downloads
        TARGET_DIR=/downloads/completed
        FILE_PATH='/downloads/show name/episode.mkv'
        FILE_NUM=2
        INFO_HASH=abc123
        GET_FINAL_PATH
        printf '%s|%s|%s' "${SOURCE_PATH}" "${TARGET_PATH}" "${COMPLETED_DIR}"
    )
    [ "${result}" = '/downloads/show name|/downloads/completed|/downloads/completed/show name' ] \
        || fail+=" bt-multi"

    result=$(
        DOWNLOAD_PATH=/downloads
        DOWNLOAD_DIR=/downloads
        TARGET_DIR=/downloads/completed
        FILE_PATH=/downloads/single.iso
        FILE_NUM=1
        INFO_HASH=abc123
        GET_FINAL_PATH
        printf '%s|%s' "${SOURCE_PATH}" "${TASK_NAME}"
    )
    [ "${result}" = '/downloads/single.iso|single' ] \
        || fail+=" bt-single-root"

    IS_TASK_SOURCE_PATH /downloads && fail+=" root-guard"
    IS_TASK_SOURCE_PATH /downloads/completed && fail+=" completed-guard"
    IS_TASK_SOURCE_PATH /downloads/recycle && fail+=" recycle-guard"
    IS_TASK_SOURCE_PATH /downloads/move-failed && fail+=" failed-guard"
    IS_TASK_SOURCE_PATH /outside/task && fail+=" outside-guard"
    IS_TASK_SOURCE_PATH '/downloads/normal task' || fail+=" valid-task"

    if [ -z "${fail}" ]; then
        ok "HTTP/BT 路径语义及根目录、共享目录、越界保护正确"
    else
        ng "路径契约组异常:${fail}"
    fi
}

t_torrent_modes() {
    local row mode expected base rc output
    # 表格是用户可见的文件布局，不根据生产分支推导期望值。
    for row in retain:source/source.torrent delete:absent rename:source/fixture.torrent \
        backup:backup/source.torrent backup-rename:backup/fixture.torrent future-mode:source/source.torrent; do
        mode=${row%%:*}
        expected=${row#*:}
        base="${TEST_ROOT}/torrent-${mode}"
        assert '创建种子夹具目录' mkdir -p "${base}/source" "${base}/backup"
        assert '写入种子夹具' bash -c 'printf TORRENT > "$1"' bash "${base}/source/source.torrent"
        DOWNLOAD_DIR="${base}/source"
        BAK_TORRENT_DIR="${base}/backup"
        TASK_NAME=fixture
        TORRENT_FILE="${base}/source/source.torrent"
        TOR=${mode}
        assert "种子处理 ${mode}" HANDLE_TORRENT
        if [ "${expected}" = absent ]; then
            equal 0 "$(find "${base}" -type f | wc -l | tr -d '[:space:]')" '删除后不应留副本'
        else
            equal TORRENT "$(cat "${base}/${expected}")" "种子内容 ${mode}"
            equal 1 "$(find "${base}" -type f | wc -l | tr -d '[:space:]')" "种子只有一个副本 ${mode}"
        fi
    done
    TOR=backup-rename
    BAK_TORRENT_DIR=/proc/aria2-test-unavailable
    rc=0
    output=$(HANDLE_TORRENT 2>&1) || rc=$?
    [ "${rc}" -ne 0 ] || die '备份失败应返回非零'
    equal TORRENT "$(cat "${TORRENT_FILE}")" '备份失败保留种子'
    [[ "${output}" == *"重命名并备份种子文件失败"* ]] || die '缺少备份失败日志'
}

t_tracker_contracts() {
    hdr "5. Tracker 文件写入与 RPC 响应契约"
    local fail="" conf output rc result tmp1 tmp2

    conf="${LOG_DIR}/aria2.conf"
    printf 'listen-port=6881\n' > "${conf}"
    TRACKER='udp://example.test/announce?key=a&b=c'
    _update_file "${conf}" >/dev/null
    grep -Fxq "bt-tracker=${TRACKER}" "${conf}" || fail+=" file-write"

    # _update_rpc 通过命令查找间接调用测试桩，ShellCheck 无法静态追踪。
    # shellcheck disable=SC2329
    curl() { printf '%s\n' '{"jsonrpc":"2.0","id":"NG6","result":"OK"}'; }
    export -f curl
    TRACKER=udp://success.test:1
    PORT=6800
    SECRET='test'
    output=$(_update_rpc 2>&1)
    rc=$?
    unset -f curl
    [ "${rc}" -eq 0 ] && [[ "${output}" == *"更新成功"* ]] \
        || fail+=" rpc-success"

    # shellcheck disable=SC2329
    curl() {
        printf '%s\n' \
            '{"jsonrpc":"2.0","id":"NG6","error":{"code":1,"message":"Token NOT OK"}}'
    }
    export -f curl
    output=$(_update_rpc 2>&1)
    rc=$?
    unset -f curl
    [ "${rc}" -ne 0 ] && [[ "${output}" == *"RPC 接口错误"* ]] \
        || fail+=" rpc-error"

    tmp1="${LOG_DIR}/tracker-1.txt"
    tmp2="${LOG_DIR}/tracker-2.txt"
    printf '%s\n' 'udp://a.test:1,udp://b.test:2' > "${tmp1}"
    printf '%s\n' 'udp://b.test:2,udp://c.test:3' > "${tmp2}"
    CTU="file://${tmp1},file://${tmp2}"
    TRACKER=""
    GET_TRACKERS >/dev/null 2>&1
    result="${TRACKER}"
    unset CTU
    [ "$(printf '%s' "${result}" | tr ',' '\n' | sort -u | wc -l)" -eq 3 ] \
        && [[ "${result}" == *"a.test:1"* ]] \
        && [[ "${result}" == *"b.test:2"* ]] \
        && [[ "${result}" == *"c.test:3"* ]] \
        || fail+=" ctu-dedup"

    if [ -z "${fail}" ]; then
        ok "特殊字符写入、严格 JSON 成功判断和 CTU 去重正确"
    else
        ng "Tracker 契约组异常:${fail}"
    fi
}

t_startup_banner_contract() {
    hdr "6. 启动信息的数据来源与脱敏"
    local fail="" conf setting missing out secret
    conf="${LOG_DIR}/startup-aria2.conf"
    setting="${LOG_DIR}/startup-setting.conf"
    missing="${LOG_DIR}/missing-setting.conf"
    secret='startup-secret-must-not-leak'

    printf 'rpc-secure=true\n' > "${conf}"
    printf '%s\n' \
        'remove-task=recycle' \
        'move-task=dmof' \
        'content-filter=false' \
        'delete-empty-dir=true' \
        'handle-torrent=backup-rename' \
        'remove-repeat-task=false' \
        'move-paused-task=true' \
        > "${setting}"

    out=$(SECRET="${secret}" PORT=16800 BTPORT=32517 \
        WEBUI=false WEBUI_PORT=18080 CACHE=512M QUIET=false \
        UT=false RUT=true CTU=https://tracker.example/list \
        SMD=false FA=trunc A2B=true CRA2B=false A2B_DISABLE_LOG=true \
        bash /etc/cont-init.d/11-version "${conf}" "${setting}" 2>&1)

    [[ "${out}" == *"RPC协议: HTTPS"* ]] || fail+=" rpc"
    [[ "${out}" == *"WebUI端口: 18080 [禁用]"* ]] || fail+=" webui"
    [[ "${out}" == *"完成任务自动移动: [按规则启用：根目录单文件不移动]"* ]] \
        || fail+=" setting"
    [[ "${out}" == *"磁力种子处理: 重命名并备份 [不生效：磁力元数据保存未启用]"* ]] \
        || fail+=" dependency"
    [[ "${out}" != *"(Aria2)"* ]] || fail+=" aria2-version"
    [[ "${out}" != *"${secret}"* ]] || fail+=" secret"

    rm -f "${missing}"
    out=$(SECRET=randomXYZ123 bash /etc/cont-init.d/11-version \
        "${LOG_DIR}/missing-aria2.conf" "${missing}" 2>&1)
    [[ "${out}" == *"首次配置: 检测到配置文件缺失"* ]] \
        && [[ "${out}" == *"附加下载处理: 本次使用项目默认配置"* ]] \
        && [[ "${out}" != *"完成任务自动移动:"* ]] \
        || fail+=" first-start"

    if [ -z "${fail}" ]; then
        ok "已有/首次配置展示正确，自定义 SECRET 未泄露"
    else
        ng "启动信息契约组异常:${fail}"
    fi
}

t_aria2b_rpc_scheme() {
    [ -f /etc/services.d/aria2b/run ] || die "a2b 服务入口不存在"
    hdr "7. aria2b 本地 RPC 协议选择"
    local fail="" conf url
    conf="${LOG_DIR}/aria2b.conf"

    printf '%s\n' '# rpc-secure=true' 'rpc-secure=false' > "${conf}"
    url=$(GET_ARIA2B_RPC_URL "${conf}")
    [ "${url}" = "http://127.0.0.1:${PORT}/jsonrpc" ] || fail+=" http"

    printf 'rpc-secure=true\n' > "${conf}"
    url=$(GET_ARIA2B_RPC_URL "${conf}")
    [ "${url}" = "https://127.0.0.1:${PORT}/jsonrpc" ] || fail+=" https"

    if [ -z "${fail}" ]; then
        ok "注释/false 使用 HTTP，有效 true 使用 HTTPS"
    else
        ng "aria2b RPC URL 组异常:${fail}"
    fi
}

