#!/usr/bin/env bash
# 模拟验证 file_ops.sh 输出效果的测试脚本

set -e

# 创建模拟环境
TEST_DIR="/tmp/aria2_test_$(date +%s)"
mkdir -p "${TEST_DIR}"/{downloads,config/logs,config/backup-torrent}

# 设置环境变量
export DOWNLOAD_PATH="${TEST_DIR}/downloads"
export CONFIG_DIR="${TEST_DIR}/config"
export LOG_DIR="${CONFIG_DIR}/logs"
export FILTER_FILE="${CONFIG_DIR}/文件过滤.conf"
export CF_LOG="${LOG_DIR}/文件过滤日志.log"
export MOVE_LOG="${LOG_DIR}/move.log"
export DELETE_LOG="${LOG_DIR}/delete.log"
export RECYCLE_LOG="${LOG_DIR}/recycle.log"
export TORRENT_LOG="${LOG_DIR}/torrent.log"
export BAK_TORRENT_DIR="${CONFIG_DIR}/backup-torrent"

# 创建模拟的依赖库（简化版）
cat > "${TEST_DIR}/mock_logger.sh" << 'EOF'
#!/usr/bin/env bash
# 模拟 logger.sh
LOG_RED="\033[31m"
LOG_GREEN="\033[1;32m" 
LOG_YELLOW="\033[1;33m"
LOG_CYAN="\033[36m"
LOG_PURPLE="\033[1;35m"
LOG_BOLD="\033[1m"
LOG_NC="\033[0m"

INFO="[${LOG_GREEN}INFO${LOG_NC}]"
ERROR="[${LOG_RED}ERROR${LOG_NC}]"
WARN="[${LOG_YELLOW}WARN${LOG_NC}]"

now() { date +"%Y/%m/%d %H:%M:%S"; }

log_i() { echo -e "$(now) ${INFO} $*"; }
log_w() { echo -e "$(now) ${WARN} $*"; }
log_e() { echo -e "$(now) ${ERROR} $*"; }

log_i_tee() { local log_file="$1"; shift; echo -e "$(now) ${INFO} $*" | tee -a "${log_file}"; }
log_w_tee() { local log_file="$1"; shift; echo -e "$(now) ${WARN} $*" | tee -a "${log_file}"; }
log_e_tee() { local log_file="$1"; shift; echo -e "$(now) ${ERROR} $*" | tee -a "${log_file}"; }
EOF

cat > "${TEST_DIR}/mock_common.sh" << 'EOF'
#!/usr/bin/env bash
# 模拟 common.sh
. "${TEST_DIR}/mock_logger.sh"

panel() {
    local title="$1"
    shift || true
    echo -e "==============================================================================="
    echo -e "${title}"
    echo -e "==============================================================================="
    [[ "$#" -gt 0 ]] && echo -e "$*"
}

try_run() { "$@"; return $?; }

kv_get() {
    [[ -f "$1" ]] || return 1
    grep -E "^$2=" "${1}" | sed -E 's/^([^=]+)=//'
}

kv_set() {
    local f="$1" k="$2" v="$3"
    touch "${f}"
    if grep -qE "^${k}=" "${f}"; then
        sed -i.bak "s@^\(${k}=\).*@\\1${v}@" "${f}"
    else
        echo "${k}=${v}" >>"${f}"
    fi
}

check_space_before_move() {
    local sp="$1" td="$2"
    
    if [[ ! -e "${sp}" ]]; then
        log_e "源文件不存在: ${sp}"
        return 1
    fi
    
    mkdir -p "${td}" || {
        log_e "无法创建目标目录: ${td}"
        return 1
    }
    
    # 模拟跨磁盘检查（这里简化处理）
    log_i "检测为同磁盘移动，无需检查空间。"
    REQ_SPACE_BYTES=""
    AVAIL_SPACE_BYTES=""
    return 0
}
EOF

cat > "${TEST_DIR}/mock_path.sh" << 'EOF'
#!/usr/bin/env bash
# 模拟 path.sh
. "${TEST_DIR}/mock_common.sh"

get_base_paths() {
    DOWNLOAD_PATH="${DOWNLOAD_PATH:-/downloads}"
    CONFIG_DIR="${CONFIG_DIR:-/config}"
    LOG_DIR="${LOG_DIR:-${CONFIG_DIR}/logs}"
    SETTING_FILE="${SETTING_FILE:-${CONFIG_DIR}/setting.conf}"
    ARIA2_CONF="${ARIA2_CONF:-${CONFIG_DIR}/aria2.conf}"
    FILTER_FILE="${FILTER_FILE:-${CONFIG_DIR}/文件过滤.conf}"
    SESSION_FILE="${SESSION_FILE:-${CONFIG_DIR}/aria2.session}"
    DHT_FILE="${DHT_FILE:-${CONFIG_DIR}/dht.dat}"
    CF_LOG="${CF_LOG:-${LOG_DIR}/文件过滤日志.log}"
    MOVE_LOG="${MOVE_LOG:-${LOG_DIR}/move.log}"
    DELETE_LOG="${DELETE_LOG:-${LOG_DIR}/delete.log}"
    RECYCLE_LOG="${RECYCLE_LOG:-${LOG_DIR}/recycle.log}"
    TORRENT_LOG="${TORRENT_LOG:-${LOG_DIR}/torrent.log}"
    BAK_TORRENT_DIR="${BAK_TORRENT_DIR:-${CONFIG_DIR}/backup-torrent}"
}

get_base_paths
EOF

cat > "${TEST_DIR}/mock_torrent.sh" << 'EOF'
#!/usr/bin/env bash
# 模拟 torrent.sh
. "${TEST_DIR}/mock_common.sh"
. "${TEST_DIR}/mock_path.sh"

handle_torrent() {
    [[ -n "${TOR:-}" ]] || return 0
    [[ -n "${TORRENT_FILE:-}" ]] || return 0
    case "${TOR}" in
    retain)
        log_i_tee "${TORRENT_LOG}" "种子已保留: $(basename "${TORRENT_FILE}") -> ${SAVE_PATH:-unknown}"
        ;;
    delete)
        log_i "已删除种子文件: ${TORRENT_FILE}"
        rm -f "${TORRENT_FILE}"
        log_i_tee "${TORRENT_LOG}" "种子已删除: $(basename "${TORRENT_FILE}") -> ${SAVE_PATH:-unknown}"
        ;;
    rename)
        log_i "已重命名种子文件: ${TORRENT_FILE} -> ${TASK_NAME}.torrent"
        mv -f "${TORRENT_FILE}" "$(dirname "${TORRENT_FILE}")/${TASK_NAME}.torrent"
        log_i_tee "${TORRENT_LOG}" "种子已重命名: ${TASK_NAME}.torrent -> ${SAVE_PATH:-unknown}"
        ;;
    backup)
        log_i "备份种子文件: ${TORRENT_FILE}"
        mkdir -p "${BAK_TORRENT_DIR}" && mv -f "${TORRENT_FILE}" "${BAK_TORRENT_DIR}"
        log_i_tee "${TORRENT_LOG}" "种子已备份: $(basename "${TORRENT_FILE}") -> ${BAK_TORRENT_DIR}"
        ;;
    backup-rename)
        log_i "重命名并备份种子文件: ${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
        mkdir -p "${BAK_TORRENT_DIR}" && mv -f "${TORRENT_FILE}" "${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
        log_i_tee "${TORRENT_LOG}" "种子已重命名并备份: ${TASK_NAME}.torrent -> ${BAK_TORRENT_DIR}"
        ;;
    *)
        :
        ;;
    esac
}

check_torrent() { [[ -e "${TORRENT_FILE:-}" ]] && handle_torrent; }
EOF

# 创建修改版的 file_ops.sh（使用模拟的依赖）
cat > "${TEST_DIR}/file_ops_test.sh" << 'EOF'
#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2312
# 文件操作：删除.aria2、清理内容、移动/删除/回收站
# 测试版本：使用模拟的依赖库

if [[ -n "${_ARIA2_LIB_FILE_OPS_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_FILE_OPS_SH_LOADED=1

# 引入依赖库（使用模拟版本）
. "${TEST_DIR}/mock_common.sh"
. "${TEST_DIR}/mock_path.sh"
. "${TEST_DIR}/mock_torrent.sh"

# ==========================任务信息展示===============================
print_task_info() {
    echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${LOG_GREEN}${TASK_TYPE}${LOG_NC} ${LOG_YELLOW}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} ${DOWNLOAD_PATH}
${LOG_PURPLE}任务位置:${LOG_NC} ${SOURCE_PATH}
${LOG_PURPLE}首个文件位置:${LOG_NC} ${FILE_PATH}
${LOG_PURPLE}任务文件数量:${LOG_NC} ${FILE_NUM}
${LOG_PURPLE}移动至目标文件夹:${LOG_NC} ${TARGET_PATH}
------------------------------------------------------------------------------------------"
}

print_delete_info() {
    echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${LOG_RED}${TASK_TYPE}${LOG_NC} ${LOG_YELLOW}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} ${DOWNLOAD_PATH}
${LOG_PURPLE}任务位置:${LOG_NC} ${SOURCE_PATH}
${LOG_PURPLE}首个文件位置:${LOG_NC} ${FILE_PATH}
${LOG_PURPLE}任务文件数量:${LOG_NC} ${FILE_NUM}
------------------------------------------------------------------------------------------"
}

# =============================读取过滤配置=============================
_filter_load() {
    MIN_SIZE=$(kv_get "${FILTER_FILE}" min-size)
    INCLUDE_FILE=$(kv_get "${FILTER_FILE}" include-file)
    EXCLUDE_FILE=$(kv_get "${FILTER_FILE}" exclude-file)
    KEYWORD_FILE=$(kv_get "${FILTER_FILE}" keyword-file)
    INCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" include-file-regex)
    EXCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" exclude-file-regex)
}

# =============================删除不需要的文件=============================
_delete_exclude_file() {
    if [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]] && [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} || -n ${KEYWORD_FILE} || -n ${EXCLUDE_FILE_REGEX} || -n ${INCLUDE_FILE_REGEX} ]]; then
        log_i "删除不需要的文件..."
        # macOS兼容版本：使用简化的文件匹配方式
        [[ -n "${MIN_SIZE}" ]] && find "${SOURCE_PATH}" -type f -size -"${MIN_SIZE}" -print0 | xargs -0 rm -vf | tee -a "${CF_LOG}" 2>/dev/null || true
        
        # 删除排除的文件扩展名
        if [[ -n "${EXCLUDE_FILE}" ]]; then
            for ext in $(echo "${EXCLUDE_FILE}" | tr '|' ' '); do
                find "${SOURCE_PATH}" -type f -name "*.${ext}" -print0 | xargs -0 rm -vf 2>/dev/null | tee -a "${CF_LOG}" || true
            done
        fi
        
        # 删除包含关键词的文件
        if [[ -n "${KEYWORD_FILE}" ]]; then
            for keyword in $(echo "${KEYWORD_FILE}" | tr '|' ' '); do
                find "${SOURCE_PATH}" -type f -name "*${keyword}*" -print0 | xargs -0 rm -vf 2>/dev/null | tee -a "${CF_LOG}" || true
            done
        fi
        
        # 只保留指定扩展名的文件（删除其他文件）
        if [[ -n "${INCLUDE_FILE}" ]]; then
            # 创建临时文件列表保存要保留的文件
            local keep_files=$(mktemp)
            for ext in $(echo "${INCLUDE_FILE}" | tr '|' ' '); do
                find "${SOURCE_PATH}" -type f -name "*.${ext}" >> "${keep_files}"
            done
            
            # 删除不在保留列表中的文件
            find "${SOURCE_PATH}" -type f | while read -r file; do
                if ! grep -qF "${file}" "${keep_files}"; then
                    rm -vf "${file}" 2>/dev/null | tee -a "${CF_LOG}" || true
                fi
            done
            rm -f "${keep_files}"
        fi
    fi
}

# =============================删除.aria2文件=============================
rm_aria2() {
    if [[ -e "${SOURCE_PATH}.aria2" ]]; then
        rm -f "${SOURCE_PATH}.aria2"
        log_i "已删除文件: ${SOURCE_PATH}.aria2"
    fi
}

# =============================删除空文件夹=============================
delete_empty_dir() {
    if [[ "${DET}" = "true" ]]; then
        log_i "删除任务中空的文件夹 ..."
        find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
    fi
}

# =============================内容过滤=============================
clean_up() {
    rm_aria2
    if [[ "${CF}" = "true" ]] && [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]]; then
        log_i_tee "${CF_LOG}" "被过滤文件的任务路径: ${SOURCE_PATH}"
        _filter_load
        _delete_exclude_file
        delete_empty_dir
    fi
}

# =============================移动文件=============================
move_file() {
    if [[ "${MOVE}" = "false" ]]; then
        rm_aria2
        return 0
    elif [[ "${MOVE}" = "dmof" ]] && [[ "${DOWNLOAD_DIR}" = "${DOWNLOAD_PATH}" ]] && [[ ${FILE_NUM} -eq 1 ]]; then
        rm_aria2
        return 0
    elif [[ "${MOVE}" = "true" ]] || [[ "${MOVE}" = "dmof" ]]; then
        TASK_TYPE=": 移动任务文件"
        print_task_info
        clean_up
        log_i "开始移动该任务文件到: ${LOG_GREEN}${TARGET_PATH}${LOG_NC}"
        mkdir -p "${TARGET_PATH}"

        if ! check_space_before_move "${SOURCE_PATH}" "${TARGET_PATH}"; then
            if [[ -n "${REQ_SPACE_BYTES:-}" ]] && [[ -n "${AVAIL_SPACE_BYTES:-}" ]]; then
                local req_g avail_g
                req_g=$(awk "BEGIN {printf \"%.2f\", ${REQ_SPACE_BYTES}/1024/1024/1024}")
                avail_g=$(awk "BEGIN {printf \"%.2f\", ${AVAIL_SPACE_BYTES}/1024/1024/1024}")
                log_e_tee "${MOVE_LOG}" "目标磁盘空间不足，移动失败。所需空间:${req_g} GB, 可用空间:${avail_g} GB. 源:${SOURCE_PATH} -> 目标:${TARGET_PATH}"
            fi
            
            local FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
            log_w "尝试将任务移动到: ${FAIL_DIR}"
            mkdir -p "${FAIL_DIR}"
            mv -f "${SOURCE_PATH}" "${FAIL_DIR}"
            local MOVE_FAIL_EXIT_CODE=$?
            if [[ ${MOVE_FAIL_EXIT_CODE} -eq 0 ]]; then
                log_i_tee "${MOVE_LOG}" "因目标磁盘空间不足，已将文件移动至: ${SOURCE_PATH} -> ${FAIL_DIR}"
            else
                log_e_tee "${MOVE_LOG}" "移动到 ${FAIL_DIR} 依然失败: ${SOURCE_PATH}"
            fi
            return 1
        fi

        mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
        local MOVE_EXIT_CODE=$?
        if [[ ${MOVE_EXIT_CODE} -eq 0 ]]; then
            log_i_tee "${MOVE_LOG}" "已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}"
        else
            log_e_tee "${MOVE_LOG}" "文件移动失败: ${SOURCE_PATH}"
            
            local FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
            mkdir -p "${FAIL_DIR}"
            if [[ ! -e "${SOURCE_PATH}" ]]; then
                log_w_tee "${MOVE_LOG}" "源文件不存在，无法移动: ${SOURCE_PATH}"
            else
                mv -f "${SOURCE_PATH}" "${FAIL_DIR}"
                local MOVE_FAIL_EXIT_CODE=$?
                if [[ ${MOVE_FAIL_EXIT_CODE} -eq 0 ]]; then
                    log_i_tee "${MOVE_LOG}" "已将文件移动至: ${SOURCE_PATH} -> ${FAIL_DIR}"
                else
                    log_e_tee "${MOVE_LOG}" "移动到 ${FAIL_DIR} 依然失败: ${SOURCE_PATH}"
                fi
            fi
        fi
    fi
}

# =============================删除文件=============================
delete_file() {
    TASK_TYPE=": 删除任务文件"
    print_delete_info
    log_i "下载已停止，开始删除文件..."
    
    if [[ ${FILE_NUM} -gt 1 ]] && [[ -d "${SOURCE_PATH}" ]]; then
        log_i "删除文件夹中的所有文件:"
        find "${SOURCE_PATH}" -type f -print0 | while IFS= read -r -d '' file; do
            echo "removed '${file}'"
        done
    fi
    
    rm -rf "${SOURCE_PATH}"
    local DELETE_EXIT_CODE=$?
    if [[ ${DELETE_EXIT_CODE} -eq 0 ]]; then
        log_i "已删除文件: ${SOURCE_PATH}"
        log_i_tee "${DELETE_LOG}" "文件删除成功: ${SOURCE_PATH}"
    else
        log_e_tee "${DELETE_LOG}" "delete failed: ${SOURCE_PATH}"
    fi
    
    rm_aria2
}

# =============================回收站=============================
move_recycle() {
    TASK_TYPE=": 移动任务文件至回收站"
    print_task_info
    log_i "开始移动已下载的任务至回收站 ${LOG_GREEN}${TARGET_PATH}${LOG_NC}"
    mkdir -p "${TARGET_PATH}"
    mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
    local RECYCLE_EXIT_CODE=$?
    if [[ ${RECYCLE_EXIT_CODE} -eq 0 ]]; then
        log_i_tee "${RECYCLE_LOG}" "已移至回收站: ${SOURCE_PATH} -> ${TARGET_PATH}"
    else
        log_e "移动文件到回收站失败: ${SOURCE_PATH}"
        log_i "已删除文件: ${SOURCE_PATH}"
        rm -rf "${SOURCE_PATH}"
        log_e_tee "${RECYCLE_LOG}" "移动文件到回收站失败: ${SOURCE_PATH}"
    fi
}
EOF

echo "🧪 开始模拟验证 file_ops.sh 的输出效果..."
echo

# 创建过滤配置文件
cat > "${FILTER_FILE}" << 'EOF'
min-size=1M
exclude-file=tmp|log|txt
keyword-file=sample|test
include-file=mkv|mp4|avi
EOF

# 场景1：单文件移动任务
echo "📋 场景1: 单文件移动任务"
echo "=========================================="

# 创建模拟文件
SOURCE_FILE="${TEST_DIR}/downloads/movie.mkv"
echo "模拟电影文件内容" > "${SOURCE_FILE}"
echo "模拟控制文件" > "${SOURCE_FILE}.aria2"

# 设置环境变量
export DOWNLOAD_PATH="${TEST_DIR}/downloads"
export DOWNLOAD_DIR="${TEST_DIR}/downloads"
export SOURCE_PATH="${SOURCE_FILE}"
export FILE_PATH="${SOURCE_FILE}"
export FILE_NUM=1
export TARGET_PATH="${TEST_DIR}/downloads/completed"
export TASK_TYPE=": 移动任务文件"
export MOVE="true"
export CF="false"
export DET="false"

# 加载测试脚本
. "${TEST_DIR}/file_ops_test.sh"

echo "--- 执行移动操作 ---"
move_file
echo

# 场景2：多文件移动任务（带过滤）
echo "📋 场景2: 多文件移动任务（带过滤）"
echo "=========================================="

# 创建多文件任务目录
MULTI_DIR="${TEST_DIR}/downloads/Big.Movie.2024"
mkdir -p "${MULTI_DIR}"
echo "主要视频文件" > "${MULTI_DIR}/Big.Movie.2024.mkv"
echo "小文件" > "${MULTI_DIR}/readme.txt"
echo "日志文件" > "${MULTI_DIR}/debug.log"
echo "样本文件" > "${MULTI_DIR}/sample.mkv"
echo "控制文件" > "${MULTI_DIR}.aria2"

# 重新设置环境变量
export SOURCE_PATH="${MULTI_DIR}"
export FILE_PATH="${MULTI_DIR}/Big.Movie.2024.mkv"
export FILE_NUM=4
export TARGET_PATH="${TEST_DIR}/downloads/completed"
export CF="true"
export DET="true"

echo "--- 执行带过滤的移动操作 ---"
move_file
echo

# 场景3：删除任务
echo "📋 场景3: 删除任务"
echo "=========================================="

# 创建要删除的文件
DELETE_FILE="${TEST_DIR}/downloads/unwanted.zip"
echo "不需要的文件" > "${DELETE_FILE}"
echo "控制文件" > "${DELETE_FILE}.aria2"

export SOURCE_PATH="${DELETE_FILE}"
export FILE_PATH="${DELETE_FILE}"
export FILE_NUM=1

echo "--- 执行删除操作 ---"
delete_file
echo

# 场景4：回收站移动
echo "📋 场景4: 回收站移动"
echo "=========================================="

# 创建要回收的文件
RECYCLE_FILE="${TEST_DIR}/downloads/old.movie.avi"
echo "旧电影文件" > "${RECYCLE_FILE}"

export SOURCE_PATH="${RECYCLE_FILE}"
export FILE_PATH="${RECYCLE_FILE}"
export FILE_NUM=1
export TARGET_PATH="${TEST_DIR}/downloads/recycle"

echo "--- 执行回收站移动 ---"
move_recycle
echo

# 场景5：多文件删除（带文件列表）
echo "📋 场景5: 多文件删除（带文件列表）"
echo "=========================================="

# 创建多文件删除目录
DELETE_DIR="${TEST_DIR}/downloads/Failed.Download"
mkdir -p "${DELETE_DIR}/subdir"
echo "文件1" > "${DELETE_DIR}/file1.txt"
echo "文件2" > "${DELETE_DIR}/file2.mkv"
echo "文件3" > "${DELETE_DIR}/subdir/file3.mp4"

export SOURCE_PATH="${DELETE_DIR}"
export FILE_PATH="${DELETE_DIR}/file1.txt"
export FILE_NUM=3

echo "--- 执行多文件删除 ---"
delete_file
echo

# 展示日志内容
echo "📊 生成的日志文件内容："
echo "=========================================="

echo "📄 移动日志 (${MOVE_LOG}):"
if [[ -f "${MOVE_LOG}" ]]; then
    cat "${MOVE_LOG}"
else
    echo "（无移动日志）"
fi
echo

echo "📄 删除日志 (${DELETE_LOG}):"
if [[ -f "${DELETE_LOG}" ]]; then
    cat "${DELETE_LOG}"
else
    echo "（无删除日志）"
fi
echo

echo "📄 回收站日志 (${RECYCLE_LOG}):"
if [[ -f "${RECYCLE_LOG}" ]]; then
    cat "${RECYCLE_LOG}"
else
    echo "（无回收站日志）"
fi
echo

echo "📄 过滤日志 (${CF_LOG}):"
if [[ -f "${CF_LOG}" ]]; then
    cat "${CF_LOG}"
else
    echo "（无过滤日志）"
fi
echo

# 展示目录结构
echo "📁 最终目录结构："
echo "=========================================="
tree "${TEST_DIR}" 2>/dev/null || find "${TEST_DIR}" -print | sed 's|[^/]*/|- |g'

echo
echo "✅ 模拟验证完成！"
echo "💾 测试环境位于: ${TEST_DIR}"
echo "🗑️  如需清理，请运行: rm -rf ${TEST_DIR}"
EOF

chmod +x "${TEST_DIR}/test_file_ops_simulation.sh"
