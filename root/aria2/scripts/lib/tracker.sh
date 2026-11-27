#!/usr/bin/env bash
# BT tracker 列表更新脚本（双模式）
# 用法：tracker.sh [file|rpc] [aria2.conf 路径]
#   file（默认）- 把 tracker 列表写入 aria2.conf；由 cont-init.d/30-config 在启动时调用（UT=true）
#   rpc         - 通过 Aria2 JSON-RPC 动态更新 tracker，无需重启；由 cron 调用（RUT=true）
# aria2.conf 路径仅 file 模式使用，默认 /config/aria2.conf

_D="$(dirname "${BASH_SOURCE[0]}")"
. "${_D}/log.sh"  # 颜色变量和 DATE_TIME
. "${_D}/rpc.sh"  # RPC_CALL

# 每次请求最多 3 秒。只使用成功请求的完整响应，避免重试混入上次的部分内容。
DOWNLOADER=(curl -fsSL --connect-timeout 3 --max-time 3)

_download_trackers() {
    local response entries attempt
    for attempt in 1 2; do
        if ! response=$("${DOWNLOADER[@]}" -- "$1"); then
            continue
        fi

        # 同时接受逗号分隔和逐行列表。拒绝 HTML 等非 tracker 响应。
        if entries=$(printf '%s\n' "$response" | tr ',' '\n' | awk '
            { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "") }
            !NF || /^#/ { next }
            /^[[:alpha:]][[:alnum:]+.-]*:\/\/[^[:space:]]+$/ { print; next }
            { exit 1 }
        ') && [[ -n "$entries" ]]; then
            printf '%s\n' "$entries"
            return 0
        fi
    done
    return 1
}

# 获取列表供启动和 cron 共用；自定义地址按英文逗号分隔，合并有效来源并去重。
GET_TRACKERS() {
    local entries='' downloaded url
    local -a urls
    TRACKER=''
    if [[ -z "${CTU}" ]]; then
        echo && echo -e "$(DATE_TIME) ${INFO} 获取 BT trackers..."
        entries=$(
            _download_trackers https://cf.trackerslist.com/all_aria2.txt ||
            _download_trackers https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt
        )
    else
        echo && echo -e "$(DATE_TIME) ${INFO} 从自定义地址获取 BT trackers: ${CTU}"
        IFS=',' read -r -a urls <<< "${CTU}"
        for url in "${urls[@]}"; do
            # 保留自定义地址列表允许在逗号周围加空白的用法。
            url="${url#"${url%%[![:space:]]*}"}"
            url="${url%"${url##*[![:space:]]}"}"
            if [[ -n "$url" ]] && downloaded=$(_download_trackers "$url"); then
                entries+="$downloaded"$'\n'
            fi
        done
        entries=$(printf '%s' "$entries" | sort -u)
    fi
    if [[ -z "$entries" ]]; then
        echo -e "$(DATE_TIME) ${ERROR} 无法获取 trackers，网络故障或链接无效" >&2
        return 1
    fi
    TRACKER=$(printf '%s\n' "$entries" | paste -sd , -)
}

# 将获取到的 tracker 列表打印到终端（用于日志确认）
ECHO_TRACKERS() {
    echo -e "
--------------------[BitTorrent Trackers]--------------------
${TRACKER}
--------------------[BitTorrent Trackers]--------------------
"
}

# 把 tracker 列表写入 aria2.conf 的 bt-tracker 行
_update_file() {
    local conf=$1 escaped_tracker
    if [ ! -f "${conf}" ]; then
        echo -e "$(DATE_TIME) ${ERROR} '${conf}' 不存在" >&2
        return 1
    fi
    # 若 bt-tracker= 行尚不存在，先追加空行，确保 sed 能匹配；
    # 文件末尾缺换行时先补一个，避免新行接在最后一行的值后面
    if ! grep -q "^bt-tracker=" "${conf}"; then
        [ -z "$(tail -c 1 "${conf}")" ] || echo >> "${conf}"
        echo "bt-tracker=" >> "${conf}"
    fi
    # sed replacement 中的 \、& 和分隔符 @ 都有特殊含义，写入配置前必须转义
    escaped_tracker=$(printf '%s' "${TRACKER}" | sed -e 's/[\\&@]/\\&/g')
    sed -i "s@^\(bt-tracker=\).*@\1${escaped_tracker}@" "${conf}" && \
        echo -e "$(DATE_TIME) ${INFO} 成功添加 BT trackers 到 Aria2 配置文件中!"
}

# 通过 RPC 调用 aria2.changeGlobalOption 动态更新 tracker
# 用 jq 严格判定 .result=="OK"，避免错误响应里附带 "OK" 文本被误判为成功
_update_rpc() {
    local result
    result=$(RPC_CALL aria2.changeGlobalOption "$(jq -nc --arg tracker "${TRACKER}" '[{"bt-tracker": $tracker}]')")
    if echo "${result}" | jq -e '.result == "OK"' >/dev/null 2>&1; then
        echo -e "$(DATE_TIME) ${INFO} BT trackers 更新成功!"
    else
        echo -e "$(DATE_TIME) ${ERROR} 网络故障或 Aria2 RPC 接口错误!" >&2
        return 1
    fi
}

main() {
    GET_TRACKERS || return 1  # 从公共源或自定义地址（CTU 变量）拉取 tracker 列表
    ECHO_TRACKERS  # 打印到终端，便于日志确认

    case "${1:-file}" in
        file) _update_file "${2:-/config/aria2.conf}" ;;
        rpc)  _update_rpc ;;
        *)
            echo -e "$(DATE_TIME) ${ERROR} 未知模式: ${1}（应为 file 或 rpc）" >&2
            return 1
            ;;
    esac
}

# source guard：被 source 时不自动跑 main，便于测试单独调 _update_file / _update_rpc
[ "${BASH_SOURCE[0]}" = "${0}" ] && main "$@"
