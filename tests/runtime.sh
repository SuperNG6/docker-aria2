#!/usr/bin/env bash
set -Eeuo pipefail
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CASE=${1:?需要场景名称}
. "${TESTS}/lib/assert.sh"
. "${TESTS}/lib/runtime.sh"
trap 'printf "ERROR [%s] %s:%s: %s\n" "$CASE" "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND" >&2' ERR
equal "$(id -u abc)" "$(id -u)" '场景必须由 abc 执行'
eventually 45 'RPC 就绪' rpc aria2.getVersion
assert 'WebUI 可访问' curl -fsS --max-time 3 http://127.0.0.1:8080/ -o /dev/null
. "${TESTS}/cases/lifecycle.sh"
. "${TESTS}/cases/configuration.sh"
# 配置重启检查必须先保留启动结果；其余场景明确准备自己的配置。
case "${CASE}" in
    config-prepare) config_prepare; exit ;;
    config-upgrade) config_upgrade; exit ;;
    identity) identity; exit ;;
esac
setting move-task false
setting remove-task rmaria
setting content-filter false
setting delete-empty-dir true
setting handle-torrent retain
setting remove-repeat-task false
setting move-paused-task false
sentinel
case "${CASE}" in
    http) http_completion ;;
    filter-partial|filter-all|selected) bt_completion "${CASE}" ;;
    single-bt) single_bt ;;
    cross-device|move-failure) move_storage "${CASE}" ;;
    repeat) repeat_task ;;
    pause-move|pause-disable|pause-resume) pause_task "${CASE}" ;;
    recycle|delete|recycle-failure) stop_task "${CASE}" ;;
    reserved) reserved_directory ;;
    *) die "未知场景: ${CASE}" ;;
esac
eventually 15 'hook 完成' hook_idle
sentinels_unchanged
