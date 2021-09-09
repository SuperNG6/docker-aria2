#!/usr/bin/env bash
# Copyright (c) 2018-2020 P3TERX <https://p3terx.com>

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


ADD_TRACKERS_RPC() {
    if [[ "${SECRET}" ]]; then
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"NG6","params":["token:'${SECRET}'",{"bt-tracker":"'${TRACKER}'"}]}'
    else
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"NG6","params":[{"bt-tracker":"'${TRACKER}'"}]}'
    fi
    curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}"
}

ADD_TRACKERS_RPC_STATUS() {
    RPC_RESULT=$(ADD_TRACKERS_RPC)
    [[ $(echo ${RPC_RESULT} | grep OK) ]] &&
        echo -e "$(DATE_TIME) ${INFO} BT trackers successfully added to Aria2 !" ||
        echo -e "$(DATE_TIME) ${ERROR} Network failure or Aria2 RPC interface error!"
}

RPC_ADDRESS="localhost:${PORT}/jsonrpc"
GET_TRACKERS
ECHO_TRACKERS
ADD_TRACKERS_RPC
ADD_TRACKERS_RPC_STATUS
