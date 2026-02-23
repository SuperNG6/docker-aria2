#!/usr/bin/env bash
#
# https://github.com/P3TERX/aria2.conf
# 文件名：tracker.sh
# 功能：获取 BT trackers 列表并写入 Aria2

. "$(dirname "$0")/tracker_common"

LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
ARIA2_CONF=${1:-/config/aria2.conf}
echo
LOG_INFO "准备获取 BT trackers 列表..."

ADD_TRACKERS() {
    LOG_INFO "添加 BT trackers 到 Aria2 配置文件 ${LIGHT_PURPLE_FONT_PREFIX}${ARIA2_CONF}${FONT_COLOR_SUFFIX} ..."
    echo
    if [ ! -f "${ARIA2_CONF}" ]; then
        LOG_ERROR "'${ARIA2_CONF}' 不存在"
        exit 1
    else
        if ! grep -q "^bt-tracker=" "${ARIA2_CONF}"; then
            if [ -s "${ARIA2_CONF}" ] && [ -n "$(tail -c 1 "${ARIA2_CONF}")" ]; then
                echo >>"${ARIA2_CONF}"
            fi
            echo "bt-tracker=" >>"${ARIA2_CONF}"
        fi
        sed -i "s@^\(bt-tracker=\).*@\1${TRACKER}@" "${ARIA2_CONF}" && LOG_INFO "已成功将 BT trackers 写入 Aria2 配置文件！"
    fi
}

GET_TRACKERS \
    "https://trackerslist.com/all_aria2.txt" \
    "https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt" \
    "https://trackers.p3terx.com/all_aria2.txt"
ECHO_TRACKERS
ADD_TRACKERS
