#!/usr/bin/env bash
# 一个入口：指定镜像和场景；每个场景使用自己的容器与匿名卷，按 TEST_JOBS 并行执行。
set -euo pipefail
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${1:-superng6/aria2:latest}
VARIANT=${2:-standard}
SELECT=${3:-all}
JOBS=${TEST_JOBS:-4}
case "${VARIANT}" in standard|a2b) ;; *) echo 'variant 必须为 standard 或 a2b' >&2; exit 2 ;; esac
[[ "${JOBS}" =~ ^[1-9][0-9]*$ ]] || { echo 'TEST_JOBS 必须为正整数' >&2; exit 2; }
LIB_CASES=(filter-rules filter-guard paths move-fallback torrent tracker banner config-failure config-crlf)
[ "${VARIANT}" != a2b ] || LIB_CASES+=(a2b-scheme)
RUNTIME_CASES=(identity http http-nested complex-bt magnet filter-partial filter-all selected single-bt
    cross-device move-failure repeat pause-move pause-disable pause-resume recycle delete recycle-failure
    stop-inactive reserved ownership-root ownership-custom config-upgrade hook-registration rpc-tls)
# 需要 root 观察 s6 服务的场景
ROOT_CASES=()
[ "${VARIANT}" != a2b ] || ROOT_CASES+=(a2b-restart)
# 先执行 "<场景>-prepare"，再重启容器，最后断言
RESTART_CASES=(config-upgrade hook-registration rpc-tls)
# 含固定等待的慢场景先启动，并行时总耗时由它们决定
SLOW_CASES=(pause-move pause-disable pause-resume config-upgrade hook-registration rpc-tls)
CASES=()
for c in "${LIB_CASES[@]}"; do CASES+=("lib:${c}"); done
CASES+=("${RUNTIME_CASES[@]}" "${ROOT_CASES[@]}")
if [ "${SELECT}" = --list ]; then printf '%s\n' "${CASES[@]}"; exit 0; fi
in_list() {
    local item=$1 candidate
    shift
    for candidate in "$@"; do [ "${candidate}" != "${item}" ] || return 0; done
    return 1
}
if [ "${SELECT}" != all ]; then
    in_list "${SELECT}" "${CASES[@]}" || { echo "未知场景: ${SELECT}" >&2; exit 2; }
    CASES=("${SELECT}")
fi
docker info >/dev/null || { echo 'Docker 不可用，未执行容器测试' >&2; exit 2; }
docker image inspect "${IMAGE}" >/dev/null || { echo "请先通过 build.sh 构建或拉取待测镜像: ${IMAGE}" >&2; exit 2; }
RUN_ID="aria2-test-$(date +%s)-$$"
LABEL="aria2-test-run=${RUN_ID}"
TLS_DIR=""
ARTIFACTS=${TEST_ARTIFACTS:-"${TMPDIR:-/tmp}/${RUN_ID}"}
mkdir -p "${ARTIFACTS}"
# 按标签清理本次运行的全部容器，中断时也不残留并行场景。
cleanup() {
    local -a pids
    mapfile -t pids < <(jobs -p)
    ((${#pids[@]} == 0)) || kill "${pids[@]}" 2>/dev/null || true
    docker ps -aq --filter "label=${LABEL}" | xargs -r docker rm -fv >/dev/null 2>&1 || true
    [ -z "${TLS_DIR}" ] || rm -rf -- "${TLS_DIR}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# rpc-tls 使用宿主临时生成的自签证书；放在诊断目录之外并在退出时删除，
# 私钥既不进仓库，也不会随 CI 失败诊断一起上传。
if in_list rpc-tls "${CASES[@]}"; then
    command -v openssl >/dev/null || { echo 'rpc-tls 场景需要宿主安装 openssl' >&2; exit 2; }
    TLS_DIR=$(mktemp -d)
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=127.0.0.1' \
        -keyout "${TLS_DIR}/key.pem" -out "${TLS_DIR}/cert.pem" >/dev/null 2>&1
    # 测试容器内由 abc 复制证书，需可读；mktemp 目录默认 700，docker cp 会保留该权限。
    chmod 755 "${TLS_DIR}"
    chmod 644 "${TLS_DIR}/key.pem" "${TLS_DIR}/cert.pem"
fi

diagnose() {
    local container=$1 destination=$2
    docker logs "${container}" > "${destination}/container.log" 2>&1 || true
    docker exec "${container}" sh -c 'ps -ef; cat /config/setting.conf; find /downloads -maxdepth 4 -ls' \
        > "${destination}/state.log" 2>&1 || true
    docker cp "${container}:/config/logs" "${destination}/logs" >/dev/null 2>&1 || true
}
wait_ready() {
    local container=$1 deadline=$((SECONDS + 60))
    while ((SECONDS < deadline)); do
        if docker exec "${container}" sh -c \
            'test -w /config/setting.conf && curl -fsS --max-time 2 http://127.0.0.1:8080/ >/dev/null'; then
            return 0
        fi
        sleep 1
    done
    return 1
}
scenario_args() {
    local name=$1
    case "${name}" in
        cross-device) printf '%s\n' --tmpfs '/downloads/completed:rw,size=32m' ;;
        ownership-root) printf '%s\n' -e PUID=0 -e PGID=0 ;;
        ownership-custom) printf '%s\n' -e PUID=1234 -e PGID=1234 ;;
    esac
}
run_case() {
    local name=$1 container=$2
    local -a env=(-e PORT=6800 -e SECRET=test-token)
    if [[ "${name}" == lib:* ]]; then
        docker exec --user abc "${env[@]}" "${container}" bash /tmp/tests/library.sh "${name#lib:}"
        return
    fi
    if in_list "${name}" "${ROOT_CASES[@]}"; then
        docker exec --user root "${container}" bash /tmp/tests/root.sh "${name}"
        return
    fi
    if in_list "${name}" "${RESTART_CASES[@]}"; then
        docker exec --user abc "${env[@]}" "${container}" bash /tmp/tests/runtime.sh "${name}-prepare" || return 1
        docker restart "${container}" >/dev/null || return 1
        wait_ready "${container}" || return 1
    fi
    case "${name}" in
        rpc-tls) env+=(-e RPC_URL=https://127.0.0.1:6800/jsonrpc) ;;
        ownership-root) env+=(-e EXPECT_UID=0 -e EXPECT_GID=0) ;;
        ownership-custom) env+=(-e EXPECT_UID=1234 -e EXPECT_GID=1234) ;;
    esac
    docker exec --user abc "${env[@]}" "${container}" bash /tmp/tests/runtime.sh "${name}"
}
start_container() {
    local name=$1 container=$2
    shift 2
    docker create "$@" "${IMAGE}" >/dev/null || return 1
    # 仅供 mutate.sh 在专用容器中注入错误；正常入口从待测镜像读取生产代码。
    if [ -n "${TEST_ROOTFS:-}" ]; then docker cp "${TEST_ROOTFS}/." "${container}:/" || return 1; fi
    docker cp "${TESTS}" "${container}:/tmp/tests" || return 1
    if [ "${name}" = rpc-tls ]; then docker cp "${TLS_DIR}" "${container}:/tmp/tests/tls" || return 1; fi
    docker start "${container}" >/dev/null
}
# 在后台子 shell 中运行一个场景；结果写入 result 文件，由主进程汇总。
run_scenario() {
    local name=$1 label=${1//:/-} container destination
    local -a args extra
    container="${RUN_ID}-${label}"
    destination="${ARTIFACTS}/${label}"
    mkdir -p "${destination}"
    rm -f "${destination}/result"
    args=(--name "${container}" --label "${LABEL}"
        -e SECRET=test-token -e UT=false -e RUT=false -e WEBUI=true -e QUIET=false)
    mapfile -t extra < <(scenario_args "${name}")
    args+=("${extra[@]}")
    [ -z "${TEST_PLATFORM:-}" ] || args+=(--platform "${TEST_PLATFORM}")
    if [ "${VARIANT}" = a2b ]; then
        args+=(-e A2B=true --cap-add NET_ADMIN)
        [ ! -d /lib/modules ] || args+=(-v /lib/modules:/lib/modules:ro)
    else
        args+=(-e A2B=false)
    fi
    if start_container "${name}" "${container}" "${args[@]}" > "${destination}/case.log" 2>&1 \
        && wait_ready "${container}" \
        && run_case "${name}" "${container}" >> "${destination}/case.log" 2>&1; then
        echo PASS > "${destination}/result"
        printf 'PASS %s\n' "${name}"
    else
        echo FAIL > "${destination}/result"
        diagnose "${container}" "${destination}"
        # 一次写出整段，避免并行场景的失败输出交错。
        printf 'FAIL %s（诊断: %s）\n%s\n' "${name}" "${destination}" \
            "$(cat "${destination}/case.log" 2>/dev/null)" >&2
    fi
    docker rm -fv "${container}" >/dev/null 2>&1 || true
}

DISPATCH=()
for c in "${SLOW_CASES[@]}"; do
    if in_list "${c}" "${CASES[@]}"; then DISPATCH+=("${c}"); fi
done
for c in "${CASES[@]}"; do
    if ! in_list "${c}" "${SLOW_CASES[@]}"; then DISPATCH+=("${c}"); fi
done
started=$SECONDS
running=0
for c in "${DISPATCH[@]}"; do
    if ((running >= JOBS)); then
        wait -n || true
        running=$((running - 1))
    fi
    run_scenario "${c}" &
    running=$((running + 1))
done
wait || true
failed=0
passed=0
for c in "${CASES[@]}"; do
    if [ "$(cat "${ARTIFACTS}/${c//:/-}/result" 2>/dev/null)" = PASS ]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fi
done
printf 'SCENARIOS: PASS=%s FAIL=%s（%s 秒，并行 %s）\n日志: %s\n' \
    "${passed}" "${failed}" "$((SECONDS - started))" "${JOBS}" "${ARTIFACTS}"
((failed == 0))
