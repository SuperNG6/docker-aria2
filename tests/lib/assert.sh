#!/usr/bin/env bash
# 断言失败直接结束当前场景，避免后续成功命令覆盖失败状态。
die() { printf 'FAIL [%s] %s\n' "${CASE:-setup}" "$*" >&2; exit 1; }
assert() {
    local reason=$1
    shift
    "$@" || die "${reason}（命令: $*）"
}
equal() { [ "$1" = "$2" ] || die "$3：预期 <$1>，实际 <$2>"; }
absent() { [ ! -e "$1" ] || die "路径不应存在: $1"; }
same_file() { assert "文件内容应一致: $1 / $2" cmp -s "$1" "$2"; }

# 使用实际经过的时间；单次探测也必须有上限。
eventually() {
    local seconds=$1 reason=$2 deadline
    shift 2
    deadline=$((SECONDS + seconds))
    while :; do
        if "$@"; then return 0; fi
        ((SECONDS < deadline)) || die "等待超时: ${reason}"
        sleep 1
    done
}

# 否定的异步结果需要观察整个窗口，不能把刚开始尚未动作当作成功。
consistently() {
    local seconds=$1 reason=$2 deadline
    shift 2
    deadline=$((SECONDS + seconds))
    while :; do
        "$@" || die "观察期间不变量被破坏: ${reason}"
        ((SECONDS < deadline)) || return 0
        sleep 1
    done
}
