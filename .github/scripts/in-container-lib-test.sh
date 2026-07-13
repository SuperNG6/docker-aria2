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

# 走真实 LOAD_FILTER_CONF + 配置文件，验证 ^key= 锚定根除前缀污染。
# include-file 是 include-file-regex 的前缀；若 grep 只锚 ^include-file，
# 两 key 同时启用时 INCLUDE_FILE 会吞进 regex 行的值（中间夹换行），拼进
# find -iregex 后正则破碎、include-file 过滤静默失效。
t_filter_prefix_conflict() {
    hdr "filter: include-file 与 include-file-regex 同存时前缀不互相污染"
    local conf="$LOG_DIR/文件过滤.conf"
    cat >"$conf" <<'EOF'
include-file=mp4|mkv
include-file-regex=^.*\.(mp4|mkv)$
EOF
    FILTER_CONF="$conf"
    reset_filter_vars
    LOAD_FILTER_CONF

    # INCLUDE_FILE 必须只有 mp4|mkv，不含换行、不含 regex 行的值
    if [[ "$INCLUDE_FILE" == "mp4|mkv" && "$INCLUDE_FILE" != *$'\n'* \
          && "$INCLUDE_FILE" != *"mp4$"* ]]; then
        ok "INCLUDE_FILE 未被 regex 行污染: '${INCLUDE_FILE}'"
    else
        ng "INCLUDE_FILE 被前缀污染: '${INCLUDE_FILE}'"
    fi
    # INCLUDE_FILE_REGEX 必须独立正确
    if [[ "$INCLUDE_FILE_REGEX" == '^.*\.(mp4|mkv)$' ]]; then
        ok "INCLUDE_FILE_REGEX 独立读取正确"
    else
        ng "INCLUDE_FILE_REGEX 异常: '${INCLUDE_FILE_REGEX}'"
    fi

    # 两个保留规则表达同一组目标，避免把交集语义误判成前缀污染
    local task
    task=$(make_multi_task fx-prefix video.mp4:1 demo.mkv:1 ad.html:1)
    SOURCE_PATH="$task"
    FILE_NUM=3
    DET=false
    # 重新 LOAD 让规则生效到 DELETE_EXCLUDE_FILE 读取的全局变量
    FILTER_CONF="$conf"
    reset_filter_vars
    LOAD_FILTER_CONF
    DELETE_EXCLUDE_FILE >/dev/null
    if [[ -f "$task/video.mp4" && -f "$task/demo.mkv" && ! -f "$task/ad.html" ]]; then
        ok "include-file 过滤在 regex 同存时仍正常工作"
    else
        ng "include-file 过滤被前缀污染破坏"
        ls -la "$task" >&2
    fi
    rm -f "$conf"
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

t_delete_guard_root() {
    hdr "delete: 拒绝删除根目录"
    local root sentinel failed=0
    for root in "$DOWNLOAD_PATH" "$DOWNLOAD_PATH/"; do
        sentinel="/downloads/__delete_guard_$RANDOM.txt"
        echo data > "$sentinel"
        SOURCE_PATH="$root"
        FILE_PATH="$sentinel"
        TARGET_PATH=""
        TASK_NAME=""
        FILE_NUM=10
        DELETE_FILE >/dev/null 2>&1
        if [[ -f "$sentinel" ]]; then
            :
        else
            failed=1
            ng "根目录删除守卫失效 root='$root'"
        fi
        rm -f "$sentinel"
    done
    [ "$failed" -eq 0 ] && ok "根目录删除均被拦截"
}

t_recycle_guard_root() {
    hdr "recycle: 拒绝移动根目录"
    local root sentinel failed=0
    for root in "$DOWNLOAD_PATH" "$DOWNLOAD_PATH/"; do
        sentinel="/downloads/__recycle_guard_$RANDOM.txt"
        echo data > "$sentinel"
        SOURCE_PATH="$root"
        FILE_PATH="$sentinel"
        TARGET_PATH="/downloads/recycle/root-guard"
        TASK_NAME=""
        FILE_NUM=10
        MOVE_RECYCLE >/dev/null 2>&1
        if [[ -f "$sentinel" ]]; then
            :
        else
            failed=1
            ng "根目录回收守卫失效 root='$root'"
        fi
        rm -f "$sentinel"
    done
    [ "$failed" -eq 0 ] && ok "根目录回收均被拦截"
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

t_rmaria_keep_main_file() {
    hdr "RMTASK=rmaria 默认值：仅清 .aria2，主文件原位保留"
    # stop.sh 的 case 在 rmaria 分支不调 MOVE_RECYCLE / DELETE_FILE，
    # 只走末尾的 CHECK_TORRENT + RM_ARIA2。这里直接模拟该分支的副作用。
    local task="$TEST_ROOT/rmaria-keep"
    mkdir -p "$task"
    echo payload > "$task/main.bin"
    touch "${task}.aria2"
    SOURCE_PATH="$task"
    TORRENT_FILE=""  # 非 BT 任务，CHECK_TORRENT 跳过
    CHECK_TORRENT
    RM_ARIA2 >/dev/null
    if [[ -f "$task/main.bin" && ! -e "${task}.aria2" ]]; then
        ok "主文件保留，.aria2 已清"
    else
        ng "rmaria 行为异常：main=$(ls -la "$task" 2>&1) aria2=$(ls "${task}.aria2" 2>&1)"
    fi
}

t_rmtask_unknown_keep_metadata() {
    hdr "RMTASK=未知值：不处理文件、.aria2 或种子"
    local task="$TEST_ROOT/rmtask-unknown"
    local torrent="$TEST_ROOT/rmtask-unknown.torrent"
    mkdir -p "$task"
    echo payload > "$task/main.bin"
    echo ctrl > "${task}.aria2"
    echo torrent > "$torrent"

    SOURCE_PATH="$task"
    FILE_PATH="$task/main.bin"
    TARGET_PATH=""
    TASK_NAME="rmtask-unknown"
    FILE_NUM=1
    RMTASK="unknown-mode"
    TOR="delete"
    TORRENT_FILE="$torrent"

    if ! declare -F HANDLE_STOP_TASK >/dev/null; then
        ng "HANDLE_STOP_TASK 未定义，无法复用 stop.sh 的 RMTASK 分流"
        return
    fi

    HANDLE_STOP_TASK >/dev/null
    if [[ -f "$task/main.bin" && -e "${task}.aria2" && -f "$torrent" ]]; then
        ok "未知 RMTASK 未触碰主文件、.aria2 和种子"
    else
        ng "未知 RMTASK 产生了副作用：main=$(test -f "$task/main.bin" && echo +||echo -) aria2=$(test -e "${task}.aria2" && echo +||echo -) torrent=$(test -f "$torrent" && echo +||echo -)"
    fi
}

# ─────────────────── 日志输出展示用例（无抑制 stdout，便于 docker logs / CI 日志肉眼检查） ───────────────────

t_log_demo_bulk_filter() {
    hdr "demo: 大批量过滤删除（CF=true）—— 完整展示 docker logs 中的输出格式"
    local task="$TEST_ROOT/log-demo-filter"
    rm -rf "$task"
    mkdir -p "$task/sub-empty" "$task/sub-keep"
    # 25 个 .txt（将被过滤删除）+ 5 个 .mp4（保留）+ 1 个嵌套 .txt
    local i
    for i in $(seq 1 25); do
        echo "junk-content-$i" > "$task/garbage-$i.txt"
    done
    for i in $(seq 1 5); do
        echo "video-bytes" > "$task/sub-keep/movie-$i.mp4"
    done
    echo "nested-junk" > "$task/sub-empty/leftover.txt"

    # CLEAN_UP 内部会调 LOAD_FILTER_CONF 从 ${FILTER_CONF} 读规则，
    # 直接 export EXCLUDE_FILE 会被它清掉——必须写到临时 FILTER_CONF 文件
    local tmp_filter_conf=/tmp/lib-test-filter.conf
    cat > "$tmp_filter_conf" <<'EOF'
exclude-file=txt
EOF
    FILTER_CONF="$tmp_filter_conf"

    SOURCE_PATH="$task"
    FILE_PATH="$task/sub-keep/movie-1.mp4"
    FILE_NUM=31
    CF=true
    DET=true
    : > "$CF_LOG"

    echo "    ─────────── ↓↓↓ 实际终端输出（含颜色）↓↓↓ ───────────"
    CLEAN_UP  # 跑完整链路：RM_ARIA2 + LOAD_FILTER_CONF + 过滤删除 + 空目录清理
    echo "    ─────────── ↑↑↑ 实际终端输出 结束 ↑↑↑ ───────────"

    # 行为断言：所有 .txt 被删，.mp4 保留，空子目录消失
    local txt_left mp4_left
    txt_left=$(find "$task" -name "*.txt" 2>/dev/null | wc -l)
    mp4_left=$(find "$task" -name "*.mp4" 2>/dev/null | wc -l)
    if [[ "$txt_left" -eq 0 && "$mp4_left" -eq 5 ]]; then
        ok "26 个 .txt 已过滤删除，5 个 .mp4 保留"
    else
        ng "过滤行为异常：txt_left=$txt_left mp4_left=$mp4_left"
    fi
    if [[ ! -d "$task/sub-empty" ]]; then
        ok "空子目录 sub-empty 已清理（DET=true）"
    else
        ng "DET 未生效，空目录残留"
    fi
    # CF_LOG 记录：rm -v 原生 `removed 'path'` 行数应 >= 26
    # 注意：grep -c 无匹配会输出 "0" 并返回 1；用 `|| true` 抑制 exit code
    # 不能用 `|| echo 0`，否则会把两次输出叠加成 "0\n0" 触发算术错误
    local rm_lines
    rm_lines=$(grep -c "^removed " "$CF_LOG" 2>/dev/null || true)
    rm_lines=${rm_lines:-0}
    if [[ "$rm_lines" -ge 26 ]]; then
        ok "filter.log 记录了 ${rm_lines} 行 removed 条目"
    else
        ng "filter.log 行数偏少：${rm_lines}"
        head -10 "$CF_LOG" >&2
    fi

    rm -f "$tmp_filter_conf"
}

t_log_demo_bulk_delete() {
    hdr "demo: 整任务删除（DELETE_FILE）—— 展示 TASK_INFO 横幅 + delete.log 格式"
    local task="$TEST_ROOT/log-demo-delete"
    rm -rf "$task"
    mkdir -p "$task/season-1"
    local i
    # 25 个文件分散在 2 个子目录里，模拟"大型 BT 任务被用户删除"
    for i in $(seq 1 15); do
        echo "episode-$i" > "$task/season-1/ep-$i.mkv"
    done
    for i in $(seq 1 10); do
        echo "extra-$i" > "$task/bonus-$i.bin"
    done

    SOURCE_PATH="$task"
    FILE_PATH="$task/season-1/ep-1.mkv"
    FILE_NUM=25
    TASK_TYPE=": 删除任务文件"
    DOWNLOAD_PATH=/downloads
    : > "$DELETE_LOG"

    echo "    ─────────── ↓↓↓ 实际终端输出（彩色 TASK_INFO + 删除行）↓↓↓ ───────────"
    DELETE_FILE  # 不抑制 stdout，CI artifact 中可肉眼看格式
    echo "    ─────────── ↑↑↑ 实际终端输出 结束 ↑↑↑ ───────────"

    if [[ ! -d "$task" ]]; then
        ok "整目录 25 文件已删除"
    else
        ng "DELETE_FILE 未删除"
    fi
    # delete.log 不能含 ANSI 码（彩色仅 stdout，日志文件必须纯文本）
    if ! grep -qF $'\033[' "$DELETE_LOG"; then
        ok "delete.log 无 ANSI 颜色码（cat 可读）"
    else
        ng "delete.log 含 ANSI 码"
        cat -A "$DELETE_LOG" | head -3 >&2
    fi
    if grep -qE '^[0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \[INFO\] 文件删除成功:' "$DELETE_LOG"; then
        ok "delete.log 格式正确（时间戳 + 级别 + 中文消息）"
    else
        ng "delete.log 格式异常"
        head -3 "$DELETE_LOG" >&2
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
    TOR="backup-rename"
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

t_path_download_root_rejected() {
    hdr "path: FILE_PATH 指向根目录时标记 error"
    local file_path failed=0
    for file_path in /downloads /downloads/; do
        reset_path_vars
        FILE_NUM=5
        FILE_PATH="$file_path"
        INFO_HASH=abc123def
        DOWNLOAD_DIR=/downloads
        GET_FINAL_PATH
        if [[ "$GET_PATH_INFO" == "error" ]]; then
            :
        else
            failed=1
            ng "未拒绝根目录 FILE_PATH=$file_path SOURCE=$SOURCE_PATH TARGET=$TARGET_PATH"
        fi
    done
    [ "$failed" -eq 0 ] && ok "根目录路径均标记为 error"
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

# ─────────────────── infoHash 解析用例（GET_INFO_HASH 三态语义） ───────────────────
#
# GET_INFO_HASH 返回码语义：0=BT 且 infoHash 有效 / 1=非 BT（infoHash=null）/ 2=解析失败
# 这里不 mock curl：GET_INFO_HASH 只解析 RPC_RESULT，不发 RPC。

t_infohash_bt_sets_torrent_file() {
    hdr "infoHash: BT 任务 → 返回 0，INFO_HASH 有效，TORRENT_FILE 指向 <dir>/<hash>.torrent"
    RPC_RESULT='{"jsonrpc":"2.0","id":"NG6","result":{"infoHash":"abc123def","dir":"/downloads"}}'
    DOWNLOAD_DIR=/downloads  # GET_INFO_HASH 拼 TORRENT_FILE 依赖此全局（由 GET_DOWNLOAD_DIR 设置）
    TORRENT_FILE=""
    local rc
    GET_INFO_HASH >/dev/null 2>&1
    rc=$?
    if [[ $rc -eq 0 \
        && "$INFO_HASH" == "abc123def" \
        && "$TORRENT_FILE" == "/downloads/abc123def.torrent" ]]; then
        ok "BT 任务：返回 0，TORRENT_FILE 推算正确"
    else
        ng "BT 任务异常: rc=$rc INFO_HASH=$INFO_HASH TORRENT_FILE=$TORRENT_FILE"
    fi
}

t_infohash_non_bt_returns_1() {
    hdr "infoHash: 非 BT（infoHash=null）→ 返回 1，TORRENT_FILE 不被设置"
    RPC_RESULT='{"jsonrpc":"2.0","id":"NG6","result":{"infoHash":null,"dir":"/downloads"}}'
    DOWNLOAD_DIR=/downloads
    TORRENT_FILE=""
    local rc
    GET_INFO_HASH >/dev/null 2>&1
    rc=$?
    if [[ $rc -eq 1 \
        && "$INFO_HASH" == "null" \
        && -z "$TORRENT_FILE" ]]; then
        ok "非 BT：返回 1，INFO_HASH=null，TORRENT_FILE 空（CHECK_TORRENT 将跳过）"
    else
        ng "非 BT 异常: rc=$rc INFO_HASH=$INFO_HASH TORRENT_FILE=$TORRENT_FILE"
    fi
}

# ─────────────────── 暂停移动延迟判定用例 ───────────────────

t_pause_mpt_waits_for_stable_pause() {
    hdr "pause: MPT 启动钩子后等待 30 秒，仅按任务状态决定是否移动"
    # pause.sh 的 source guard 使测试能直接调用 hook 主体；在子 shell mock 事件、RPC 和文件操作，避免影响后续用例。
    . /aria2/scripts/pause.sh
    local disabled_at_entry stays_paused resumed triggered_then_disabled rpc_unavailable

    disabled_at_entry=$(
        INIT_EVENT() { init_calls=$((init_calls + 1)); }
        init_calls=0 MPT=false
        RUN_PAUSE_HOOK disabled-task 1 /downloads/file >/dev/null
        printf '%s' "$init_calls"
    )

    stays_paused=$(
        INIT_EVENT() { TASK_GID="$2"; }
        GUARD_EVENT() { return 0; }
        sleep() { delay_seconds="$1"; }
        LOAD_CONF() { :; }
        GET_RPC_RESULT() { return 0; }
        GET_TASK_STATUS() { TASK_STATUS=paused; }
        MOVE_FILE() { move_calls=$((move_calls + 1)); }
        CHECK_TORRENT() { torrent_calls=$((torrent_calls + 1)); }
        move_calls=0 torrent_calls=0 delay_seconds=0
        MPT=true MOVE=false
        RUN_PAUSE_HOOK paused-task 1 /downloads/file >/dev/null
        printf '%s:%s:%s:%s' "$move_calls" "$torrent_calls" "$MOVE" "$delay_seconds"
    )
    resumed=$(
        INIT_EVENT() { TASK_GID="$2"; }
        GUARD_EVENT() { return 0; }
        sleep() { delay_seconds="$1"; }
        LOAD_CONF() { :; }
        GET_RPC_RESULT() { return 0; }
        GET_TASK_STATUS() { TASK_STATUS=active; }
        MOVE_FILE() { move_calls=$((move_calls + 1)); }
        CHECK_TORRENT() { torrent_calls=$((torrent_calls + 1)); }
        move_calls=0 torrent_calls=0 delay_seconds=0
        MPT=true MOVE=false
        RUN_PAUSE_HOOK filtered-task 1 /downloads/file >/dev/null
        printf '%s:%s:%s:%s' "$move_calls" "$torrent_calls" "$MOVE" "$delay_seconds"
    )
    # MPT 只决定是否启动本次钩子；启动后 LOAD_CONF 刷新后续配置，不取消已经发生的暂停事件。
    triggered_then_disabled=$(
        INIT_EVENT() { TASK_GID="$2"; }
        GUARD_EVENT() { return 0; }
        sleep() { delay_seconds="$1"; }
        LOAD_CONF() { MPT=false; }
        GET_RPC_RESULT() { return 0; }
        GET_TASK_STATUS() { TASK_STATUS=paused; }
        MOVE_FILE() { move_calls=$((move_calls + 1)); }
        CHECK_TORRENT() { torrent_calls=$((torrent_calls + 1)); }
        move_calls=0 torrent_calls=0 delay_seconds=0
        MPT=true MOVE=false
        RUN_PAUSE_HOOK disabled-task 1 /downloads/file >/dev/null
        printf '%s:%s:%s:%s' "$move_calls" "$torrent_calls" "$MOVE" "$delay_seconds"
    )
    rpc_unavailable=$(
        INIT_EVENT() { TASK_GID="$2"; }
        GUARD_EVENT() { return 0; }
        sleep() { delay_seconds="$1"; }
        LOAD_CONF() { :; }
        GET_RPC_RESULT() { return 1; }
        MOVE_FILE() { move_calls=$((move_calls + 1)); }
        CHECK_TORRENT() { torrent_calls=$((torrent_calls + 1)); }
        move_calls=0 torrent_calls=0 delay_seconds=0
        MPT=true MOVE=false
        RUN_PAUSE_HOOK unavailable-task 1 /downloads/file >/dev/null 2>&1
        printf '%s:%s:%s:%s' "$move_calls" "$torrent_calls" "$MOVE" "$delay_seconds"
    )

    if [[ "$disabled_at_entry" == "0" \
        && "$stays_paused" == "1:1:true:30" && "$resumed" == "0:0:false:30" \
        && "$triggered_then_disabled" == "1:1:true:30" && "$rpc_unavailable" == "0:0:false:30" ]]; then
        ok "MPT 关闭时不初始化；等待后仍暂停才移动；触发后关闭 MPT 不取消本次事件"
    else
        ng "暂停移动延迟分支异常：disabled-init=$disabled_at_entry paused=$stays_paused resumed=$resumed triggered-then-disabled=$triggered_then_disabled unavailable=$rpc_unavailable"
    fi
}

# ─────────────────── RRT 重复任务检测用例（start.sh 核心分支） ───────────────────
#
# start.sh 的 RRT 触发条件：RRT=true && completed 已有同名目录 && TASK_STATUS != error
# 满足时：删本地新下载、按 TOR 处理 .torrent、RPC 取消任务。
# 单测里没有真的 aria2 任务，只验证"条件分支 + rm 副作用"；RPC 取消由 aria2 上游保证。

t_rrt_triggered_deletes_local() {
    hdr "RRT: completed 已有同名 → 删本地新下载，保留 completed 旧副本"
    local task_name="rrt-dup-task"
    local src="/downloads/$task_name"
    local completed="/downloads/completed/$task_name"
    rm -rf "$src" "$completed"
    mkdir -p "$src" "$completed"
    echo "fresh-partial" > "$src/new.bin"
    echo "older-finished" > "$completed/old.bin"

    SOURCE_PATH="$src"
    COMPLETED_DIR="$completed"
    TASK_STATUS="active"
    RRT=true
    TORRENT_FILE=""  # 无种子缓存

    if [ "${RRT}" = "true" ] && [ -d "${COMPLETED_DIR}" ] && [ "${TASK_STATUS}" != "error" ]; then
        REMOVE_SOURCE_PATH
    fi

    if [[ ! -e "$src" && -f "$completed/old.bin" ]]; then
        ok "本地新下载已删，completed 旧副本完整保留"
    else
        ng "RRT 触发后状态异常：src 是否存在=$([[ -e $src ]] && echo yes || echo no)，旧副本是否完整=$([[ -f $completed/old.bin ]] && echo yes || echo no)"
    fi
    rm -rf "$completed"
}

t_rrt_skip_on_error_status() {
    hdr "RRT: TASK_STATUS=error → 跳过删除（保留部分下载供用户排查）"
    local task_name="rrt-err-task"
    local src="/downloads/$task_name"
    local completed="/downloads/completed/$task_name"
    rm -rf "$src" "$completed"
    mkdir -p "$src" "$completed"
    echo "broken-partial" > "$src/incomplete.bin"

    SOURCE_PATH="$src"
    COMPLETED_DIR="$completed"
    TASK_STATUS="error"
    RRT=true

    if [ "${RRT}" = "true" ] && [ -d "${COMPLETED_DIR}" ] && [ "${TASK_STATUS}" != "error" ]; then
        REMOVE_SOURCE_PATH
    fi

    if [[ -f "$src/incomplete.bin" ]]; then
        ok "error 状态保留部分下载文件（不删）"
    else
        ng "error 状态被错误删除"
    fi
    rm -rf "$src" "$completed"
}

t_rrt_skip_when_disabled() {
    hdr "RRT: RRT=false → 不检测、不删本地（即使有同名 completed）"
    local task_name="rrt-disabled-task"
    local src="/downloads/$task_name"
    local completed="/downloads/completed/$task_name"
    rm -rf "$src" "$completed"
    mkdir -p "$src" "$completed"
    echo "in-progress" > "$src/active.bin"

    SOURCE_PATH="$src"
    COMPLETED_DIR="$completed"
    TASK_STATUS="active"
    RRT=false

    if [ "${RRT}" = "true" ] && [ -d "${COMPLETED_DIR}" ] && [ "${TASK_STATUS}" != "error" ]; then
        REMOVE_SOURCE_PATH
    fi

    if [[ -f "$src/active.bin" ]]; then
        ok "RRT=false 时不触发删除"
    else
        ng "RRT 关闭却仍删了文件"
    fi
    rm -rf "$src" "$completed"
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
    SECRET="test"
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
t_filter_delete_empty_dir
t_filter_prefix_conflict

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
t_delete_guard_root
t_recycle_guard_root
t_rm_aria2
t_rmaria_keep_main_file
t_rmtask_unknown_keep_metadata

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
t_path_download_root_rejected
t_path_magnet_metadata

# infoHash 解析三态语义（GET_INFO_HASH）
t_infohash_bt_sets_torrent_file
t_infohash_non_bt_returns_1
t_pause_mpt_waits_for_stable_pause

# RRT 重复任务（start.sh 分支）
t_rrt_triggered_deletes_local
t_rrt_skip_on_error_status
t_rrt_skip_when_disabled

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

# F2: 默认 SECRET 警告
t_default_secret_warning
t_custom_secret_no_warning

# 日志输出展示（放最后，docker logs 里输出最显眼）
t_log_demo_bulk_filter
t_log_demo_bulk_delete

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
