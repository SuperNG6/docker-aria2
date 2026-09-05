#!/usr/bin/env bash
# 每次仅执行一组；由宿主入口为下一组启动新的 Bash，避免全局变量相互污染。
set -o pipefail
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CASE=${1:?需要库测试组名称}
. "${TESTS}/lib/assert.sh"
equal "$(id -u abc)" "$(id -u)" '库测试必须由 abc 执行'
TEST_ROOT=$(mktemp -d /downloads/lib-test.XXXXXX) || die '无法创建测试目录'
LOG_DIR=$(mktemp -d /tmp/lib-test.XXXXXX) || die '无法创建日志目录'
trap 'rm -rf "${TEST_ROOT}" "${LOG_DIR}"' EXIT
. /aria2/scripts/lib/event.sh
. /aria2/scripts/lib/tracker.sh
[ ! -f /etc/services.d/aria2b/run ] || . /etc/services.d/aria2b/run
DOWNLOAD_PATH=/downloads
CF_LOG="${LOG_DIR}/filter.log"
MOVE_LOG="${LOG_DIR}/move.log"
DELETE_LOG="${LOG_DIR}/delete.log"
RECYCLE_LOG="${LOG_DIR}/recycle.log"
BAK_TORRENT_DIR="${TEST_ROOT}/backup-torrent"
assert '创建种子备份目录' mkdir -p "${BAK_TORRENT_DIR}"
# 已有规则组内部仍可汇总差异；唯一 PASS 由宿主在整个进程成功后打印。
ok() { :; }
ng() { die "$*"; }
hdr() { printf '%s\n' "$*"; }
. "${TESTS}/cases/library.sh"
. "${TESTS}/cases/boundaries.sh"
case "${CASE}" in
    filter-rules) t_filter_rules ;;
    filter-guard) t_filter_eligibility_and_guard ;;
    paths) t_path_contracts; path_aliases ;;
    torrent) t_torrent_modes ;;
    tracker) t_tracker_contracts ;;
    banner) t_startup_banner_contract ;;
    a2b-scheme) t_aria2b_rpc_scheme ;;
    config-failure) config_copy_failure ;;
    *) die "未知库测试组: ${CASE}" ;;
esac
