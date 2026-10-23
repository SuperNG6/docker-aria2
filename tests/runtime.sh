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
# 重启类场景的准备步骤，以及必须保留启动结果的检查，不套用下面的测试基线配置。
case "${CASE}" in
    config-upgrade-prepare) config_upgrade_prepare; exit ;;
    hook-registration-prepare) hook_registration_prepare; exit ;;
    rpc-tls-prepare) rpc_tls_prepare; exit ;;
    config-upgrade) config_upgrade; exit ;;
    identity) identity; exit ;;
esac
# 零配置场景直接使用模板默认值；其余场景明确准备自己的配置。
if [ "${CASE}" != magnet ]; then
    setting move-task false
    setting remove-task rmaria
    setting content-filter false
    setting delete-empty-dir true
    setting handle-torrent retain
    setting remove-repeat-task false
    setting move-paused-task false
fi
sentinel
case "${CASE}" in
    http) http_completion ;;
    http-nested) http_nested ;;
    complex-bt) complex_bt ;;
    magnet) magnet_default ;;
    filter-partial|filter-all|selected) bt_completion "${CASE}" ;;
    single-bt) single_bt ;;
    cross-device|move-failure) move_storage "${CASE}" ;;
    repeat) repeat_task ;;
    pause-move|pause-disable|pause-resume) pause_task "${CASE}" ;;
    recycle|delete|recycle-failure) stop_task "${CASE}" ;;
    stop-inactive) stop_inactive ;;
    reserved) reserved_directory ;;
    ownership-root|ownership-custom) ownership ;;
    hook-registration) hook_registration ;;
    rpc-tls) rpc_tls ;;
    *) die "未知场景: ${CASE}" ;;
esac
eventually 15 'hook 完成' hook_idle
sentinels_unchanged
