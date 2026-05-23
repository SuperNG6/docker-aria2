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

LIB=/aria2/scripts/lib
TEST_ROOT=/downloads/__lib_test__
LOG_DIR=/tmp/lib-test-logs
mkdir -p "$LOG_DIR"

# log.sh 提供颜色常量 + DATE_TIME；后续库依赖它
# config.sh 不 source —— 它会自动调 LOAD_CONF 读取 setting.conf，干扰用例隔离
. "$LIB/log.sh"
. "$LIB/files.sh"
. "$LIB/filter.sh"
. "$LIB/torrent.sh"
. "$LIB/event.sh"   # 提供 GET_BASE_PATH / GET_FINAL_PATH / GET_TARGET_PATH
. "$LIB/tracker.sh" # source guard 让其不自动跑 main

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
    hdr "filter: min-size=5k（删除小于阈值的文件，含临界值断言）"
    local task
    task=$(make_multi_task fx-min big.bin:10 small.bin:3 mid.bin:5)
    SOURCE_PATH="$task"
    FILE_NUM=3
    DET=false
    reset_filter_vars
    MIN_SIZE="5k"
    DELETE_EXCLUDE_FILE >/dev/null
    # 加强断言：mid.bin (5KB) 必须保留——find -size -5k 是 strictly less than，恰好 5KB 不命中
    # 之前只断言 big/small 会让"误删 mid.bin"也通过
    if [[ -f "$task/big.bin" && ! -f "$task/small.bin" && -f "$task/mid.bin" ]]; then
        ok "<5KB 已删除，big/mid 保留（mid.bin 临界值不命中）"
    else
        ng "min-size 异常: big=$(test -f "$task/big.bin" && echo +||echo -) small=$(test -f "$task/small.bin" && echo +||echo -) mid=$(test -f "$task/mid.bin" && echo +||echo -)"
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
    hdr "filter: FILE_NUM=1 时跳过（防误删单文件任务，含日志负断言）"
    local task
    task=$(make_multi_task fx-single only.txt:1)
    SOURCE_PATH="$task"
    FILE_NUM=1
    DET=false
    reset_filter_vars
    EXCLUDE_FILE="txt"
    # 捕获输出做负断言：函数应当 silent return，不应打"删除不需要的文件"
    local out
    out=$(DELETE_EXCLUDE_FILE 2>&1)
    if [[ -f "$task/only.txt" ]] && ! echo "$out" | grep -q "删除不需要的文件"; then
        ok "单文件任务安静跳过（无误导日志）"
    else
        ng "单文件任务异常：file=$(test -f "$task/only.txt" && echo +||echo -) 输出='$out'"
    fi
}

t_filter_skip_root() {
    hdr "filter: SOURCE_PATH==DOWNLOAD_PATH 时跳过（防误删根目录，含日志负断言）"
    # 在 /downloads 根放个哨兵文件，过滤器必须拒绝在根目录执行
    local sentinel=/downloads/__sentinel_$RANDOM.txt
    echo data > "$sentinel"
    SOURCE_PATH="$DOWNLOAD_PATH"
    FILE_NUM=10
    DET=false
    reset_filter_vars
    EXCLUDE_FILE="txt"
    local out
    out=$(DELETE_EXCLUDE_FILE 2>&1)
    if [[ -f "$sentinel" ]] && ! echo "$out" | grep -q "删除不需要的文件"; then
        ok "根目录过滤安静跳过（无误导日志）"
    else
        ng "过滤器在根目录执行了删除或打了误导日志！sentinel=$(test -f "$sentinel" && echo +||echo -) 输出='$out'"
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
    FILE_PATH="$f"  # 模拟 aria2 传给钩子的"首个文件路径"，让 TASK_INFO 日志完整
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
    FILE_PATH="$f"  # 单文件任务：FILE_PATH 与 SOURCE_PATH 同值
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
    FILE_PATH="$task/a.mp4"  # 多文件任务：FILE_PATH 是第一个文件
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
    FILE_PATH="$f"
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
    FILE_PATH="$f"
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
    FILE_PATH="$f"
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
    FILE_PATH="$task/a.bin"
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
    FILE_PATH="$task/a.bin"
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

# ─────────────────── 种子文件处理用例 ───────────────────

# 准备一个 .torrent 文件，echo 出路径
_make_torrent() {
    local name="$1"
    local f="$TEST_ROOT/$name.torrent"
    mkdir -p "$TEST_ROOT" "$TEST_ROOT/backup"
    echo "fake-torrent-bytes" > "$f"
    echo "$f"
}

t_torrent_retain() {
    hdr "torrent: TOR=retain 保留种子原位"
    local tf
    tf=$(_make_torrent "abc")
    TORRENT_FILE="$tf"
    BAK_TORRENT_DIR="$TEST_ROOT/backup"
    DOWNLOAD_DIR="$TEST_ROOT"
    TASK_NAME="abc-task"
    TOR=retain
    HANDLE_TORRENT >/dev/null
    [[ -f "$tf" ]] && ok "retain 保留" || ng "retain 意外删除"
}

t_torrent_delete() {
    hdr "torrent: TOR=delete 直接删除种子"
    local tf
    tf=$(_make_torrent "abc")
    TORRENT_FILE="$tf"
    TOR=delete
    HANDLE_TORRENT >/dev/null
    [[ ! -f "$tf" ]] && ok "delete 删除种子" || ng "delete 未删除"
}

t_torrent_rename() {
    hdr "torrent: TOR=rename 重命名为任务名"
    local tf
    tf=$(_make_torrent "abc")
    TORRENT_FILE="$tf"
    DOWNLOAD_DIR="$TEST_ROOT"
    TASK_NAME="my-task"
    TOR=rename
    HANDLE_TORRENT >/dev/null
    if [[ ! -f "$tf" && -f "$TEST_ROOT/my-task.torrent" ]]; then
        ok "rename 完成"
    else
        ng "rename 失败"
        ls -la "$TEST_ROOT" 2>&1 | head -5 >&2
    fi
}

t_torrent_backup() {
    hdr "torrent: TOR=backup 原名移到备份目录"
    local tf
    tf=$(_make_torrent "abc")
    TORRENT_FILE="$tf"
    BAK_TORRENT_DIR="$TEST_ROOT/backup"
    TOR=backup
    HANDLE_TORRENT >/dev/null
    if [[ ! -f "$tf" && -f "$TEST_ROOT/backup/abc.torrent" ]]; then
        ok "backup 移到备份目录"
    else
        ng "backup 失败"
    fi
}

t_torrent_backup_rename() {
    hdr "torrent: TOR=backup-rename 重命名+备份"
    local tf
    tf=$(_make_torrent "abc")
    TORRENT_FILE="$tf"
    BAK_TORRENT_DIR="$TEST_ROOT/backup"
    TASK_NAME="my-task"
    TOR=backup-rename
    HANDLE_TORRENT >/dev/null
    if [[ ! -f "$tf" && -f "$TEST_ROOT/backup/my-task.torrent" ]]; then
        ok "backup-rename 重命名后备份"
    else
        ng "backup-rename 失败"
    fi
}

t_torrent_unknown() {
    hdr "torrent: TOR=未知值 保留原文件 + 打 WARNING（防静默吞错）"
    local tf
    tf=$(_make_torrent "abc")
    TORRENT_FILE="$tf"
    TOR=unknown_mode_xyz
    # 捕获 stderr 验证 WARNING 输出
    local err
    err=$(HANDLE_TORRENT 2>&1 >/dev/null)
    if [[ -f "$tf" ]] && echo "$err" | grep -q "WARNING"; then
        ok "未知值保留原文件 + 打了 WARNING（不会静默吞错）"
    else
        ng "未知值行为异常: file=$(test -f "$tf" && echo +||echo -) stderr='$err'"
    fi
}

# ─────────────────── 路径计算用例（GET_FINAL_PATH） ───────────────────

reset_path_vars() {
    unset SOURCE_PATH TARGET_PATH TASK_NAME COMPLETED_DIR GET_PATH_INFO RELATIVE_PATH
    DOWNLOAD_PATH=/downloads
    TARGET_DIR=/downloads/completed
}

t_path_http_single_root() {
    hdr "path: HTTP 单文件在 /downloads 根"
    reset_path_vars
    FILE_NUM=1
    FILE_PATH=/downloads/foo.txt
    INFO_HASH=null
    DOWNLOAD_DIR=/downloads
    GET_FINAL_PATH
    if [[ "$SOURCE_PATH" == "/downloads/foo.txt" \
        && "$TARGET_PATH" == "/downloads/completed" \
        && "$TASK_NAME" == "foo" ]]; then
        ok "SOURCE=文件，TARGET=completed 根"
    else
        ng "SOURCE=$SOURCE_PATH TARGET=$TARGET_PATH TASK=$TASK_NAME"
    fi
}

t_path_http_single_subdir() {
    hdr "path: HTTP 单文件在 dir=/downloads/sub"
    reset_path_vars
    FILE_NUM=1
    FILE_PATH=/downloads/sub/foo.txt
    INFO_HASH=null
    DOWNLOAD_DIR=/downloads/sub
    GET_FINAL_PATH
    if [[ "$SOURCE_PATH" == "/downloads/sub/foo.txt" \
        && "$TARGET_PATH" == "/downloads/completed/sub" ]]; then
        ok "保留 sub 层级"
    else
        ng "SOURCE=$SOURCE_PATH TARGET=$TARGET_PATH"
    fi
}

t_path_bt_single_root() {
    hdr "path: BT 单文件直接在 DOWNLOAD_DIR 根 → 按单文件处理"
    reset_path_vars
    FILE_NUM=1
    FILE_PATH=/downloads/foo.bin
    INFO_HASH=abc123def
    DOWNLOAD_DIR=/downloads
    GET_FINAL_PATH
    if [[ "$SOURCE_PATH" == "/downloads/foo.bin" ]]; then
        ok "SOURCE=文件本身（避免误整窝端走兄弟任务）"
    else
        ng "SOURCE=$SOURCE_PATH"
    fi
}

t_path_bt_single_subdir() {
    hdr "path: BT 单文件带文件夹 → 整目录搬"
    reset_path_vars
    FILE_NUM=1
    FILE_PATH=/downloads/torrent-folder/file.bin
    INFO_HASH=abc123def
    DOWNLOAD_DIR=/downloads
    GET_FINAL_PATH
    if [[ "$SOURCE_PATH" == "/downloads/torrent-folder" \
        && "$COMPLETED_DIR" == "/downloads/completed/torrent-folder" ]]; then
        ok "SOURCE=种子文件夹"
    else
        ng "SOURCE=$SOURCE_PATH COMPLETED_DIR=$COMPLETED_DIR"
    fi
}

t_path_bt_multi() {
    hdr "path: BT 多文件 → 整目录搬"
    reset_path_vars
    FILE_NUM=5
    FILE_PATH=/downloads/multi-task/sub/file1.bin
    INFO_HASH=abc123def
    DOWNLOAD_DIR=/downloads
    GET_FINAL_PATH
    if [[ "$SOURCE_PATH" == "/downloads/multi-task" ]]; then
        ok "SOURCE=任务根文件夹（不进 sub）"
    else
        ng "SOURCE=$SOURCE_PATH"
    fi
}

t_path_out_of_bounds() {
    hdr "path: SOURCE 越界（aria2 dir 指到 DOWNLOAD_PATH 外）"
    reset_path_vars
    FILE_NUM=5
    FILE_PATH=/elsewhere/task/file.bin
    INFO_HASH=abc123def
    DOWNLOAD_DIR=/elsewhere
    GET_FINAL_PATH
    if [[ "$GET_PATH_INFO" == "error" ]]; then
        ok "标记为 error（防越权操作）"
    else
        ng "未标记 error: GET_PATH_INFO=$GET_PATH_INFO SOURCE=$SOURCE_PATH"
    fi
}

t_path_magnet_metadata() {
    hdr "path: 磁力链元数据阶段（FILE_PATH 为空）→ 静默返回"
    reset_path_vars
    FILE_NUM=0
    FILE_PATH=""
    INFO_HASH=null
    DOWNLOAD_DIR=/downloads
    GET_FINAL_PATH
    if [[ -z "$SOURCE_PATH" ]]; then
        ok "FILE_PATH 空时不计算路径"
    else
        ng "意外算出 SOURCE=$SOURCE_PATH"
    fi
}

# ─────────────────── tracker.sh 用例 ───────────────────

t_tracker_file_write() {
    hdr "tracker: _update_file 写入 aria2.conf"
    local conf=/tmp/tracker-test.conf
    cat > "$conf" <<EOF
# test config
bt-tracker=
listen-port=6881
EOF
    TRACKER="udp://t1.example.com:1337,udp://t2.example.com:6969"
    _update_file "$conf" >/dev/null
    if grep -q "^bt-tracker=udp://t1.example.com:1337,udp://t2.example.com:6969$" "$conf"; then
        ok "tracker 列表已写入"
    else
        ng "tracker 写入失败"
        cat "$conf" >&2
    fi
    rm -f "$conf"
}

t_tracker_file_escape() {
    hdr "tracker: _update_file 转义特殊字符（&, query string）"
    local conf=/tmp/tracker-test.conf
    echo "bt-tracker=" > "$conf"
    TRACKER='udp://example.com/announce?key=a&b=c'
    _update_file "$conf" >/dev/null
    if grep -q 'bt-tracker=udp://example.com/announce?key=a&b=c' "$conf"; then
        ok "& 字符正确转义保留"
    else
        ng "& 字符转义异常"
        cat "$conf" >&2
    fi
    rm -f "$conf"
}

t_tracker_file_missing_line() {
    hdr "tracker: _update_file 在缺 bt-tracker= 行时自动追加"
    local conf=/tmp/tracker-test.conf
    echo "listen-port=6881" > "$conf"
    TRACKER="udp://t1.example.com:1337"
    _update_file "$conf" >/dev/null
    if grep -q "^bt-tracker=udp://t1.example.com:1337$" "$conf"; then
        ok "缺行时自动追加"
    else
        ng "未追加 bt-tracker 行"
    fi
    rm -f "$conf"
}

t_tracker_rpc_success_response() {
    hdr "tracker: _update_rpc 识别 .result==OK 为成功"
    # mock curl 返回成功响应
    curl() { echo '{"jsonrpc":"2.0","id":"NG6","result":"OK"}'; }
    export -f curl
    TRACKER="udp://t.example.com:1337"
    PORT=6800
    SECRET=test
    local out
    out=$(_update_rpc 2>&1)
    unset -f curl
    if echo "$out" | grep -q "更新成功"; then
        ok "OK 响应识别为成功"
    else
        ng "未识别成功响应"
        echo "$out" >&2
    fi
}

t_tracker_rpc_fake_ok() {
    hdr "tracker: _update_rpc 不被错误响应中的 OK 字样欺骗（B2 回归）"
    # 错误响应里恰好含 OK 字符串
    curl() { echo '{"jsonrpc":"2.0","id":"NG6","error":{"code":1,"message":"Token NOT OK"}}'; }
    export -f curl
    TRACKER="t"
    PORT=6800
    SECRET=wrong
    local out
    out=$(_update_rpc 2>&1)
    unset -f curl
    if echo "$out" | grep -q "RPC 接口错误"; then
        ok "正确识别 .result 缺失"
    else
        ng "被错误消息中的 OK 字样欺骗"
        echo "$out" >&2
    fi
}

t_tracker_main_file_e2e() {
    hdr "tracker: main file 模式端到端（GET_TRACKERS → ECHO → _update_file）"
    local conf=/tmp/tracker-main-test.conf
    echo "bt-tracker=" > "$conf"

    # 保存原函数定义，临时 override GET_TRACKERS 避免外网依赖
    local orig_get
    orig_get=$(declare -f GET_TRACKERS)
    GET_TRACKERS() { TRACKER="udp://e2e1.test:1337,udp://e2e2.test:6969"; }

    local out rc
    out=$(main file "$conf" 2>&1)
    rc=$?

    # 恢复原 GET_TRACKERS
    eval "$orig_get"

    if [[ $rc -eq 0 ]] \
        && grep -q "^bt-tracker=udp://e2e1.test:1337,udp://e2e2.test:6969$" "$conf" \
        && echo "$out" | grep -q "成功添加 BT trackers"; then
        ok "main file 端到端：完整流程跑通且写入了 bt-tracker 行"
    else
        ng "main file 异常: rc=$rc"
        grep "^bt-tracker" "$conf" >&2
        echo "$out" | tail -5 >&2
    fi
    rm -f "$conf"
}

t_tracker_main_rpc_e2e() {
    hdr "tracker: main rpc 模式端到端（GET_TRACKERS → ECHO → _update_rpc）"

    local orig_get
    orig_get=$(declare -f GET_TRACKERS)
    GET_TRACKERS() { TRACKER="udp://rpc-e2e.test:1337"; }
    # mock curl 返回 aria2 成功响应
    curl() { echo '{"jsonrpc":"2.0","id":"NG6","result":"OK"}'; }
    export -f curl
    PORT=6800
    SECRET=testtoken

    local out rc
    out=$(main rpc 2>&1)
    rc=$?

    unset -f curl
    eval "$orig_get"

    if [[ $rc -eq 0 ]] && echo "$out" | grep -q "BT trackers 更新成功"; then
        ok "main rpc 端到端：完整流程跑通且识别为成功"
    else
        ng "main rpc 异常: rc=$rc"
        echo "$out" | tail -10 >&2
    fi
}

t_tracker_ctu_dedup() {
    hdr "tracker: CTU 多源去重合并（含本地 file:// URL）"
    # 用本地 file:// URL 避免外网依赖（curl 默认支持 file://）
    echo "udp://a.example:1,udp://b.example:2" > /tmp/trk1.txt
    echo "udp://b.example:2,udp://c.example:3" > /tmp/trk2.txt

    export CTU="file:///tmp/trk1.txt,file:///tmp/trk2.txt"
    TRACKER=""
    GET_TRACKERS >/dev/null 2>&1
    local result="$TRACKER"

    unset CTU
    rm -f /tmp/trk1.txt /tmp/trk2.txt

    # 期望去重后 3 个 tracker：a/b/c（b 在两个文件都出现，应只保留一个）
    local count
    count=$(echo "$result" | tr ',' '\n' | sort -u | wc -l)
    if [[ "$count" == "3" ]] \
        && echo "$result" | grep -q "a.example:1" \
        && echo "$result" | grep -q "b.example:2" \
        && echo "$result" | grep -q "c.example:3"; then
        ok "CTU 多源合并去重正确：'$result'"
    else
        ng "CTU 合并异常 (count=$count): '$result'"
    fi
}

# ─────────────────── config.sh SED_CONF 用例 ───────────────────

t_sedconf_preserve_old_values() {
    hdr "config: SED_CONF 升级合并保留旧值"
    # 备份当前 /config/setting.conf
    local backup=/tmp/setting.conf.bak
    cp /config/setting.conf "$backup"

    # 注入"旧版用户修改过"的 setting.conf
    cat > /config/setting.conf <<'EOF'
# 旧版用户配置
remove-task=recycle
move-task=dmof
content-filter=true
delete-empty-dir=false
handle-torrent=backup
remove-repeat-task=false
move-paused-task=true
EOF
    # 重新 source config.sh 触发 LOAD_CONF
    SETTING_CONF=/config/setting.conf
    . "$LIB/config.sh"

    # 验证 LOAD_CONF 读到了旧值
    if [[ "$RMTASK" != "recycle" || "$MOVE" != "dmof" || "$CF" != "true" \
        || "$DET" != "false" || "$TOR" != "backup" || "$RRT" != "false" \
        || "$MPT" != "true" ]]; then
        ng "LOAD_CONF 读取旧值不全：RMTASK=$RMTASK MOVE=$MOVE CF=$CF DET=$DET TOR=$TOR RRT=$RRT MPT=$MPT"
        cp "$backup" /config/setting.conf
        return
    fi

    # SED_CONF 应该用新模板 + 旧值
    SED_CONF
    local fail=""
    grep -q "^remove-task=recycle$"     /config/setting.conf || fail+=" RMTASK"
    grep -q "^move-task=dmof$"          /config/setting.conf || fail+=" MOVE"
    grep -q "^content-filter=true$"     /config/setting.conf || fail+=" CF"
    grep -q "^delete-empty-dir=false$"  /config/setting.conf || fail+=" DET"
    grep -q "^handle-torrent=backup$"   /config/setting.conf || fail+=" TOR"
    grep -q "^remove-repeat-task=false$" /config/setting.conf || fail+=" RRT"
    grep -q "^move-paused-task=true$"   /config/setting.conf || fail+=" MPT"
    if [[ -z "$fail" ]]; then
        ok "7 个旧值全部保留到新模板"
    else
        ng "丢失旧值:$fail"
        cat /config/setting.conf >&2
    fi

    # 还原
    cp "$backup" /config/setting.conf
    rm -f "$backup"
}

# ─────────────────── F1: SEED_ENV_TO_SETTING_CONF 用例 ───────────────────

t_seed_env_set_values() {
    hdr "config: SEED_ENV_TO_SETTING_CONF env var 透传到首次 setting.conf"
    local backup=/tmp/setting.conf.bak
    cp /config/setting.conf "$backup"

    # 模拟首次启动：重置为内置默认模板
    cp /aria2/conf/setting.conf /config/setting.conf

    # 设环境变量（必须在 source config.sh 之前，让 snapshot 能捕获到）
    export MOVE=true
    export RMTASK=recycle
    export CF=true
    export TOR=delete

    SETTING_CONF=/config/setting.conf
    . "$LIB/config.sh"
    SEED_ENV_TO_SETTING_CONF

    local fail=""
    grep -q "^move-task=true$"        /config/setting.conf || fail+=" move-task"
    grep -q "^remove-task=recycle$"   /config/setting.conf || fail+=" remove-task"
    grep -q "^content-filter=true$"   /config/setting.conf || fail+=" content-filter"
    grep -q "^handle-torrent=delete$" /config/setting.conf || fail+=" handle-torrent"
    if [[ -z "$fail" ]]; then
        ok "4 个 env var 透传成功"
    else
        ng "透传失败:$fail"
        echo "  [debug] setting.conf 当前关键行：" >&2
        grep -E "^(move-task|remove-task|content-filter|handle-torrent)=" /config/setting.conf >&2
    fi

    unset MOVE RMTASK CF TOR
    cp "$backup" /config/setting.conf
    rm -f "$backup"
}

t_seed_env_skip_unset() {
    hdr "config: SEED 跳过未设的 env var（保留模板默认值）"
    local backup=/tmp/setting.conf.bak
    cp /config/setting.conf "$backup"
    cp /aria2/conf/setting.conf /config/setting.conf

    unset MOVE RMTASK CF DET TOR RRT MPT

    SETTING_CONF=/config/setting.conf
    . "$LIB/config.sh"
    SEED_ENV_TO_SETTING_CONF

    if diff -q /config/setting.conf /aria2/conf/setting.conf >/dev/null; then
        ok "未设 env var 时 setting.conf 与模板一致"
    else
        ng "未设 env var 时 setting.conf 被意外修改"
        diff /aria2/conf/setting.conf /config/setting.conf >&2
    fi

    cp "$backup" /config/setting.conf
    rm -f "$backup"
}

t_seed_env_escape_special() {
    hdr "config: SEED 转义含特殊字符的 env value（|, &, \\）"
    local backup=/tmp/setting.conf.bak
    cp /config/setting.conf "$backup"
    cp /aria2/conf/setting.conf /config/setting.conf

    # 用一个含 & 的值（aria2b 的几个 mode 都是简单字符串，但行为应当对任意字符串安全）
    export TOR='backup-rename'   # 真实合法值

    SETTING_CONF=/config/setting.conf
    . "$LIB/config.sh"
    SEED_ENV_TO_SETTING_CONF

    if grep -q "^handle-torrent=backup-rename$" /config/setting.conf; then
        ok "特殊字符值正确写入"
    else
        ng "值写入失败"
        cat /config/setting.conf >&2
    fi

    unset TOR
    cp "$backup" /config/setting.conf
    rm -f "$backup"
}

# ─────────────────── F2: 11-version 默认 SECRET 警告 ───────────────────

t_default_secret_warning() {
    hdr "11-version: SECRET=yourtoken 触发安全警告（F2 回归）"
    local out
    out=$(SECRET=yourtoken bash /etc/cont-init.d/11-version 2>&1)
    if echo "$out" | grep -q "yourtoken" && echo "$out" | grep -q "警告"; then
        ok "默认 token 触发警告"
    else
        ng "未触发警告或警告内容缺失"
        echo "$out" | tail -5 >&2
    fi
}

t_custom_secret_no_warning() {
    hdr "11-version: 自定义 SECRET 不打警告"
    local out
    out=$(SECRET=randomXYZ123 bash /etc/cont-init.d/11-version 2>&1)
    if ! echo "$out" | grep -q "警告"; then
        ok "自定义 token 不打警告"
    else
        ng "自定义 token 误打警告"
        echo "$out" | tail -5 >&2
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

# torrent
t_torrent_retain
t_torrent_delete
t_torrent_rename
t_torrent_backup
t_torrent_backup_rename
t_torrent_unknown

# path 计算
t_path_http_single_root
t_path_http_single_subdir
t_path_bt_single_root
t_path_bt_single_subdir
t_path_bt_multi
t_path_out_of_bounds
t_path_magnet_metadata

# tracker
t_tracker_file_write
t_tracker_file_escape
t_tracker_file_missing_line
t_tracker_rpc_success_response
t_tracker_rpc_fake_ok
t_tracker_main_file_e2e
t_tracker_main_rpc_e2e
t_tracker_ctu_dedup

# config 升级合并
t_sedconf_preserve_old_values

# F1: env var → setting.conf 种子值
t_seed_env_set_values
t_seed_env_skip_unset
t_seed_env_escape_special

# F2: 默认 SECRET 警告
t_default_secret_warning
t_custom_secret_no_warning

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
