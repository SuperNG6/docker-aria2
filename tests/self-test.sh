#!/usr/bin/env bash
# 验证测试工具本身会拒绝错误，防止重新引入“断言失败后仍然 PASS”。
set -euo pipefail
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMP=$(mktemp -d)
trap 'rm -rf "${TEMP}"' EXIT
for expression in 'assert "应当失败" false' 'equal expected actual "值不一致"' \
    'same_file /missing-test-file-a /missing-test-file-b'; do
    rc=0
    bash -c '. "$1"; CASE=self; eval "$2"; echo ASSERTION_WAS_IGNORED' \
        bash "${TESTS}/lib/assert.sh" "${expression}" > "${TEMP}/output" 2>&1 || rc=$?
    if [ "${rc}" -ne 1 ] || grep -q ASSERTION_WAS_IGNORED "${TEMP}/output" \
        || ! grep -Fq 'FAIL [self]' "${TEMP}/output"; then
        cat "${TEMP}/output" >&2
        echo '断言未可靠终止场景' >&2
        exit 1
    fi
done
echo 'PASS: 错误断言会结束场景，不会被后续成功命令覆盖'
