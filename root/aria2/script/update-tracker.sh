#!/usr/bin/env bash
# 更新 aria2.conf 中的 BT tracker 列表（基于配置文件，需重启 aria2 或 aria2 --save-session 后生效）
# 由 cont-init.d/30-config 在容器启动时调用（UT=true 时）
# 用法：update-tracker.sh [/path/to/aria2.conf]

_D="$(dirname "$0")/lib"
. "${_D}/log.sh"     # 颜色变量和 DATE_TIME
. "${_D}/tracker.sh" # GET_TRACKERS、ECHO_TRACKERS

# 支持通过参数指定配置文件路径，默认为 /config/aria2.conf
ARIA2_CONF=${1:-/config/aria2.conf}

echo && echo -e "${INFO} Get trackers ..."

GET_TRACKERS   # 从公共源或自定义地址（CTU 变量）拉取 tracker 列表
ECHO_TRACKERS  # 打印到终端，便于日志确认

if [ ! -f "${ARIA2_CONF}" ]; then
    echo -e "$(DATE_TIME) ${ERROR} '${ARIA2_CONF}' 不存在"
    exit 1
fi

# 若配置文件中还没有 bt-tracker= 行，先追加一个空行（确保下一步 sed 能匹配）
grep -q "^bt-tracker=" "${ARIA2_CONF}" || echo "bt-tracker=" >> "${ARIA2_CONF}"

# 将 tracker 列表写入配置文件的 bt-tracker 行
sed -i "s@^\(bt-tracker=\).*@\1${TRACKER}@" "${ARIA2_CONF}" && \
    echo -e "$(DATE_TIME) ${INFO} 成功添加 BT trackers 到 Aria2 配置文件中!"
