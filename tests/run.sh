#!/usr/bin/env bash
# 一个入口：指定镜像和场景；每个场景使用自己的容器与匿名卷。
set -euo pipefail
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${1:-superng6/aria2:dev-latest}
VARIANT=${2:-standard}
SELECT=${3:-all}
case "${VARIANT}" in standard|a2b) ;; *) echo 'variant 必须为 standard 或 a2b' >&2; exit 2 ;; esac
LIB_CASES=(filter-rules filter-guard paths torrent tracker banner config-failure)
[ "${VARIANT}" != a2b ] || LIB_CASES+=(a2b-scheme)
RUNTIME_CASES=(identity http filter-partial filter-all selected single-bt cross-device move-failure repeat pause-move pause-disable pause-resume recycle delete recycle-failure reserved config-upgrade)
CASES=()
for c in "${LIB_CASES[@]}"; do CASES+=("lib:${c}"); done
CASES+=("${RUNTIME_CASES[@]}")
if [ "${SELECT}" = --list ]; then printf '%s\n' "${CASES[@]}"; exit 0; fi
if [ "${SELECT}" != all ]; then
    found=false
    for c in "${CASES[@]}"; do [ "${c}" != "${SELECT}" ] || found=true; done
    [ "${found}" = true ] || { echo "未知场景: ${SELECT}" >&2; exit 2; }
    CASES=("${SELECT}")
fi
docker info >/dev/null || { echo 'Docker 不可用，未执行容器测试' >&2; exit 2; }
docker image inspect "${IMAGE}" >/dev/null || { echo "请先通过 build.sh 构建或拉取待测镜像: ${IMAGE}" >&2; exit 2; }
RUN_ID="aria2-test-$(date +%s)-$$"
ARTIFACTS=${TEST_ARTIFACTS:-"${TMPDIR:-/tmp}/${RUN_ID}"}
mkdir -p "${ARTIFACTS}"
CONTAINER=""
cleanup() {
    if [ -n "${CONTAINER}" ]; then docker rm -fv "${CONTAINER}" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
diagnose() {
    local destination=$1
    docker logs "${CONTAINER}" > "${destination}/container.log" 2>&1 || true
    docker exec "${CONTAINER}" sh -c 'ps -ef; cat /config/setting.conf; find /downloads -maxdepth 4 -ls' \
        > "${destination}/state.log" 2>&1 || true
    docker cp "${CONTAINER}:/config/logs" "${destination}/logs" >/dev/null 2>&1 || true
}
run_case() {
    local name=$1
    if [[ "${name}" == lib:* ]]; then
        docker exec --user abc -e PORT=6800 -e SECRET=test-token "${CONTAINER}" \
            bash /tmp/tests/library.sh "${name#lib:}"
    else
        if [ "${name}" = config-upgrade ]; then
            docker exec --user abc -e PORT=6800 -e SECRET=test-token "${CONTAINER}" \
                bash /tmp/tests/runtime.sh config-prepare || return 1
            docker restart "${CONTAINER}" >/dev/null || return 1
        fi
        docker exec --user abc -e PORT=6800 -e SECRET=test-token "${CONTAINER}" \
            bash /tmp/tests/runtime.sh "${name}"
    fi
}
failed=0
passed=0
for c in "${CASES[@]}"; do
    label=${c//:/-}
    CONTAINER="${RUN_ID}-${label}"
    destination="${ARTIFACTS}/${label}"
    mkdir -p "${destination}"
    args=(--name "${CONTAINER}" -e SECRET=test-token -e UT=false -e RUT=false -e WEBUI=true -e QUIET=false)
    [ "${c}" != cross-device ] || args+=(--tmpfs '/downloads/completed:rw,size=32m')
    [ -z "${TEST_PLATFORM:-}" ] || args+=(--platform "${TEST_PLATFORM}")
    if [ "${VARIANT}" = a2b ]; then
        args+=(-e A2B=true --cap-add NET_ADMIN)
        [ ! -d /lib/modules ] || args+=(-v /lib/modules:/lib/modules:ro)
    else
        args+=(-e A2B=false)
    fi
    docker create "${args[@]}" "${IMAGE}" >/dev/null
    # 仅供 mutate.sh 在专用容器中注入错误；正常入口从待测镜像读取生产代码。
    if [ -n "${TEST_ROOTFS:-}" ]; then docker cp "${TEST_ROOTFS}/." "${CONTAINER}:/"; fi
    docker cp "${TESTS}" "${CONTAINER}:/tmp/tests"
    docker start "${CONTAINER}" >/dev/null
    ready=false
    deadline=$((SECONDS + 60))
    while ((SECONDS < deadline)); do
        if docker exec "${CONTAINER}" sh -c \
            'test -w /config/setting.conf && curl -fsS --max-time 2 http://127.0.0.1:8080/ >/dev/null'; then
            ready=true
            break
        fi
        sleep 1
    done
    if [ "${ready}" = true ] && run_case "${c}" > "${destination}/case.log" 2>&1; then
        printf 'PASS %s\n' "${c}"
        passed=$((passed + 1))
    else
        printf 'FAIL %s（诊断: %s）\n' "${c}" "${destination}" >&2
        cat "${destination}/case.log" 2>/dev/null || true
        failed=$((failed + 1))
        diagnose "${destination}"
    fi
    cleanup
    CONTAINER=""
done
printf 'SCENARIOS: PASS=%s FAIL=%s\n日志: %s\n' "${passed}" "${failed}" "${ARTIFACTS}"
((failed == 0))
