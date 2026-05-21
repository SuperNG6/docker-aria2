#!/usr/bin/env bash

DOWNLOADER="curl -fsSL --connect-timeout 3 --max-time 3 --retry 2"
NL=$'\n'

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
        TRACKER="$(echo "$TRACKER" | awk NF | sort -u | sed 'H;1h;$!d;x;y/\n/,/')"
    fi
    [[ -z "${TRACKER}" ]] && {
        echo -e "$(DATE_TIME) ${ERROR} 无法获取 trackers，网络故障或链接无效"
        exit 1
    }
}

ECHO_TRACKERS() {
    echo -e "
--------------------[BitTorrent Trackers]--------------------
${TRACKER}
--------------------[BitTorrent Trackers]--------------------
"
}
