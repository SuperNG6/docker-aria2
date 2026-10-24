#!/usr/bin/env bash
# BT tracker 列表更新脚本（双模式）
# 用法：tracker.sh [file|rpc] [aria2.conf 路径]
#   file（默认）- 把 tracker 列表写入 aria2.conf；由 cont-init.d/30-config 在启动时调用（UT=true）
#   rpc         - 通过 Aria2 JSON-RPC 动态更新 tracker，无需重启；由 cron 调用（RUT=true）
# aria2.conf 路径仅 file 模式使用，默认 /config/aria2.conf

_D="$(dirname "${BASH_SOURCE[0]}")"
. "${_D}/log.sh"  # 颜色变量和 DATE_TIME
. "${_D}/rpc.sh"  # RPC_CALL

# curl 下载器，3 秒连接超时、3 秒最大时长、最多重试 2 次
# 用数组装参数：未来若 URL 含空格或加新 flag，可避免词法分割引发的隐性 bug
DOWNLOADER=(curl -fsSL --connect-timeout 3 --max-time 3 --retry 2)
NL=$'\n'  # 换行符，用于分隔多个自定义 URL

# 获取最新 BT tracker 列表，结果存入 TRACKER 变量（逗号分隔格式，适配 aria2 bt-tracker 参数）
# 无自定义地址（CTU 为空）时按优先级尝试两个公共源：
#   1. trackerslist.com（主源）
#   2. jsdelivr CDN 镜像（主源不可达时备用）
# 有自定义地址（CTU 环境变量，逗号分隔多个 URL）时从自定义源获取并去重合并
GET_TRACKERS() {
    if [[ -z "${CTU}" ]]; then
        echo && echo -e "$(DATE_TIME) ${INFO} 获取 BT trackers..."
        TRACKER=$(
            "${DOWNLOADER[@]}" https://trackerslist.com/all_aria2.txt ||
            "${DOWNLOADER[@]}" https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt
        )
    else
        echo && echo -e "$(DATE_TIME) ${INFO} 从自定义地址获取 BT trackers: ${CTU}"
        URLS=$(echo "${CTU}" | tr "," "$NL")
        for URL in $URLS; do
            TRACKER+="$("${DOWNLOADER[@]}" "${URL}" | tr "," "\n")$NL"
        done
        # 去重、去空行，然后用 paste 把多行折成单行逗号分隔（适配 aria2 bt-tracker 参数）
        TRACKER="$(echo "$TRACKER" | awk NF | sort -u | paste -sd , -)"
    fi
    if [[ -z "${TRACKER}" ]]; then
        echo -e "$(DATE_TIME) ${ERROR} 无法获取 trackers，网络故障或链接无效" >&2
        return 1
    fi
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
