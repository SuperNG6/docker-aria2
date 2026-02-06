#!/usr/bin/env bash
#
# https://github.com/P3TERX/aria2.conf
# File name：tracker.sh
# Description: Get BT trackers and add to Aria2

. "$(dirname "$0")/tracker_common"

ARIA2_CONF=${1:-/config/aria2.conf}
echo && echo -e "$INFO Get trackers ..."

ADD_TRACKERS() {
    echo -e "$(DATE_TIME) ${INFO} 添加 BT trackers 到 Aria2 配置文件中 ${LIGHT_PURPLE_FONT_PREFIX}${ARIA2_CONF}${FONT_COLOR_SUFFIX} ..." && echo
    if [ ! -f "${ARIA2_CONF}" ]; then
        echo -e "$(DATE_TIME) ${ERROR} '${ARIA2_CONF}' 不存在"
        exit 1
    else
        [ -z "$(grep "bt-tracker=" "${ARIA2_CONF}")" ] && echo "bt-tracker=" >>"${ARIA2_CONF}"
        sed -i "s@^\(bt-tracker=\).*@\1${TRACKER}@" "${ARIA2_CONF}" && echo -e "$(DATE_TIME) ${INFO} 成功添加 BT trackers 到 Aria2 配置文件中!"
    fi
}

GET_TRACKERS
ECHO_TRACKERS
ADD_TRACKERS
