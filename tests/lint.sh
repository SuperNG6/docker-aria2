#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
files=()
# 同时检查未提交的新文件，本地与 CI 使用同一发现规则。
while IFS= read -r -d '' file; do
    if head -n 1 "${file}" | grep -Eq '^#!/(usr/bin/env (ba)?sh|bin/(ba)?sh|usr/bin/with-contenv (ba)?sh)($| )'; then
        files+=("${file}")
    fi
done < <(find root tests -type f -print0)
files+=(build.sh)
for file in "${files[@]}"; do bash -n "${file}"; done
shellcheck --severity=warning -x "${files[@]}"
bash tests/self-test.sh
git diff --check
printf 'PASS: %s 个 Shell 文件逐个完成语法检查与 ShellCheck\n' "${#files[@]}"
