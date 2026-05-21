#!/usr/bin/env bash
# BT Tracker 获取库：从公共列表或自定义地址拉取最新 tracker 列表
# 被 update-tracker.sh（写入配置文件）和 update-tracker-rpc.sh（RPC 动态更新）共同引用
# 需先引入 log.sh 以使用颜色变量和 DATE_TIME()

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
        # 去重、去空行，然后转换回逗号分隔格式
        TRACKER="$(echo "$TRACKER" | awk NF | sort -u | sed 'H;1h;$!d;x;y/\n/,/')"
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
