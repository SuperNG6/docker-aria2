#!/usr/bin/env bash
#
# https://github.com/P3TERX/aria2.conf
# File name：tracker.sh
# Description: Get BT trackers and add to Aria2

RED_FONT_PREFIX="\033[31m"
GREEN_FONT_PREFIX="\033[32m"
YELLOW_FONT_PREFIX="\033[1;33m"
LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
ARIA2_CONF=${1:-aria2.conf}
DOWNLOADER="curl -fsSL --connect-timeout 3 --max-time 3 --retry 2"
SCRIPT_CONF="/config/setting.conf"
NL=$'\n'
echo && echo -e "$INFO Get trackers ..."
ARIA2_CONF="/config/aria2.conf"

DATE_TIME() {
    date +"%Y/%m/%d %H:%M:%S"
}


GET_TRACKERS() {
    if [[ -z "${CTU}" ]]; then
        echo && echo -e "$(DATE_TIME) ${INFO} Get BT trackers..."
        TRACKER=$(
            ${DOWNLOADER} https://trackerslist.com/all_aria2.txt ||
                ${DOWNLOADER} https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt ||
                ${DOWNLOADER} https://trackers.p3terx.com/all_aria2.txt
        )
    else
        echo && echo -e "$(DATE_TIME) ${INFO} Get BT trackers from url(s):${CTU} ..."
        URLS=$(echo ${CTU} | tr "," "$NL")
        for URL in $URLS; do
            TRACKER+="$(${DOWNLOADER} ${URL} | tr "," "\n")$NL"
        done
        TRACKER="$(echo "$TRACKER" | awk NF | sort -u | sed 'H;1h;$!d;x;y/\n/,/' )"
    fi

    [[ -z "${TRACKER}" ]] && {
        echo
        echo -e "$(DATE_TIME) ${ERROR} Unable to get trackers, network failure or invalid links." && exit 1
    }
}

ECHO_TRACKERS() {
    echo -e "
--------------------[BitTorrent Trackers]--------------------
${TRACKER}
--------------------[BitTorrent Trackers]--------------------
"
}


ADD_TRACKERS() {
    echo -e "$(DATE_TIME) ${INFO} 添加 BT trackers 到 Aria2 配置文件中 ${LIGHT_PURPLE_FONT_PREFIX}${ARIA2_CONF}${FONT_COLOR_SUFFIX} ..." && echo
    if [ ! -f ${ARIA2_CONF} ]; then
        echo -e "$(DATE_TIME) ${ERROR} '${ARIA2_CONF}' 不存在"
        exit 1
    else
        [ -z $(grep "bt-tracker=" ${ARIA2_CONF}) ] && echo "bt-tracker=" >>${ARIA2_CONF}
        sed -i "s@^\(bt-tracker=\).*@\1${TRACKER}@" ${ARIA2_CONF} && echo -e "$(DATE_TIME) ${INFO} 成功添加 BT trackers 到 Aria2 配置文件中!"
    fi
}

GET_TRACKERS
ECHO_TRACKERS
ADD_TRACKERS
