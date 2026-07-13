#!/usr/bin/env bash
# Aria2 镜像集成测试：验证本项目写入的配置和下载完成钩子
# aria2 原生 RPC、磁力和 torrent 能力由上游保证，这里只覆盖本项目维护的行为。
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
rpc() {
    local method="$1" params="${2:-[]}"
    printf '%s' "$params" \
        | jq -nc --arg t "$TOKEN" --arg m "$method" \
            'input as $p | {jsonrpc:"2.0",id:"t",method:$m,params:([$t] + $p)}' \
        | curl -fsS --max-time 30 "$RPC_URL" \
            -H 'Content-Type: application/json' \
            --data-binary @-
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

# ─────────────────── 项目行为用例 ───────────────────

t_fa_default() {
    hdr "1. file-allocation 默认值（B1 回归：未设 FA 时应为 falloc）"
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

t_smd_default() {
    hdr "2. bt-save-metadata 默认值（SMD=true 默认 → aria2.conf 应为 true）"
    if [[ -z "$CONTAINER" ]]; then
        log "  ⚠ 未提供容器名，跳过"
        return
    fi
    local val
    val=$(docker exec "$CONTAINER" grep "^bt-save-metadata=" /config/aria2.conf | cut -d= -f2)
    if [[ "$val" == "true" ]]; then
        ok "bt-save-metadata=true"
    else
        ng "bt-save-metadata=$val（默认 SMD=true 期望写入 true）"
    fi
}

t_btport_default() {
    hdr "3. BTPORT 默认值（32516 同时写入 listen-port 与 dht-listen-port）"
    if [[ -z "$CONTAINER" ]]; then
        log "  ⚠ 未提供容器名，跳过"
        return
    fi
    local lp dp
    lp=$(docker exec "$CONTAINER" grep "^listen-port=" /config/aria2.conf | cut -d= -f2)
    dp=$(docker exec "$CONTAINER" grep "^dht-listen-port=" /config/aria2.conf | cut -d= -f2)
    if [[ "$lp" == "32516" && "$dp" == "32516" ]]; then
        ok "listen-port=32516 dht-listen-port=32516"
    else
        ng "端口值偏离期望：listen=$lp dht=$dp"
    fi
}

t_move_e2e() {
    hdr "4. MOVE 端到端 (move-task=true)"
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

    # MOVE_FILE 是后台异步执行（completed.sh 用 `MOVE_FILE &`）；
    # 用 poll 替代固定 sleep，避免误报（系统慢但最终成功的情况）
    local moved=0 elapsed
    for elapsed in $(seq 1 30); do
        if docker exec "$CONTAINER" sh -c "
            [ ! -f /downloads/$fname ] && [ -f /downloads/completed/$fname ]
        " 2>/dev/null; then
            moved=1
            break
        fi
        sleep 1
    done

    if [[ "$moved" == "1" ]]; then
        ok "/downloads/$fname → /downloads/completed/$fname（poll ${elapsed}s 内完成）"
    else
        ng "MOVE 未生效（poll 30s 超时）"
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

t_fa_default
t_smd_default
t_btport_default
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
