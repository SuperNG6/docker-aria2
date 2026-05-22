#!/usr/bin/env bash
# 文件过滤 / 文件移动 库单元测试（在容器内运行）
#
# 直接 source lib/{log,files,filter}.sh 并手动设置环境，调用 MOVE_FILE /
# DELETE_EXCLUDE_FILE / DELETE_FILE / MOVE_RECYCLE 等函数；用真实文件系统断言行为。
# 不经过 aria2，不依赖 RPC，可对 MOVE 各模式和过滤各规则做精细覆盖。
#
# 用法（宿主机侧）：
#   docker cp in-container-lib-test.sh <container>:/tmp/
#   docker exec <container> bash /tmp/in-container-lib-test.sh
#
# 退出码：0 全部通过；非零 = 失败用例数（最多 255）

set -o pipefail
# 不开 -u：被测库（log.sh#TASK_INFO 等）引用 FILE_PATH/TASK_TYPE 等隐式契约变量，
# 单元测试无法在每个用例穷举设置；改用 pipefail + 显式断言保障正确性。

PASS=0
FAIL=0
declare -a FAILED

ok()  { echo "  ✓ $*"; PASS=$((PASS + 1)); }
ng()  { echo "  ✗ $*"; FAIL=$((FAIL + 1)); FAILED+=("$*"); }
hdr() { echo; echo "──── $* ────"; }

LIB=/aria2/script/lib
TEST_ROOT=/downloads/__lib_test__
LOG_DIR=/tmp/lib-test-logs
mkdir -p "$LOG_DIR"

# log.sh 提供颜色常量 + DATE_TIME；后续库依赖它
# config.sh 不 source —— 它会自动调 LOAD_CONF 读取 setting.conf，干扰用例隔离
. "$LIB/log.sh"
. "$LIB/files.sh"
. "$LIB/filter.sh"

# 公共全局：files/filter 库读取的"全局基础路径"
DOWNLOAD_PATH=/downloads
CF_LOG="$LOG_DIR/filter.log"
MOVE_LOG="$LOG_DIR/move.log"
DELETE_LOG="$LOG_DIR/delete.log"
RECYCLE_LOG="$LOG_DIR/recycle.log"

# 每个过滤用例先重置 6 个规则变量，避免相互污染
reset_filter_vars() {
    MIN_SIZE=""
    INCLUDE_FILE=""
    EXCLUDE_FILE=""
    KEYWORD_FILE=""
    INCLUDE_FILE_REGEX=""
    EXCLUDE_FILE_REGEX=""
}

# make_multi_task <task-name> <file:size_kb> ...
# 在 TEST_ROOT 下创建一个多文件任务目录，echo 出绝对路径
make_multi_task() {
    local name="$1"
    shift
    local task="$TEST_ROOT/$name"
    rm -rf "$task"
    mkdir -p "$task"
    local spec fn size
    for spec in "$@"; do
        fn="${spec%%:*}"
        size="${spec##*:}"
        dd if=/dev/zero of="$task/$fn" bs=1024 count="$size" 2>/dev/null
    done
    echo "$task"
}

# ─────────────────── 过滤器用例 ───────────────────

t_filter_exclude_file() {
    hdr "filter: exclude-file=txt|jpg（按扩展名删除）"
    local task
    task=$(make_multi_task fx-excl \
        movie.mp4:2 cover.jpg:1 readme.txt:1 sub.srt:1)
    SOURCE_PATH="$task"
    FILE_NUM=4
    DET=false
    reset_filter_vars
    EXCLUDE_FILE="txt|jpg"
    DELETE_EXCLUDE_FILE >/dev/null
    if [[ -f "$task/movie.mp4" && -f "$task/sub.srt" \
        && ! -f "$task/cover.jpg" && ! -f "$task/readme.txt" ]]; then
        ok "txt/jpg 已删除, mp4/srt 保留"
    else
        ng "exclude-file 行为异常"
        ls -la "$task" >&2
    fi
}

t_filter_include_file() {
    hdr "filter: include-file=mp4|mkv（仅保留指定扩展名）"
    local task
    task=$(make_multi_task fx-incl \
        video.mp4:2 demo.mkv:1 ad.html:1 cover.jpg:1)
    SOURCE_PATH="$task"
    FILE_NUM=4
    DET=false
    reset_filter_vars
    INCLUDE_FILE="mp4|mkv"
    DELETE_EXCLUDE_FILE >/dev/null
    if [[ -f "$task/video.mp4" && -f "$task/demo.mkv" \
        && ! -f "$task/ad.html" && ! -f "$task/cover.jpg" ]]; then
        ok "非 mp4/mkv 已删除"
    else
        ng "include-file 行为异常"
        ls -la "$task" >&2
    fi
}

t_filter_keyword() {
    hdr "filter: keyword-file=广告|sample（按关键词删除，含 UTF-8）"
    local task
    task=$(make_multi_task fx-kw \
        movie.mp4:2 sample.mp4:1 广告片头.mp4:1)
    SOURCE_PATH="$task"
    FILE_NUM=3
    DET=false
    reset_filter_vars
    KEYWORD_FILE="广告|sample"
    DELETE_EXCLUDE_FILE >/dev/null
    if [[ -f "$task/movie.mp4" \
        && ! -f "$task/sample.mp4" && ! -f "$task/广告片头.mp4" ]]; then
        ok "含 sample/广告 关键词的文件已删除"
    else
        ng "keyword-file 行为异常"
        ls -la "$task" >&2
    fi
}

t_filter_min_size() {
    hdr "filter: min-size=5k（删除小于阈值的文件）"
    local task
    task=$(make_multi_task fx-min big.bin:10 small.bin:3 mid.bin:5)
    SOURCE_PATH="$task"
    FILE_NUM=3
    DET=false
    reset_filter_vars
    MIN_SIZE="5k"
    DELETE_EXCLUDE_FILE >/dev/null
    if [[ -f "$task/big.bin" && ! -f "$task/small.bin" ]]; then
        ok "<5KB 文件已删除 (big.bin 保留)"
    else
        ng "min-size 行为异常"
        ls -la "$task" >&2
    fi
}

t_filter_exclude_regex() {
    hdr "filter: exclude-file-regex（按正则删除，比特彗星 padding 文件示例）"
    # 文件名复刻 setting.conf 示例：_____padding_file_<n>_____（末尾带 _）
    local task
    task=$(make_multi_task fx-rex \
        movie.mp4:2 _____padding_file_0001_____:1 sub.srt:1)
    SOURCE_PATH="$task"
    FILE_NUM=3
    DET=false
    reset_filter_vars
    EXCLUDE_FILE_REGEX='(.*/)_+(padding)(_*)(file)(.*)(_+)'
    DELETE_EXCLUDE_FILE >/dev/null
    if [[ -f "$task/movie.mp4" && -f "$task/sub.srt" \
        && ! -f "$task/_____padding_file_0001_____" ]]; then
        ok "padding 文件已删除，其余保留"
    else
        ng "exclude-file-regex 行为异常"
        ls -la "$task" >&2
    fi
}

t_filter_skip_single_file() {
    hdr "filter: FILE_NUM=1 时跳过（防误删单文件任务）"
    local task
    task=$(make_multi_task fx-single only.txt:1)
    SOURCE_PATH="$task"
    FILE_NUM=1
    DET=false
    reset_filter_vars
    EXCLUDE_FILE="txt"
    DELETE_EXCLUDE_FILE >/dev/null
    if [[ -f "$task/only.txt" ]]; then
        ok "单文件任务被正确跳过"
    else
        ng "单文件任务被错误过滤"
    fi
}

t_filter_skip_root() {
    hdr "filter: SOURCE_PATH==DOWNLOAD_PATH 时跳过（防误删根目录）"
    # 在 /downloads 根放个哨兵文件，过滤器必须拒绝在根目录执行
    local sentinel=/downloads/__sentinel_$RANDOM.txt
    echo data > "$sentinel"
    SOURCE_PATH="$DOWNLOAD_PATH"
    FILE_NUM=10
    DET=false
    reset_filter_vars
    EXCLUDE_FILE="txt"
    DELETE_EXCLUDE_FILE >/dev/null 2>&1
    if [[ -f "$sentinel" ]]; then
        ok "对根目录的过滤已被安全跳过"
    else
        ng "过滤器在根目录执行了删除！"
    fi
    rm -f "$sentinel"
}

t_filter_delete_empty_dir() {
    hdr "filter: DET=true 删除过滤后的空目录"
    local task
    task=$(make_multi_task fx-det video.mp4:1 ad.html:1)
    mkdir -p "$task/empty-subdir"
    SOURCE_PATH="$task"
    FILE_NUM=2
    DET=true
    reset_filter_vars
    EXCLUDE_FILE="html"
    DELETE_EXCLUDE_FILE >/dev/null
    DELETE_EMPTY_DIR >/dev/null
    if [[ ! -d "$task/empty-subdir" ]]; then
        ok "空目录已被删除"
    else
        ng "DET=true 但空目录残留"
    fi
}

# ─────────────────── 移动用例 ───────────────────

t_move_false() {
    hdr "move: MOVE=false 不移动只清理 .aria2"
    rm -rf /downloads/completed
    local f="$TEST_ROOT/mv-false/file.txt"
    mkdir -p "$(dirname "$f")"
    echo data > "$f"
    SOURCE_PATH="$TEST_ROOT/mv-false"
    TARGET_PATH="/downloads/completed/__lib_test__"
    TASK_NAME="mv-false"
    FILE_NUM=1
    MOVE=false
    CF=false
    DOWNLOAD_DIR="$TEST_ROOT"
    MOVE_FILE
    if [[ -f "$f" && ! -d /downloads/completed/__lib_test__ ]]; then
        ok "MOVE=false 文件保留原位"
    else
        ng "MOVE=false 行为异常"
    fi
}

t_move_true_single() {
    hdr "move: MOVE=true 单文件任务"
    rm -rf /downloads/completed
    local f="$TEST_ROOT/mv-true.txt"
    mkdir -p "$TEST_ROOT"
    echo data > "$f"
    SOURCE_PATH="$f"
    TARGET_PATH="/downloads/completed/__lib_test__"
    TASK_NAME="mv-true"
    FILE_NUM=1
    MOVE=true
    CF=false
    DOWNLOAD_DIR="$TEST_ROOT"
    MOVE_FILE
    if [[ ! -f "$f" && -f /downloads/completed/__lib_test__/mv-true.txt ]]; then
        ok "MOVE=true 单文件已移动"
    else
        ng "MOVE=true 单文件移动失败"
        ls -la "$TEST_ROOT" /downloads/completed/__lib_test__ 2>&1 | head -20
    fi
}

t_move_true_dir() {
    hdr "move: MOVE=true 多文件目录（整目录搬移）"
    rm -rf /downloads/completed
    local task="$TEST_ROOT/mv-dir"
    mkdir -p "$task"
    echo a > "$task/a.mp4"
    echo b > "$task/b.mp4"
    SOURCE_PATH="$task"
    TARGET_PATH="/downloads/completed/__lib_test__"
    TASK_NAME="mv-dir"
    FILE_NUM=2
    MOVE=true
    CF=false
    DOWNLOAD_DIR="$TEST_ROOT"
    MOVE_FILE
    if [[ ! -d "$task" \
        && -f /downloads/completed/__lib_test__/mv-dir/a.mp4 \
        && -f /downloads/completed/__lib_test__/mv-dir/b.mp4 ]]; then
        ok "MOVE=true 整目录已搬到 completed"
    else
        ng "MOVE=true 目录移动失败"
        ls -la "$task" /downloads/completed/__lib_test__/mv-dir 2>&1 | head -20
    fi
}

t_move_dmof_root_single() {
    hdr "move: MOVE=dmof 根目录单文件不移动"
    rm -rf /downloads/completed
    local f=/downloads/mv-dmof-root.txt
    echo data > "$f"
    SOURCE_PATH="$f"
    TARGET_PATH="/downloads/completed"
    TASK_NAME="mv-dmof-root"
    FILE_NUM=1
    MOVE=dmof
    CF=false
    DOWNLOAD_DIR="$DOWNLOAD_PATH" # 根目录
    MOVE_FILE
    if [[ -f "$f" && ! -d /downloads/completed ]]; then
        ok "dmof 模式：根目录单文件保留"
    else
        ng "dmof 模式行为异常"
    fi
    rm -f "$f"
}

t_move_dmof_subdir_single() {
    hdr "move: MOVE=dmof 子目录单文件正常移动"
    rm -rf /downloads/completed
    local sub="$TEST_ROOT/sub"
    mkdir -p "$sub"
    local f="$sub/file.mp4"
    echo data > "$f"
    SOURCE_PATH="$f"
    TARGET_PATH="/downloads/completed/__lib_test__/sub"
    TASK_NAME="file"
    FILE_NUM=1
    MOVE=dmof
    CF=false
    DOWNLOAD_DIR="$sub" # 用户分类子目录
    MOVE_FILE
    if [[ ! -f "$f" && -f /downloads/completed/__lib_test__/sub/file.mp4 ]]; then
        ok "dmof 模式：子目录单文件已移动"
    else
        ng "dmof 子目录移动失败"
        ls -la /downloads/completed/__lib_test__/sub 2>&1 || true
    fi
}

t_move_unknown_mode() {
    hdr "move: MOVE=未知值 不做任何操作（向后兼容护栏）"
    rm -rf /downloads/completed
    local f="$TEST_ROOT/mv-unknown.txt"
    mkdir -p "$TEST_ROOT"
    echo data > "$f"
    SOURCE_PATH="$f"
    TARGET_PATH="/downloads/completed/__lib_test__"
    TASK_NAME="mv-unknown"
    FILE_NUM=1
    MOVE=futuremode
    CF=false
    DOWNLOAD_DIR="$TEST_ROOT"
    MOVE_FILE
    if [[ -f "$f" && ! -d /downloads/completed ]]; then
        ok "未知 MOVE 值被安全忽略"
    else
        ng "未知 MOVE 值产生了文件操作"
    fi
}

# ─────────────────── 删除 / 回收站用例 ───────────────────

t_delete_file() {
    hdr "delete: DELETE_FILE 彻底删除任务"
    local task="$TEST_ROOT/del"
    mkdir -p "$task"
    echo data > "$task/a.bin"
    SOURCE_PATH="$task"
    TARGET_PATH=""
    TASK_NAME="del"
    FILE_NUM=1
    DELETE_FILE >/dev/null
    if [[ ! -d "$task" ]]; then
        ok "DELETE_FILE 已删除目录"
    else
        ng "DELETE_FILE 未删除"
    fi
}

t_move_recycle() {
    hdr "recycle: MOVE_RECYCLE 移动到回收站"
    local task="$TEST_ROOT/rec"
    rm -rf /downloads/recycle
    mkdir -p "$task"
    echo data > "$task/a.bin"
    SOURCE_PATH="$task"
    TARGET_PATH="/downloads/recycle/__lib_test__"
    TASK_NAME="rec"
    FILE_NUM=1
    MOVE_RECYCLE >/dev/null
    if [[ ! -d "$task" \
        && -f /downloads/recycle/__lib_test__/rec/a.bin ]]; then
        ok "已移动到回收站"
    else
        ng "MOVE_RECYCLE 异常"
    fi
}

t_rm_aria2() {
    hdr "cleanup: RM_ARIA2 清理 .aria2 控制文件"
    local f="$TEST_ROOT/rmaria.bin"
    mkdir -p "$TEST_ROOT"
    echo data > "$f"
    echo ctrl > "${f}.aria2"
    SOURCE_PATH="$f"
    RM_ARIA2 >/dev/null
    if [[ -f "$f" && ! -f "${f}.aria2" ]]; then
        ok ".aria2 已删除，主文件保留"
    else
        ng "RM_ARIA2 行为异常"
    fi
}

# ─────────────────── 主流程 ───────────────────

echo "在容器内运行库单元测试 ..."
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"

# filter
t_filter_exclude_file
t_filter_include_file
t_filter_keyword
t_filter_min_size
t_filter_exclude_regex
t_filter_skip_single_file
t_filter_skip_root
t_filter_delete_empty_dir

# move
t_move_false
t_move_true_single
t_move_true_dir
t_move_dmof_root_single
t_move_dmof_subdir_single
t_move_unknown_mode

# delete / recycle / .aria2
t_delete_file
t_move_recycle
t_rm_aria2

# 清理
rm -rf "$TEST_ROOT" /downloads/completed /downloads/recycle

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
