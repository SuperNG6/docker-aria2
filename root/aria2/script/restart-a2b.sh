#!/usr/bin/env bash
# aria2b 定时重启脚本
# 由 cont-init.d/40-config 在 A2B=true 时调用，向 crontab 注册定时重启任务
# aria2b 长时间运行后可能出现连接积压，定期重启可保持其正常工作

CRON_MARKER="restart-aria2b"  # crontab 注释标记，用于精确识别和替换本脚本添加的行

if [ "${CRA2B}" = "false" ]; then
    # CRA2B=false 表示禁用定时重启，移除已有的重启任务
    crontab -l 2>/dev/null | grep -v "${CRON_MARKER}" | crontab -
    echo "CRA2B=false，已移除定时重启 aria2b 任务。"
    exit 0
fi

# 从 CRA2B 变量（如 "2h"）提取数字部分作为间隔小时数
HOURS=$(echo "${CRA2B}" | sed 's/[^0-9]*//g')

# 校验小时数范围（1-24），无效则使用默认值 2
if [[ ! "${HOURS}" =~ ^([1-9]|1[0-9]|2[0-4])$ ]]; then
    HOURS=2
    echo "CRA2B 值无效，使用默认值 2 小时。"
fi

# 先移除旧的重启任务（防止重复添加），再写入新的定时任务
# pkill -x aria2b：精确匹配进程名，避免误杀名称相近的进程（比 kill -9 + PID 查找更安全）
# s6 会在 aria2b 退出后自动重启它（services.d/aria2b/run），因此 pkill 即可实现重启
crontab -l 2>/dev/null | grep -v "${CRON_MARKER}" | crontab -
(crontab -l 2>/dev/null; echo "0 */${HOURS} * * * pkill -x aria2b # ${CRON_MARKER}") | crontab -
echo "已设置定时重启任务：每 ${HOURS} 小时重启 aria2b 进程。"
