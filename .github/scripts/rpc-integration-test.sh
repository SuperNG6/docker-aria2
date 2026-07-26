#!/usr/bin/env bash
# 真实容器场景测试。
#
# 不 source 项目库、不复制 hook 分支、不手写 SOURCE_PATH。所有文件处理均由运行中的
# aria2c 通过正式 RPC 和 on-download-* hook 触发，最终只检查用户能观察到的 RPC、
# 文件、日志和 UID/GID。
#
# 用法:
#   rpc-integration-test.sh <host> <port> <secret> <container> [variant] [webui-port]

set -uo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-6800}"
SECRET="${3:-smoketoken}"
CONTAINER="${4:-}"
VARIANT="${5:-standard}"
WEBUI_PORT="${6:-8080}"
RPC_URL="http://${HOST}:${PORT}/jsonrpc"
TOKEN="token:${SECRET}"

# 两个文件的固定 torrent：
#   fixture-task/keep.mp4   = "KEEP\n"
#   fixture-task/remove.txt = "REMOVE\n"
# piece hash 对应两文件按 torrent 顺序拼接后的 12 字节内容。
# announce 指向本机不可用端口，测试不依赖公网 tracker；完整场景只做本地 hash 校验。
TORRENT_B64='ZDg6YW5ub3VuY2UyNzpodHRwOi8vMTI3LjAuMC4xOjkvYW5ub3VuY2UxMDpjcmVhdGVkIGJ5MjU6ZG9ja2VyLWFyaWEyIHJ1bnRpbWUgdGVzdDQ6aW5mb2Q1OmZpbGVzbGQ2Omxlbmd0aGk1ZTQ6cGF0aGw4OmtlZXAubXA0ZWVkNjpsZW5ndGhpN2U0OnBhdGhsMTA6cmVtb3ZlLnR4dGVlZTQ6bmFtZTEyOmZpeHR1cmUtdGFzazEyOnBpZWNlIGxlbmd0aGkxNjM4NGU2OnBpZWNlczIwOgZ+KEI/Sus8Rziuc7OyXrVBbZzdZWU='
COMPLETE_OPTIONS='{"dir":"/downloads","check-integrity":"true","seed-time":"0","bt-enable-lpd":"false","enable-peer-exchange":"false"}'
ACTIVE_OPTIONS='{"dir":"/downloads","file-allocation":"none","seed-time":"0","bt-enable-lpd":"false","enable-peer-exchange":"false"}'

PASS=0
FAIL=0
declare -a FAILED

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
hdr() { printf '\n──── %s ────\n' "$*"; }
ok()  { printf '  ✓ %s\n' "$*"; PASS=$((PASS + 1)); }
ng()  { printf '  ✗ %s\n' "$*"; FAIL=$((FAIL + 1)); FAILED+=("$*"); }

rpc() {
    local method=$1 params=${2:-[]}
    printf '%s' "${params}" \
        | jq -nc --arg token "${TOKEN}" --arg method "${method}" \
            'input as $params
             | {jsonrpc:"2.0",id:"runtime",method:$method,params:([$token] + $params)}' \
        | curl -fsS --connect-timeout 2 --max-time "${RPC_MAX_TIME:-30}" "${RPC_URL}" \
            -H 'Content-Type: application/json' \
            --data-binary @-
}

wait_rpc() {
    local elapsed
    for elapsed in $(seq 1 45); do
        if RPC_MAX_TIME=2 rpc aria2.getVersion '[]' 2>/dev/null \
            | jq -e '.result.version' >/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_status() {
    local gid=$1 accepted=$2 timeout=${3:-60} elapsed=0 status=""
    while ((elapsed < timeout)); do
        status=$(rpc aria2.tellStatus "[\"${gid}\"]" 2>/dev/null \
            | jq -r '.result.status // ""')
        case ",${accepted}," in
            *",${status},"*)
                printf '%s' "${status}"
                return 0
                ;;
        esac
        sleep 1
        elapsed=$((elapsed + 1))
    done
    printf '%s' "${status}"
    return 1
}

wait_container_test() {
    local expression=$1 timeout=${2:-30} elapsed
    for elapsed in $(seq 1 "${timeout}"); do
        if docker exec "${CONTAINER}" sh -c "${expression}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

cleanup_gid() {
    local gid=${1:-}
    [ -n "${gid}" ] || return 0
    rpc aria2.forceRemove "[\"${gid}\"]" >/dev/null 2>&1 || true
    rpc aria2.removeDownloadResult "[\"${gid}\"]" >/dev/null 2>&1 || true
}

configure_setting() {
    local move=$1 remove=$2 filter=$3 empty=$4 repeat=$5 torrent=$6 paused=$7
    docker exec --user abc "${CONTAINER}" sed -i \
        -e "s/^move-task=.*/move-task=${move}/" \
        -e "s/^remove-task=.*/remove-task=${remove}/" \
        -e "s/^content-filter=.*/content-filter=${filter}/" \
        -e "s/^delete-empty-dir=.*/delete-empty-dir=${empty}/" \
        -e "s/^remove-repeat-task=.*/remove-repeat-task=${repeat}/" \
        -e "s/^handle-torrent=.*/handle-torrent=${torrent}/" \
        -e "s/^move-paused-task=.*/move-paused-task=${paused}/" \
        /config/setting.conf
}

set_filter_conf() {
    docker exec --user abc "${CONTAINER}" sh -c \
        'printf "%s\n" "$1" > /config/文件过滤.conf' sh "$1"
}

reset_fixture_paths() {
    docker exec --user abc "${CONTAINER}" sh -c '
        rm -rf \
            /downloads/fixture-task \
            /downloads/completed/fixture-task \
            /downloads/recycle/fixture-task
        find /downloads -maxdepth 1 -type f -name "*.torrent" -delete
    '
}

prepare_complete_fixture() {
    reset_fixture_paths || return 1
    docker exec --user abc "${CONTAINER}" sh -c '
        mkdir -p /downloads/fixture-task
        printf "KEEP\n" > /downloads/fixture-task/keep.mp4
        printf "REMOVE\n" > /downloads/fixture-task/remove.txt
    '
}

add_fixture_torrent() {
    local options=$1 params
    params=$(jq -nc \
        --arg torrent "${TORRENT_B64}" \
        --argjson options "${options}" \
        '[$torrent, [], $options]')
    rpc aria2.addTorrent "${params}" | jq -r '.result // empty'
}

expected_abc_owner() {
    docker exec "${CONTAINER}" sh -c \
        'printf "%s:%s" "$(id -u abc)" "$(id -g abc)"'
}

t_runtime_identity_and_config() {
    hdr "1. 实际进程身份与初始化配置"
    local abc_uid aria2_pid aria2_uid
    abc_uid=$(docker exec "${CONTAINER}" id -u abc)
    aria2_pid=$(docker exec "${CONTAINER}" pgrep -x aria2c)
    aria2_uid=$(docker exec "${CONTAINER}" stat -c %u "/proc/${aria2_pid}")

    if [ "${aria2_uid}" = "${abc_uid}" ] \
        && docker exec "${CONTAINER}" grep -Fxq 'file-allocation=falloc' /config/aria2.conf \
        && docker exec "${CONTAINER}" grep -Fxq 'bt-save-metadata=true' /config/aria2.conf \
        && docker exec "${CONTAINER}" grep -Fxq 'on-download-complete=/aria2/scripts/completed.sh' /config/aria2.conf \
        && docker exec --user abc "${CONTAINER}" test -w /config/setting.conf \
        && docker exec --user abc "${CONTAINER}" test -w /downloads; then
        ok "aria2c 以 abc 运行，正式配置和卷写权限有效"
    else
        ng "实际进程身份、配置或 abc 写权限异常"
    fi
}

t_http_complete_hook() {
    hdr "2. HTTP 单文件完成 → aria2 自动触发 completed.sh"
    local fname gid status owner expected_owner
    fname="runtime-http-${VARIANT}-$$.html"
    configure_setting true rmaria false true false retain false || {
        ng "无法写入真实 setting.conf"
        return
    }
    docker exec --user abc "${CONTAINER}" rm -rf \
        "/downloads/${fname}" "/downloads/completed/${fname}"

    gid=$(rpc aria2.addUri \
        "[[\"http://127.0.0.1:${WEBUI_PORT}/index.html\"],{\"out\":\"${fname}\"}]" \
        | jq -r '.result // empty')
    [ -n "${gid}" ] || {
        ng "HTTP 场景未获得 GID"
        return
    }

    status=$(wait_status "${gid}" complete 60)
    expected_owner=$(expected_abc_owner)
    if [ "${status}" = "complete" ] \
        && wait_container_test \
            "[ ! -e '/downloads/${fname}' ] && [ -s '/downloads/completed/${fname}' ]" \
        && owner=$(docker exec "${CONTAINER}" stat -c '%u:%g' \
            "/downloads/completed/${fname}") \
        && [ "${owner}" = "${expected_owner}" ]; then
        ok "真实下载、异步 hook、移动和 abc 所有权均正确"
    else
        ng "HTTP 下载完成 hook 场景异常（status=${status:-空}）"
    fi

    cleanup_gid "${gid}"
    docker exec --user abc "${CONTAINER}" rm -f "/downloads/completed/${fname}"
}

t_bt_filter_partial() {
    hdr "3. BT 多文件完成 → 过滤部分文件"
    local gid status owner expected_owner
    configure_setting true rmaria true true false retain false || {
        ng "无法启用真实文件过滤配置"
        return
    }
    set_filter_conf 'exclude-file=txt'
    prepare_complete_fixture || {
        ng "无法以 abc 准备完整 torrent 夹具"
        return
    }

    gid=$(add_fixture_torrent "${COMPLETE_OPTIONS}")
    [ -n "${gid}" ] || {
        ng "部分过滤场景未获得 GID"
        return
    }
    status=$(wait_status "${gid}" complete 60)
    expected_owner=$(expected_abc_owner)

    if [ "${status}" = "complete" ] \
        && wait_container_test \
            "[ ! -e /downloads/fixture-task ] \
             && [ -f /downloads/completed/fixture-task/keep.mp4 ] \
             && [ ! -e /downloads/completed/fixture-task/remove.txt ]" \
        && owner=$(docker exec "${CONTAINER}" stat -c '%u:%g' \
            /downloads/completed/fixture-task/keep.mp4) \
        && [ "${owner}" = "${expected_owner}" ]; then
        ok "真实 BT hook 只删除命中文件并移动剩余内容"
    else
        ng "真实 BT 部分过滤场景异常（status=${status:-空}）"
    fi
    cleanup_gid "${gid}"
}

t_bt_filter_all_guard() {
    hdr "4. BT 多文件全部命中 → 跳过整次过滤"
    local gid status warning_count
    configure_setting true rmaria true true false retain false || {
        ng "无法启用全部文件保护场景配置"
        return
    }
    set_filter_conf 'exclude-file=mp4|txt'
    prepare_complete_fixture || {
        ng "无法以 abc 重建完整 torrent 夹具"
        return
    }
    docker exec --user abc "${CONTAINER}" sh -c \
        ': > /config/logs/文件过滤日志.log'

    gid=$(add_fixture_torrent "${COMPLETE_OPTIONS}")
    [ -n "${gid}" ] || {
        ng "全部过滤保护场景未获得 GID"
        return
    }
    status=$(wait_status "${gid}" complete 60)

    if [ "${status}" = "complete" ] \
        && wait_container_test \
            "[ ! -e /downloads/fixture-task ] \
             && [ -f /downloads/completed/fixture-task/keep.mp4 ] \
             && [ -f /downloads/completed/fixture-task/remove.txt ]" \
        && warning_count=$(docker exec "${CONTAINER}" grep -Fc \
            '过滤规则会删除当前任务全部文件，已跳过本次文件过滤' \
            /config/logs/文件过滤日志.log) \
        && [ "${warning_count}" -eq 1 ]; then
        ok "正式 hook 保留全部文件，并准确记录一次保护警告"
    else
        ng "真实 BT 全部文件保护场景异常（status=${status:-空}）"
    fi
    cleanup_gid "${gid}"
}

t_bt_stop_recycle_hook() {
    hdr "5. 活动 BT 任务删除 → aria2 自动触发 stop.sh"
    local gid status
    configure_setting false recycle false true false retain false || {
        ng "无法启用真实回收站配置"
        return
    }
    reset_fixture_paths

    gid=$(add_fixture_torrent "${ACTIVE_OPTIONS}")
    [ -n "${gid}" ] || {
        ng "停止任务场景未获得 GID"
        return
    }
    status=$(wait_status "${gid}" active,waiting 30)

    if [ -z "${status}" ] \
        || ! wait_container_test \
            "[ -f /downloads/fixture-task/keep.mp4 ] \
             && [ -f /downloads/fixture-task/remove.txt ]" 15; then
        ng "停止前 aria2 未创建真实任务文件（status=${status:-空}）"
        cleanup_gid "${gid}"
        return
    fi

    if ! rpc aria2.forceRemove "[\"${gid}\"]" | jq -e '.result' >/dev/null; then
        ng "RPC 无法删除活动 BT 任务"
        cleanup_gid "${gid}"
        return
    fi

    if wait_container_test \
        "[ ! -e /downloads/fixture-task ] \
         && [ -f /downloads/recycle/fixture-task/keep.mp4 ] \
         && [ -f /downloads/recycle/fixture-task/remove.txt ] \
         && [ ! -e /downloads/fixture-task.aria2 ]" 30; then
        ok "真实 stop.sh 将活动任务移入回收站并清理控制文件"
    else
        ng "真实 BT 停止回收场景异常"
    fi
    rpc aria2.removeDownloadResult "[\"${gid}\"]" >/dev/null 2>&1 || true
}

t_existing_config_restart() {
    [ "${VARIANT}" = "standard" ] || return 0
    hdr "6. 已有精简配置 → 容器重启后升级并保留用户值"

    if ! docker exec --user abc "${CONTAINER}" sh -c \
        'printf "%s\n" \
            "# 模拟旧版精简配置" \
            "remove-task=recycle" \
            "move-task=dmof" \
            > /config/setting.conf'; then
        ng "无法准备旧版精简 setting.conf"
        return
    fi

    if ! docker restart "${CONTAINER}" >/dev/null || ! wait_rpc; then
        ng "已有配置场景重启后 RPC 未恢复"
        return
    fi

    if docker exec "${CONTAINER}" sh -c '
        test "$(grep -c "^remove-task=recycle$" /config/setting.conf)" -eq 1
        test "$(grep -c "^move-task=dmof$" /config/setting.conf)" -eq 1
        for key in \
            remove-task move-task content-filter delete-empty-dir \
            handle-torrent remove-repeat-task move-paused-task; do
            test "$(grep -c "^${key}=" /config/setting.conf)" -eq 1 || exit 1
        done
    ' && docker exec --user abc "${CONTAINER}" test -w /config/setting.conf; then
        ok "真实重启拾取完整模板、保留旧值且 abc 仍可写"
    else
        ng "setting.conf 真实重启升级结果异常"
    fi
}

if [ -z "${CONTAINER}" ]; then
    echo "缺少 container 参数，真实场景测试不能降级为纯 RPC 模式。" >&2
    exit 2
fi

log "RPC=${RPC_URL} variant=${VARIANT} container=${CONTAINER}"
if ! wait_rpc; then
    echo "无法连接运行中的 aria2 RPC: ${RPC_URL}" >&2
    exit 1
fi

t_runtime_identity_and_config
t_http_complete_hook
t_bt_filter_partial
t_bt_filter_all_guard
t_bt_stop_recycle_hook
t_existing_config_restart

reset_fixture_paths >/dev/null 2>&1 || true

printf '\n═════════════════════════════════\n'
printf '  RUNTIME SCENARIOS: PASS=%s FAIL=%s\n' "${PASS}" "${FAIL}"
if ((FAIL > 0)); then
    printf '  失败场景:\n'
    printf '    - %s\n' "${FAILED[@]}"
    exit $((FAIL > 255 ? 255 : FAIL))
fi
printf '  ✓ 所有真实容器场景通过\n'
