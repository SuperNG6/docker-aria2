#!/bin/bash
#
# 根据 CRA2B 环境变量设置定时重启 aria2b 进程的 cron 任务
# 由 cont-init.d/40-config 在 A2B=true 时调用

CRON_MARKER="restart-aria2b"

if [ "${CRA2B}" = "false" ]; then
    crontab -l 2>/dev/null | grep -v "${CRON_MARKER}" | crontab -
    echo "CRA2B=false，已移除定时重启 aria2b 任务。"
    exit 0
fi

HOURS=$(echo "${CRA2B}" | sed 's/[^0-9]*//g')

if [[ ! "${HOURS}" =~ ^([1-9]|1[0-9]|2[0-4])$ ]]; then
    HOURS=2
    echo "CRA2B 值无效，使用默认值 2 小时。"
fi

crontab -l 2>/dev/null | grep -v "${CRON_MARKER}" | crontab -
(crontab -l 2>/dev/null; echo "0 */${HOURS} * * * pkill -x aria2b # ${CRON_MARKER}") | crontab -
echo "已设置定时重启任务：每 ${HOURS} 小时重启 aria2b 进程。"
