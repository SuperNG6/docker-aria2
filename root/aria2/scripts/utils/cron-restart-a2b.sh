#!/usr/bin/env bash
# shellcheck shell=bash
# 定时重启 aria2b
set -euo pipefail
. /aria2/scripts/lib/logger.sh

# 检查 aria2b 是否存在，不存在则静默退出
[[ -x "/usr/local/bin/aria2b" ]] || exit 0

# 仅在 A2B=true 时生效
if [[ "${A2B:-false}" != "true" ]]; then
    log_i "A2B 未启用，跳过配置 aria2b 重启定时任务。"
    exit 0
fi

VAL="${CRA2B:-2h}"
if [[ "${VAL}" == "false" ]]; then
    # 移除既有条目
    (crontab -l 2>/dev/null | grep -v "aria2b.*kill") | crontab - || true
    log_i "CRA2B=false，已移除 aria2b 重启定时任务。"
    exit 0
fi

# 提取小时数字，默认 2 小时；范围 1-24
HOURS=${VAL//[^0-9]/}
if ! [[ "${HOURS}" =~ ^([1-9]|1[0-9]|2[0-4])$ ]]; then
    HOURS=2
    log_w "CRA2B='${VAL}' 非法，回退为 ${HOURS} 小时。"
fi

# 先清理旧规则，再写入新规则（整点执行）
(crontab -l 2>/dev/null | grep -v "aria2b.*kill") | crontab - || true
(crontab -l 2>/dev/null; echo "0 */${HOURS} * * * pgrep -x aria2b >/dev/null && pkill -9 aria2b || true") | crontab -
log_i "已设置定时任务：每 ${HOURS} 小时整点重启 aria2b。"
