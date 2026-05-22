#!/usr/bin/env bash
# BT tracker 列表更新脚本（双模式）
# 用法：tracker.sh [file|rpc] [aria2.conf 路径]
#   file（默认）- 把 tracker 列表写入 aria2.conf；由 cont-init.d/30-config 在启动时调用（UT=true）
#   rpc         - 通过 Aria2 JSON-RPC 动态更新 tracker，无需重启；由 cron 调用（RUT=true）
# aria2.conf 路径仅 file 模式使用，默认 /config/aria2.conf

_D="$(dirname "${BASH_SOURCE[0]}")"
. "${_D}/log.sh"  # 颜色变量和 DATE_TIME

# curl 下载器，3 秒连接超时、3 秒最大时长、最多重试 2 次
DOWNLOADER="curl -fsSL --connect-timeout 3 --max-time 3 --retry 2"
NL=$'\n'  # 换行符，用于分隔多个自定义 URL

# 获取最新 BT tracker 列表，结果存入 TRACKER 变量（逗号分隔格式，适配 aria2 bt-tracker 参数）
# 无自定义地址（CTU 为空）时按优先级尝试三个公共源：
#   1. trackerslist.com（主源）
#   2. jsdelivr CDN 镜像（主源不可达时备用）
#   3. ghp.ci GitHub 代理（中国大陆备用）
# 有自定义地址（CTU 环境变量，逗号分隔多个 URL）时从自定义源获取并去重合并
GET_TRACKERS() {
    if [[ -z "${CTU}" ]]; then
        echo && echo -e "$(DATE_TIME) ${INFO} 获取 BT trackers..."
        TRACKER=$(
            ${DOWNLOADER} https://trackerslist.com/all_aria2.txt ||
            ${DOWNLOADER} https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt ||
            ${DOWNLOADER} https://ghp.ci/https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/all_aria2.txt
        )
    else
        echo && echo -e "$(DATE_TIME) ${INFO} 从自定义地址获取 BT trackers: ${CTU}"
        URLS=$(echo "${CTU}" | tr "," "$NL")
        for URL in $URLS; do
            TRACKER+="$(${DOWNLOADER} "${URL}" | tr "," "\n")$NL"
        done
        # 去重、去空行，然后用 paste 把多行折成单行逗号分隔（适配 aria2 bt-tracker 参数）
        TRACKER="$(echo "$TRACKER" | awk NF | sort -u | paste -sd , -)"
    fi
    [[ -z "${TRACKER}" ]] && {
        echo -e "$(DATE_TIME) ${ERROR} 无法获取 trackers，网络故障或链接无效"
        exit 1
    }
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
        echo -e "$(DATE_TIME) ${ERROR} '${conf}' 不存在"
        exit 1
    fi
    # 若 bt-tracker= 行尚不存在，先追加空行，确保 sed 能匹配
    grep -q "^bt-tracker=" "${conf}" || echo "bt-tracker=" >> "${conf}"
    # sed replacement 中的 \、& 和分隔符 @ 都有特殊含义，写入配置前必须转义
    escaped_tracker=$(printf '%s' "${TRACKER}" | sed -e 's/[\\&@]/\\&/g')
    sed -i "s@^\(bt-tracker=\).*@\1${escaped_tracker}@" "${conf}" && \
        echo -e "$(DATE_TIME) ${INFO} 成功添加 BT trackers 到 Aria2 配置文件中!"
}

# 通过 RPC 调用 aria2.changeGlobalOption 动态更新 tracker
# 优先 http，失败自动降级为 https（自签证书用 -k 跳过验证）
_update_rpc() {
    local addr="localhost:${PORT}/jsonrpc"
    local payload result
    # jq 构造 payload：SECRET / TRACKER 中的特殊字符会被正确转义
    payload=$(jq -nc \
        --arg secret "${SECRET}" \
        --arg tracker "${TRACKER}" \
        '{jsonrpc:"2.0",method:"aria2.changeGlobalOption",id:"NG6",
          params:(if $secret == ""
                  then [{"bt-tracker": $tracker}]
                  else ["token:" + $secret, {"bt-tracker": $tracker}]
                  end)}')
    result=$(curl "${addr}" -fsSd "${payload}" || curl "https://${addr}" -kfsSd "${payload}")
    if echo "${result}" | grep -q OK; then
        echo -e "$(DATE_TIME) ${INFO} BT trackers 更新成功!"
    else
        echo -e "$(DATE_TIME) ${ERROR} 网络故障或 Aria2 RPC 接口错误!"
    fi
}

main() {
    GET_TRACKERS   # 从公共源或自定义地址（CTU 变量）拉取 tracker 列表
    ECHO_TRACKERS  # 打印到终端，便于日志确认

    case "${1:-file}" in
        file) _update_file "${2:-/config/aria2.conf}" ;;
        rpc)  _update_rpc ;;
        *)
            echo -e "$(DATE_TIME) ${ERROR} 未知模式: ${1}（应为 file 或 rpc）"
            exit 1
            ;;
    esac
}

main "$@"
