#!/usr/bin/env bash
# 在专用容器注入五个明确错误，检查场景是否真的能发现它们。工作区代码不变。
set -euo pipefail
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${1:-superng6/aria2:dev-latest}
VARIANT=${2:-standard}
TEMP=$(mktemp -d)
ARTIFACTS=${TEST_ARTIFACTS:-"${TMPDIR:-/tmp}/aria2-mutations-$(date +%s)-$$"}
mkdir -p "${ARTIFACTS}"
printf '变异验证日志: %s\n' "${ARTIFACTS}"
trap 'rm -rf "${TEMP}"' EXIT
for mutation in reserved config-upgrade filter-all pause-disable http; do
    printf '\n验证原始镜像: %s\n' "${mutation}"
    TEST_ROOTFS="" TEST_ARTIFACTS="${ARTIFACTS}/baseline-${mutation}" bash "${TESTS}/run.sh" "${IMAGE}" "${VARIANT}" "${mutation}"
    overlay="${TEMP}/overlay-${mutation}"
    python3 - "${TESTS}/.." "${overlay}" "${mutation}" <<'PY'
from pathlib import Path
import sys
repo, overlay, mutation = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
changes = {
    'reserved': ('aria2/scripts/lib/files.sh', 'IS_TASK_SOURCE_PATH() {', 'IS_TASK_SOURCE_PATH() {\n    return 0'),
    'config-upgrade': ('aria2/scripts/lib/config.sh', 'SED_CONF() {', 'SED_CONF() {\n    cp /aria2/conf/setting.conf /config/setting.conf\n    return $?'),
    'filter-all': ('aria2/scripts/lib/filter.sh', 'if [ "${candidate_num}" -ge "${REAL_FILE_NUM}" ]; then', 'if false; then'),
    'pause-disable': ('aria2/scripts/pause.sh', '    # 等待期间关闭功能时，取消本次尚未执行的移动。\n    [ "${MPT}" = "true" ] || return 0', '    # mutation: 忽略等待期间关闭的开关'),
    'http': ('aria2/scripts/lib/event.sh', 'SOURCE_PATH="${FILE_PATH}"', 'SOURCE_PATH="$(dirname "${FILE_PATH}")"'),
}
relative, before, after = changes[mutation]
source = (repo / 'root' / relative).read_text()
if source.count(before) != 1:
    raise SystemExit(f'变异位置已改变，需人工更新: {mutation}')
target = overlay / relative
target.parent.mkdir(parents=True)
target.write_text(source.replace(before, after, 1))
target.chmod(0o755)
PY
    printf '注入错误: %s\n' "${mutation}"
    rc=0
    TEST_ROOTFS="${overlay}" TEST_ARTIFACTS="${ARTIFACTS}/mutant-${mutation}" \
        bash "${TESTS}/run.sh" "${IMAGE}" "${VARIANT}" "${mutation}" || rc=$?
    if [ "${rc}" -ne 1 ] \
        || ! grep -Fq "FAIL [${mutation}]" "${ARTIFACTS}/mutant-${mutation}/${mutation}/case.log"; then
        echo "变异未被有效断言捕获，或基础设施失败: ${mutation}" >&2
        exit 1
    fi
    printf 'CAUGHT %s\n' "${mutation}"
done
