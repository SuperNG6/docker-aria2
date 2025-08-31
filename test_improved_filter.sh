#!/usr/bin/env bash
# 测试改进后的过滤逻辑

echo "🧪 测试改进的文件过滤逻辑"
echo "==============================="

# 创建测试环境
TEST_DIR="/tmp/filter_test_$(date +%s)"
mkdir -p "${TEST_DIR}/downloads/test_movie"

# 创建测试文件
cd "${TEST_DIR}/downloads/test_movie"
echo "主要视频文件" > "Movie.2024.1080p.mkv"
echo "字幕文件" > "Movie.2024.srt"
echo "小文件" > "readme.txt"
echo "日志文件" > "debug.log"
echo "样本文件" > "sample.mkv"
echo "临时文件" > "temp.tmp"

echo "📁 测试前文件列表："
ls -la "${TEST_DIR}/downloads/test_movie/"
echo

# 模拟配置（同时有include和exclude规则）
export FILTER_FILE="${TEST_DIR}/filter.conf"
cat > "${FILTER_FILE}" << 'EOF'
min-size=1M
exclude-file=tmp|log|txt
keyword-file=sample|test
include-file=mkv|mp4|avi|srt
EOF

echo "📋 测试配置："
cat "${FILTER_FILE}"
echo

# 模拟环境变量
export SOURCE_PATH="${TEST_DIR}/downloads/test_movie"
export FILE_NUM=6
export DOWNLOAD_PATH="${TEST_DIR}/downloads"
export CF_LOG="${TEST_DIR}/filter.log"

# 创建模拟的依赖函数
kv_get() {
    [[ -f "$1" ]] || return 1
    grep -E "^$2=" "${1}" | sed -E 's/^([^=]+)=//'
}

log_i() { echo -e "[INFO] $*"; }
log_w() { echo -e "[WARN] $*"; }

# 创建改进的过滤函数
_filter_load() {
    MIN_SIZE=$(kv_get "${FILTER_FILE}" min-size)
    INCLUDE_FILE=$(kv_get "${FILTER_FILE}" include-file)
    EXCLUDE_FILE=$(kv_get "${FILTER_FILE}" exclude-file)
    KEYWORD_FILE=$(kv_get "${FILTER_FILE}" keyword-file)
    INCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" include-file-regex)
    EXCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" exclude-file-regex)
}

# 改进的过滤函数（复制改进逻辑）
_delete_exclude_file() {
    if [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]] && [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} || -n ${KEYWORD_FILE} || -n ${EXCLUDE_FILE_REGEX} || -n ${INCLUDE_FILE_REGEX} ]]; then
        log_i "删除不需要的文件..."
        
        # 优化逻辑：检查是否有include规则，如果有则优先执行（白名单模式）
        if [[ -n "${INCLUDE_FILE}" ]] || [[ -n "${INCLUDE_FILE_REGEX}" ]]; then
            log_i "检测到白名单规则，优先执行以避免冲突"
            
            # 白名单模式：只保留匹配的文件，删除其他所有文件
            if [[ -n "${INCLUDE_FILE}" ]]; then
                log_i "保留文件类型: ${INCLUDE_FILE}"
                # macOS兼容版本
                for ext in $(echo "${INCLUDE_FILE}" | tr '|' ' '); do
                    echo "  检查扩展名: ${ext}"
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
                        echo "删除: ${file}"
                        rm -f "${file}"
                    else
                        echo "保留: ${file}"
                    fi
                done
            fi
            
            # 输出提示信息
            log_i "白名单模式已执行，其他过滤规则已跳过以避免冲突"
            [[ -n "${EXCLUDE_FILE}" ]] && log_i "已跳过 exclude-file: ${EXCLUDE_FILE}"
            [[ -n "${KEYWORD_FILE}" ]] && log_i "已跳过 keyword-file: ${KEYWORD_FILE}"
            [[ -n "${MIN_SIZE}" ]] && log_i "已跳过 min-size: ${MIN_SIZE}"
            [[ -n "${EXCLUDE_FILE_REGEX}" ]] && log_i "已跳过 exclude-file-regex: ${EXCLUDE_FILE_REGEX}"
            
        else
            # 黑名单模式：没有include规则时，按原顺序执行exclude规则
            log_i "执行黑名单过滤模式"
            
            # 实现黑名单逻辑...
            echo "（黑名单模式的具体实现）"
        fi
        
        # 统计剩余文件
        local remaining_files=$(find "${SOURCE_PATH}" -type f 2>/dev/null | wc -l)
        log_i "过滤完成，剩余文件数: ${remaining_files}"
        
        # 如果所有文件都被删除，给出警告
        if [[ ${remaining_files} -eq 0 ]]; then
            log_w "警告：所有文件都被过滤删除，请检查过滤配置"
        fi
    fi
}

echo "🔄 执行过滤测试..."
_filter_load
_delete_exclude_file

echo
echo "📁 测试后文件列表："
ls -la "${TEST_DIR}/downloads/test_movie/" 2>/dev/null || echo "目录为空或不存在"

echo
echo "🎯 预期结果："
echo "  ✅ 应该保留：Movie.2024.1080p.mkv (mkv文件)"
echo "  ✅ 应该保留：Movie.2024.srt (srt文件)"
echo "  ❌ 应该删除：readme.txt (不在白名单中)"
echo "  ❌ 应该删除：debug.log (不在白名单中)"
echo "  ❌ 应该删除：sample.mkv (虽然是mkv但在之前会被keyword过滤，现在应该保留)"
echo "  ❌ 应该删除：temp.tmp (不在白名单中)"

echo
echo "💡 改进效果："
echo "  - include规则优先执行，避免规则冲突"
echo "  - 白名单模式下其他规则被跳过"
echo "  - 配置文件无需修改，完全兼容"

# 清理
rm -rf "${TEST_DIR}"
echo
echo "✅ 测试完成"
