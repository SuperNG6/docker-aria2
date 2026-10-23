#!/usr/bin/env bash
# 需要 root 才能观察或操作 s6 服务的场景；只通过正式 cron 任务触发，不替换生产脚本。
set -Eeuo pipefail
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CASE=${1:?需要场景名称}
. "${TESTS}/lib/assert.sh"
trap 'printf "ERROR [%s] %s:%s: %s\n" "$CASE" "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND" >&2' ERR
equal 0 "$(id -u)" '场景必须由 root 执行'
SERVICE=/var/run/s6/services/aria2b

service_pid() {
    s6-svstat "${SERVICE}" | sed -n 's/^up (pid \([0-9][0-9]*\)).*/\1/p'
}
# 已连续运行数秒，排除"刚启动就退出"的重启循环被误当成正常运行。
service_stable() {
    s6-svstat "${SERVICE}" | grep -Eq '^up \(pid [0-9]+\) ([3-9]|[1-9][0-9]+) seconds'
}
service_restarted() {
    local pid
    pid=$(service_pid)
    [ -n "${pid}" ] && [ "${pid}" != "$1" ]
}

a2b_restart() {
    local line command before aria2c_pid
    # 定时任务只能重启 aria2b 服务，不能连带重启 aria2c；默认 CRA2B=2h 对应每两小时一次。
    line=$(crontab -l | grep -F '# restart-aria2b') || die '缺少 aria2b 定时重启任务'
    [[ "${line}" == '0 */2 * * * '* ]] || die "定时间隔与 CRA2B=2h 不符: ${line}"
    command=${line#'0 */2 * * * '}
    command=${command%%#*}
    eventually 30 'aria2b 稳定运行' service_stable
    before=$(service_pid)
    aria2c_pid=$(pgrep -x aria2c)
    # 与 crond 一样交给 sh 执行这条命令。
    assert '执行定时重启命令' sh -c "${command}"
    eventually 15 'aria2b 已重启' service_restarted "${before}"
    equal "${aria2c_pid}" "$(pgrep -x aria2c)" 'aria2c 未被重启'
}

case "${CASE}" in
    a2b-restart) a2b_restart ;;
    *) die "未知场景: ${CASE}" ;;
esac
