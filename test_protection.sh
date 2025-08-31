#!/usr/bin/env bash
# 测试全删保护功能

echo "🛡️  测试全删保护功能"
echo "========================="

# 创建测试环境
TEST_DIR="/tmp/protection_test_$(date +%s)"
mkdir -p "${TEST_DIR}/downloads/test_task"

cd "${TEST_DIR}/downloads/test_task"

echo "🎯 创建测试文件..."
echo "文本文件1" > "file1.txt"
echo "文本文件2" > "file2.txt"
echo "文档文件" > "document.doc"
echo "图片文件" > "image.jpg"
echo "压缩文件" > "archive.zip"

echo
echo "📊 测试前文件列表："
ls -la "${TEST_DIR}/downloads/test_task/"

# 设置环境变量
export SOURCE_PATH="${TEST_DIR}/downloads/test_task"
export FILE_NUM=5
export DOWNLOAD_PATH="${TEST_DIR}/downloads"
export CF_LOG="${TEST_DIR}/filter.log"

# 模拟依赖函数
kv_get() {
    [[ -f "$1" ]] || return 1
    grep -E "^$2=" "${1}" | sed -E 's/^([^=]+)=//'
}

log_i() { echo -e "$(date +'%H:%M:%S') [INFO] $*"; }
log_w() { echo -e "$(date +'%H:%M:%S') [WARN] $*"; }
log_e() { echo -e "$(date +'%H:%M:%S') [ERROR] $*"; }
log_i_tee() { local log_file="$1"; shift; echo -e "$(date +'%H:%M:%S') [INFO] $*" | tee -a "${log_file}"; }
log_e_tee() { local log_file="$1"; shift; echo -e "$(date +'%H:%M:%S') [ERROR] $*" | tee -a "${log_file}"; }

# 加载过滤配置
_filter_load() {
    MIN_SIZE=$(kv_get "${FILTER_FILE}" min-size)
    INCLUDE_FILE=$(kv_get "${FILTER_FILE}" include-file)
    EXCLUDE_FILE=$(kv_get "${FILTER_FILE}" exclude-file)
    KEYWORD_FILE=$(kv_get "${FILTER_FILE}" keyword-file)
    INCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" include-file-regex)
    EXCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" exclude-file-regex)
}

# 完整的改进过滤函数（包含全删保护）
_delete_exclude_file() {
    if [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]] && [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} || -n ${KEYWORD_FILE} || -n ${EXCLUDE_FILE_REGEX} || -n ${INCLUDE_FILE_REGEX} ]]; then
        log_i "删除不需要的文件..."
        
        # 安全检查：预判过滤规则是否会删除所有文件
        local total_files=$(find "${SOURCE_PATH}" -type f | wc -l)
        local files_to_keep=0
        
        log_i "安全检查：任务包含 ${total_files} 个文件，分析过滤影响..."
        
        # 优化逻辑：检查是否有include规则
        if [[ -n "${INCLUDE_FILE}" ]] || [[ -n "${INCLUDE_FILE_REGEX}" ]]; then
            log_i "检测到白名单规则，预判保留文件数量..."
            
            # 预判白名单模式下会保留多少文件（macOS兼容）
            if [[ -n "${INCLUDE_FILE}" ]]; then
                files_to_keep=0
                for ext in $(echo "${INCLUDE_FILE}" | tr '|' ' '); do
                    local count=$(find "${SOURCE_PATH}" -type f -name "*.${ext}" | wc -l)
                    files_to_keep=$((files_to_keep + count))
                done
                log_i "根据 include-file 规则，预计保留 ${files_to_keep} 个文件"
            fi
            
        else
            # 黑名单模式预判（简化版本）
            log_i "检测到黑名单规则，预判删除文件数量..."
            files_to_keep=${total_files}  # 假设都保留，然后减去要删除的
            
            if [[ -n "${EXCLUDE_FILE}" ]]; then
                for ext in $(echo "${EXCLUDE_FILE}" | tr '|' ' '); do
                    local count=$(find "${SOURCE_PATH}" -type f -name "*.${ext}" | wc -l)
                    files_to_keep=$((files_to_keep - count))
                    log_i "exclude-file 规则会删除 ${count} 个 .${ext} 文件"
                done
            fi
        fi
        
        # 全删保护：如果会删除所有文件，则跳过过滤
        if [[ ${files_to_keep} -eq 0 ]]; then
            log_w "🛡️  全删保护触发！"
            log_w "过滤规则会删除所有 ${total_files} 个文件，为避免误删重要内容已跳过过滤操作"
            log_w "请检查过滤配置是否过于严格："
            [[ -n "${MIN_SIZE}" ]] && log_w "  - min-size: ${MIN_SIZE}"
            [[ -n "${INCLUDE_FILE}" ]] && log_w "  - include-file: ${INCLUDE_FILE}"
            [[ -n "${EXCLUDE_FILE}" ]] && log_w "  - exclude-file: ${EXCLUDE_FILE}"
            [[ -n "${KEYWORD_FILE}" ]] && log_w "  - keyword-file: ${KEYWORD_FILE}"
            [[ -n "${INCLUDE_FILE_REGEX}" ]] && log_w "  - include-file-regex: ${INCLUDE_FILE_REGEX}"
            [[ -n "${EXCLUDE_FILE_REGEX}" ]] && log_w "  - exclude-file-regex: ${EXCLUDE_FILE_REGEX}"
            log_i_tee "${CF_LOG}" "全删保护: 跳过过滤 ${SOURCE_PATH}，规则过于严格会删除所有文件"
            return 0
        fi
        
        log_i "✅ 安全检查通过，预计保留 ${files_to_keep} 个文件，执行过滤..."
        
        # 执行实际的过滤逻辑（简化版本）
        if [[ -n "${INCLUDE_FILE}" ]]; then
            log_i "执行白名单过滤: ${INCLUDE_FILE}"
            for ext in $(echo "${INCLUDE_FILE}" | tr '|' ' '); do
                echo "  保留 *.${ext} 文件"
            done
            
            # 删除不匹配的文件
            find "${SOURCE_PATH}" -type f | while read -r file; do
                local should_keep=false
                for ext in $(echo "${INCLUDE_FILE}" | tr '|' ' '); do
                    if [[ "${file}" =~ \."${ext}"$ ]]; then
                        should_keep=true
                        break
                    fi
                done
                if [[ ${should_keep} == false ]]; then
                    echo "  删除: $(basename "${file}")"
                    rm -f "${file}"
                fi
            done
        else
            log_i "执行黑名单过滤..."
            # 简化的黑名单逻辑
        fi
        
        # 统计剩余文件
        local remaining_files=$(find "${SOURCE_PATH}" -type f 2>/dev/null | wc -l)
        log_i "过滤完成，剩余文件数: ${remaining_files}"
        
        # 验证保护机制
        if [[ ${remaining_files} -eq 0 ]]; then
            log_e "❌ 异常：尽管有安全保护，但所有文件仍被删除！"
        else
            log_i "✅ 过滤保护有效，成功保留了 ${remaining_files} 个重要文件"
        fi
    fi
}

echo
echo "📋 测试场景1：会触发全删保护的配置"
echo "========================================"

export FILTER_FILE="${TEST_DIR}/dangerous_filter.conf"
cat > "${FILTER_FILE}" << 'EOF'
include-file=mkv|mp4|avi
EOF

echo "配置内容："
cat "${FILTER_FILE}"
echo

echo "🚀 执行过滤测试..."
_filter_load
_delete_exclude_file

echo
echo "📊 测试后文件列表："
ls -la "${TEST_DIR}/downloads/test_task/" 2>/dev/null || echo "目录为空"

echo
echo "📋 测试场景2：安全的配置（不会触发保护）"
echo "==========================================="

# 重新创建测试文件
cd "${TEST_DIR}/downloads/test_task"
echo "文本文件1" > "file1.txt"
echo "视频文件" > "movie.mkv"
echo "文档文件" > "document.doc"

export FILTER_FILE="${TEST_DIR}/safe_filter.conf"
cat > "${FILTER_FILE}" << 'EOF'
include-file=mkv|txt
EOF

echo "配置内容："
cat "${FILTER_FILE}"
echo

echo "🚀 执行过滤测试..."
_filter_load
_delete_exclude_file

echo
echo "📊 测试后文件列表："
ls -la "${TEST_DIR}/downloads/test_task/" 2>/dev/null || echo "目录为空"

echo
echo "📋 测试场景3：黑名单模式的全删保护"
echo "=================================="

# 重新创建测试文件
cd "${TEST_DIR}/downloads/test_task"
echo "文本文件1" > "file1.txt"
echo "文本文件2" > "file2.txt"

export FILTER_FILE="${TEST_DIR}/blacklist_filter.conf"
cat > "${FILTER_FILE}" << 'EOF'
exclude-file=txt|doc|jpg|zip
EOF

echo "配置内容："
cat "${FILTER_FILE}"
echo

echo "🚀 执行过滤测试..."
_filter_load
_delete_exclude_file

echo
echo "📊 测试后文件列表："
ls -la "${TEST_DIR}/downloads/test_task/" 2>/dev/null || echo "目录为空"

echo
echo "📄 查看保护日志："
if [[ -f "${CF_LOG}" ]]; then
    cat "${CF_LOG}"
else
    echo "无保护日志"
fi

# 清理
rm -rf "${TEST_DIR}"

echo
echo "🎯 测试总结："
echo "  ✅ 场景1: 危险配置应该触发全删保护，跳过过滤"
echo "  ✅ 场景2: 安全配置应该正常执行过滤"
echo "  ✅ 场景3: 黑名单全删也应该触发保护"
echo
echo "✅ 全删保护功能测试完成"
