#!/usr/bin/env bash
#
# 更新 aria2.conf 中的 BT trackers（基于文件，需要 aria2 重载配置生效）
# 用法：update-tracker.sh [/path/to/aria2.conf]

_D="$(dirname "$0")/lib"
. "${_D}/log.sh"
. "${_D}/tracker.sh"

ARIA2_CONF=${1:-/config/aria2.conf}

echo && echo -e "${INFO} Get trackers ..."

GET_TRACKERS
ECHO_TRACKERS

if [ ! -f "${ARIA2_CONF}" ]; then
    echo -e "$(DATE_TIME) ${ERROR} '${ARIA2_CONF}' 不存在"
    exit 1
fi

[ -z "$(grep "bt-tracker=" "${ARIA2_CONF}")" ] && echo "bt-tracker=" >> "${ARIA2_CONF}"
sed -i "s@^\(bt-tracker=\).*@\1${TRACKER}@" "${ARIA2_CONF}" && \
    echo -e "$(DATE_TIME) ${INFO} 成功添加 BT trackers 到 Aria2 配置文件中!"
