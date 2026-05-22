#!/usr/bin/env bash
# Aria2 镜像集成测试：通过 JSON-RPC 提交各种形式的任务，验证镜像端到端行为
# 覆盖：getVersion / 全局选项 / HTTP 单源/多源/自定义参数 / pause-unpause / 查询接口
#       magnet / .torrent / purge / MOVE 端到端（编辑 setting.conf 后触发真实下载）
#
# 用法: rpc-integration-test.sh <host> <port> <secret> [container-name] [variant]
#   host:           RPC 主机
#   port:           映射到宿主机的 RPC 端口
#   secret:         RPC token（不带 token: 前缀）
#   container-name: 可选，提供后会做 MOVE 端到端测试（需要 docker exec 进容器改 setting.conf）
#   variant:        可选，仅作为日志标识（standard / a2b）
# 退出码：0 全部通过；非零 = 失败用例数（最多 255）

set -uo pipefail

HOST="${1:-127.0.0.1}"
PORT="${2:-6800}"
SECRET="${3:-smoketoken}"
CONTAINER="${4:-}"
VARIANT="${5:-standard}"
RPC_URL="http://${HOST}:${PORT}/jsonrpc"
TOKEN="token:${SECRET}"

PASS=0
FAIL=0
declare -a FAILED

ts()  { date '+%H:%M:%S'; }
log() { echo "[$(ts)] $*"; }
hdr() { echo; echo "──── $* ────"; }
ok()  { echo "  ✓ $*"; PASS=$((PASS + 1)); }
ng()  { echo "  ✗ $*"; FAIL=$((FAIL + 1)); FAILED+=("$*"); }

# rpc <method> <params-json-array>
# params 是 JSON 数组（不含 token），函数自动在头部插入 token 字段。
# 通过 stdin 把 params 传给 jq、把构造好的 body 传给 curl，绕开 Linux
# MAX_ARG_STRLEN (128KB) 单参数限制——.torrent 经 base64 后可达数百 KB。
rpc() {
    local method="$1" params="${2:-[]}"
    printf '%s' "$params" \
        | jq -nc --arg t "$TOKEN" --arg m "$method" \
            'input as $p | {jsonrpc:"2.0",id:"t",method:$m,params:([$t] + $p)}' \
        | curl -fsS --max-time 30 "$RPC_URL" \
            -H 'Content-Type: application/json' \
            --data-binary @-
}

# wait_status <gid> <expected> <timeout_s>：状态一致返回 0，否则在超时/错误时返回 1
# stdout 输出最后看到的状态（便于调用方诊断）
wait_status() {
    local gid="$1" expected="$2" timeout="${3:-30}" elapsed=0 s
    while ((elapsed < timeout)); do
        s=$(rpc aria2.tellStatus "[\"$gid\"]" 2>/dev/null | jq -r '.result.status // ""')
        [[ "$s" == "$expected" ]] && {
            echo "$s"
            return 0
        }
        [[ "$s" == "error" ]] && {
            echo "$s"
            return 1
        }
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "$s"
    return 1
}

# wait_final <gid> <timeout_s>：达到任何终止态（complete/error/removed）即返回 0
wait_final() {
    local gid="$1" timeout="${2:-60}" elapsed=0 s
    while ((elapsed < timeout)); do
        s=$(rpc aria2.tellStatus "[\"$gid\"]" 2>/dev/null | jq -r '.result.status // ""')
        case "$s" in
            complete | error | removed)
                echo "$s"
                return 0
                ;;
        esac
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "$s"
    return 1
}

# 静默清理 GID 留下的任务与结果记录
cleanup_gid() {
    local gid="$1"
    [[ -z "$gid" ]] && return 0
    rpc aria2.forceRemove "[\"$gid\"]" >/dev/null 2>&1 || true
    rpc aria2.removeDownloadResult "[\"$gid\"]" >/dev/null 2>&1 || true
}

# ─────────────────── 用例 ───────────────────

t_version() {
    hdr "1. aria2.getVersion"
    local v
    v=$(rpc aria2.getVersion '[]' | jq -r '.result.version // ""')
    [[ -n "$v" ]] && ok "version=$v" || ng "version 字段为空"
}

t_global_stat() {
    hdr "2. aria2.getGlobalStat"
    local r
    r=$(rpc aria2.getGlobalStat '[]')
    if echo "$r" | jq -e '.result.numActive' >/dev/null 2>&1; then
        ok "numActive=$(echo "$r" | jq -r '.result.numActive')"
    else
        ng "响应格式异常: $r"
    fi
}

t_change_global_option() {
    hdr "3. changeGlobalOption / getGlobalOption"
    rpc aria2.changeGlobalOption '[{"max-overall-download-limit":"512K"}]' >/dev/null
    local v
    v=$(rpc aria2.getGlobalOption '[]' | jq -r '.result["max-overall-download-limit"] // ""')
    [[ "$v" == "524288" ]] && ok "max-overall-download-limit=524288" \
        || ng "expected=524288 got=$v"
    rpc aria2.changeGlobalOption '[{"max-overall-download-limit":"0"}]' >/dev/null
}

t_http_single() {
    hdr "4. HTTP 单源 addUri"
    local url='https://raw.githubusercontent.com/aria2/aria2/master/README.rst'
    local gid
    gid=$(rpc aria2.addUri "[[\"$url\"]]" | jq -r '.result // ""')
    [[ -z "$gid" ]] && {
        ng "addUri 返回空 GID"
        return
    }
    ok "addUri → GID=$gid"
    local s
    s=$(wait_final "$gid" 60)
    [[ "$s" == "complete" ]] && ok "下载完成" || ng "未完成: status=$s"
    cleanup_gid "$gid"
}

t_http_multi() {
    hdr "5. HTTP 多源 addUri"
    local urls='["https://raw.githubusercontent.com/aria2/aria2/master/README.rst","https://raw.githubusercontent.com/aria2/aria2/master/README.rst"]'
    local gid
    gid=$(rpc aria2.addUri "[$urls,{\"out\":\"multi-src-readme\"}]" | jq -r '.result // ""')
    [[ -z "$gid" ]] && {
        ng "addUri (multi) 返回空 GID"
        return
    }
    ok "addUri (multi) → GID=$gid"
    local s
    s=$(wait_final "$gid" 60)
    [[ "$s" == "complete" ]] && ok "下载完成" || ng "未完成: status=$s"
    cleanup_gid "$gid"
}

t_http_options() {
    hdr "6. addUri with out/dir/header"
    local url='https://raw.githubusercontent.com/torvalds/linux/master/COPYING'
    local opts='{"out":"linux-copying.txt","dir":"/downloads","header":["User-Agent: aria2-smoke"]}'
    local gid
    gid=$(rpc aria2.addUri "[[\"$url\"],$opts]" | jq -r '.result // ""')
    [[ -z "$gid" ]] && {
        ng "addUri (options) 返回空 GID"
        return
    }
    ok "addUri (options) → GID=$gid"
    local s
    s=$(wait_final "$gid" 60)
    [[ "$s" == "complete" ]] && ok "下载完成" || ng "未完成: status=$s"
    cleanup_gid "$gid"
}

t_pause_unpause() {
    hdr "7. pause / unpause / remove"
    # 限速到 50K/s + 2MB 文件 ≈ 40s 持续期，确保 pause 介入时任务仍在传输
    rpc aria2.changeGlobalOption '[{"max-overall-download-limit":"50K"}]' >/dev/null
    local url='https://speed.cloudflare.com/__down?bytes=2097152'
    local gid
    gid=$(rpc aria2.addUri "[[\"$url\"]]" | jq -r '.result // ""')
    if [[ -z "$gid" ]]; then
        ng "addUri (pause-test) 返回空 GID"
        rpc aria2.changeGlobalOption '[{"max-overall-download-limit":"0"}]' >/dev/null
        return
    fi
    ok "addUri (2MB@50K) → GID=$gid"
    sleep 3
    rpc aria2.pause "[\"$gid\"]" >/dev/null
    local s
    s=$(wait_status "$gid" paused 10) || true
    [[ "$s" == "paused" ]] && ok "pause → status=paused" \
        || ng "pause expected=paused got=$s"
    rpc aria2.unpause "[\"$gid\"]" >/dev/null
    sleep 1
    s=$(rpc aria2.tellStatus "[\"$gid\"]" | jq -r '.result.status // ""')
    [[ "$s" == "active" || "$s" == "waiting" ]] && ok "unpause → status=$s" \
        || ng "unpause expected=active/waiting got=$s"
    rpc aria2.remove "[\"$gid\"]" >/dev/null 2>&1 || true
    cleanup_gid "$gid"
    # 恢复无限速
    rpc aria2.changeGlobalOption '[{"max-overall-download-limit":"0"}]' >/dev/null
}

t_query_lists() {
    hdr "8. tellActive / tellWaiting / tellStopped"
    rpc aria2.tellActive '[]' | jq -e '.result|type=="array"' >/dev/null \
        && ok "tellActive 数组" || ng "tellActive 非数组"
    rpc aria2.tellWaiting '[0,100]' | jq -e '.result|type=="array"' >/dev/null \
        && ok "tellWaiting 数组" || ng "tellWaiting 非数组"
    rpc aria2.tellStopped '[0,100]' | jq -e '.result|type=="array"' >/dev/null \
        && ok "tellStopped 数组" || ng "tellStopped 非数组"
}

t_magnet() {
    hdr "9. 磁力链 addUri (Big Buck Bunny — 公开测试种子)"
    # Big Buck Bunny 是常年用于测试的小型公共领域种子，做种者稳定
    local magnet='magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c'
    magnet+='&dn=Big+Buck+Bunny'
    magnet+='&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce'
    magnet+='&tr=udp%3A%2F%2Fopen.tracker.cl%3A1337%2Fannounce'
    local gid
    gid=$(rpc aria2.addUri "[[\"$magnet\"]]" | jq -r '.result // ""')
    [[ -z "$gid" ]] && {
        ng "addUri (magnet) 返回空 GID"
        return
    }
    ok "addUri (magnet) → GID=$gid"
    local s
    s=$(wait_status "$gid" active 60) \
        || s=$(rpc aria2.tellStatus "[\"$gid\"]" | jq -r '.result.status // ""')
    if [[ "$s" == "active" || "$s" == "complete" ]]; then
        ok "magnet 状态=$s（DHT/tracker 对等点查找已启动）"
    else
        ng "magnet 状态=$s（未进入 active）"
        rpc aria2.tellStatus "[\"$gid\"]" \
            | jq -r '.result | {status,errorCode,errorMessage,followedBy}' || true
    fi
    cleanup_gid "$gid"
}

t_torrent_file() {
    hdr "10. .torrent addTorrent (Ubuntu 24.04 LTS live-server)"
    local listing torrent_name tmp b64 gid s
    # 动态拿最新点版本，避免硬编码 URL 因点版本退役而 404
    listing=$(curl -fsSL --max-time 30 https://releases.ubuntu.com/24.04/ 2>/dev/null || true)
    torrent_name=$(echo "$listing" \
        | grep -oE 'ubuntu-24\.04\.[0-9]+-live-server-amd64\.iso\.torrent' \
        | head -1)
    if [[ -z "$torrent_name" ]]; then
        ng "无法获取 Ubuntu .torrent 列表（网络/上游问题）"
        return
    fi
    tmp=$(mktemp)
    if ! curl -fsSL --max-time 30 \
        "https://releases.ubuntu.com/24.04/${torrent_name}" -o "$tmp"; then
        ng ".torrent 下载失败"
        rm -f "$tmp"
        return
    fi
    ok "下载 .torrent → $torrent_name ($(wc -c < "$tmp") bytes)"
    b64=$(base64 -w0 "$tmp" 2>/dev/null || base64 < "$tmp" | tr -d '\n')
    gid=$(rpc aria2.addTorrent "[\"$b64\",[],{\"bt-stop-timeout\":\"5\"}]" \
        | jq -r '.result // ""')
    [[ -z "$gid" ]] && {
        ng "addTorrent 返回空 GID"
        rm -f "$tmp"
        return
    }
    ok "addTorrent → GID=$gid"
    s=$(wait_status "$gid" active 30) \
        || s=$(rpc aria2.tellStatus "[\"$gid\"]" | jq -r '.result.status // ""')
    [[ "$s" == "active" ]] && ok "torrent 状态=active" \
        || ng "torrent 状态=$s 未进入 active"
    cleanup_gid "$gid"
    rm -f "$tmp"
}

t_purge() {
    hdr "11. purgeDownloadResult"
    rpc aria2.purgeDownloadResult '[]' | jq -e '.result=="OK"' >/dev/null \
        && ok "purgeDownloadResult OK" || ng "purgeDownloadResult 失败"
}

t_fa_default() {
    hdr "12. file-allocation 默认值（B1 回归：未设 FA 时应为 falloc）"
    if [[ -z "$CONTAINER" ]]; then
        log "  ⚠ 未提供容器名，跳过"
        return
    fi
    local val
    val=$(docker exec "$CONTAINER" grep "^file-allocation=" /config/aria2.conf | cut -d= -f2)
    if [[ "$val" == "falloc" ]]; then
        ok "file-allocation=falloc"
    else
        ng "file-allocation=$val（B1 早期把 FA 未设时回退成 none）"
    fi
}

t_move_e2e() {
    hdr "13. MOVE 端到端 (move-task=true)"
    if [[ -z "$CONTAINER" ]]; then
        log "  ⚠ 未提供容器名，跳过 MOVE 端到端测试"
        return
    fi

    # 改 setting.conf 启用移动，并清掉 completed/ 残留
    if ! docker exec "$CONTAINER" sh -c "
        sed -i 's/^move-task=.*/move-task=true/' /config/setting.conf &&
        rm -rf /downloads/completed
    "; then
        ng "容器配置失败"
        return
    fi
    ok "容器内已启用 move-task=true"

    # 提交下载，文件名带随机后缀避免和其他用例撞车
    local fname="move-e2e-$$-$RANDOM.txt"
    local url='https://raw.githubusercontent.com/aria2/aria2/master/README.rst'
    local gid
    gid=$(rpc aria2.addUri "[[\"$url\"],{\"out\":\"$fname\"}]" | jq -r '.result // ""')
    if [[ -z "$gid" ]]; then
        ng "MOVE addUri 返空"
        return
    fi
    ok "addUri → GID=$gid out=$fname"

    local s
    s=$(wait_final "$gid" 60)
    if [[ "$s" != "complete" ]]; then
        ng "下载未完成: status=$s"
        cleanup_gid "$gid"
        return
    fi
    ok "下载完成"

    # MOVE_FILE 是后台 fork 执行（completed.sh 异步），给它点时间
    sleep 8

    if docker exec "$CONTAINER" sh -c "
        [ ! -f /downloads/$fname ] && [ -f /downloads/completed/$fname ]
    "; then
        ok "/downloads/$fname → /downloads/completed/$fname"
    else
        ng "MOVE 未生效"
        docker exec "$CONTAINER" sh -c "
            echo '--- /downloads ---'; ls -la /downloads/
            echo '--- /downloads/completed ---'; ls -la /downloads/completed/ 2>/dev/null || true
            echo '--- move.log ---'; tail -20 /config/logs/move.log 2>/dev/null || true
        " || true
    fi

    # 还原
    cleanup_gid "$gid"
    docker exec "$CONTAINER" sh -c "
        sed -i 's/^move-task=.*/move-task=false/' /config/setting.conf
        rm -rf /downloads/completed
    " || true
}

# ─────────────────── 主流程 ───────────────────

log "RPC: $RPC_URL  variant=$VARIANT  container=${CONTAINER:-<none>}"
if ! rpc aria2.getVersion '[]' | jq -e '.result.version' >/dev/null 2>&1; then
    echo "✗ 无法连接 RPC: $RPC_URL"
    exit 1
fi

t_version
t_global_stat
t_change_global_option
t_http_single
t_http_multi
t_http_options
t_pause_unpause
t_query_lists
t_magnet
t_torrent_file
t_purge
t_fa_default
t_move_e2e

echo
echo "═════════════════════════════════"
echo "  PASS=$PASS  FAIL=$FAIL"
if ((FAIL > 0)); then
    echo "  失败用例:"
    printf '    - %s\n' "${FAILED[@]}"
    exit $((FAIL > 255 ? 255 : FAIL))
fi
echo "  ✓ 全部通过"
exit 0
