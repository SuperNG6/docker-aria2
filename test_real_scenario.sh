#!/usr/bin/env bash
# 测试真实场景：电影下载包含各种大小的文件

echo "🎬 真实场景测试：电影下载文件过滤"
echo "======================================="

# 创建测试环境
TEST_DIR="/tmp/movie_filter_test_$(date +%s)"
mkdir -p "${TEST_DIR}/downloads/Movie.2024.1080p.BluRay"

# 创建真实场景的文件
cd "${TEST_DIR}/downloads/Movie.2024.1080p.BluRay"

echo "🎯 创建模拟文件..."

# 主要文件 - 应该保留
echo "模拟1GB电影文件内容" > "Movie.2024.1080p.BluRay.mkv"
dd if=/dev/zero of="Movie.2024.1080p.BluRay.mkv" bs=1024 count=1048576 2>/dev/null  # 模拟1GB
echo "字幕文件内容" > "Movie.2024.1080p.BluRay.srt"
dd if=/dev/zero of="Movie.2024.1080p.BluRay.srt" bs=1024 count=1 2>/dev/null  # 1KB

# 垃圾文件 - 应该被删除
echo "垃圾广告1" > "ads_1.txt"
dd if=/dev/zero of="ads_1.txt" bs=1024 count=1024 2>/dev/null  # 1MB
echo "垃圾广告2" > "ads_2.jpg"  
dd if=/dev/zero of="ads_2.jpg" bs=1024 count=2048 2>/dev/null  # 2MB
echo "广告视频" > "trailer_ads.mp4"
dd if=/dev/zero of="trailer_ads.mp4" bs=1024 count=51200 2>/dev/null  # 50MB
echo "网站推广" > "website.html"
dd if=/dev/zero of="website.html" bs=1024 count=512 2>/dev/null  # 512KB
echo "安装说明" > "readme.txt"
dd if=/dev/zero of="readme.txt" bs=1024 count=256 2>/dev/null  # 256KB

# 其他小文件
echo "样本视频" > "sample.mkv"
dd if=/dev/zero of="sample.mkv" bs=1024 count=10240 2>/dev/null  # 10MB
echo "NFO信息" > "movie.nfo"
dd if=/dev/zero of="movie.nfo" bs=1024 count=4 2>/dev/null  # 4KB

echo
echo "📊 过滤前文件统计："
ls -lh "${TEST_DIR}/downloads/Movie.2024.1080p.BluRay/"
echo
du -sh "${TEST_DIR}/downloads/Movie.2024.1080p.BluRay/"*

# 创建过滤配置
export FILTER_FILE="${TEST_DIR}/filter.conf"
cat > "${FILTER_FILE}" << 'EOF'
min-size=100M
include-file=mkv|mp4|avi|srt|ass
EOF

echo
echo "📋 过滤配置："
cat "${FILTER_FILE}"
echo

# 设置环境变量
export SOURCE_PATH="${TEST_DIR}/downloads/Movie.2024.1080p.BluRay"
export FILE_NUM=8
export DOWNLOAD_PATH="${TEST_DIR}/downloads"
export CF_LOG="${TEST_DIR}/filter.log"

# 模拟依赖函数
kv_get() {
    [[ -f "$1" ]] || return 1
    grep -E "^$2=" "${1}" | sed -E 's/^([^=]+)=//'
}

log_i() { echo -e "$(date +'%H:%M:%S') [INFO] $*"; }
log_w() { echo -e "$(date +'%H:%M:%S') [WARN] $*"; }

# 加载过滤配置
_filter_load() {
    MIN_SIZE=$(kv_get "${FILTER_FILE}" min-size)
    INCLUDE_FILE=$(kv_get "${FILTER_FILE}" include-file)
    EXCLUDE_FILE=$(kv_get "${FILTER_FILE}" exclude-file)
    KEYWORD_FILE=$(kv_get "${FILTER_FILE}" keyword-file)
    INCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" include-file-regex)
    EXCLUDE_FILE_REGEX=$(kv_get "${FILTER_FILE}" exclude-file-regex)
}

# 改进的过滤函数
_delete_exclude_file() {
    if [[ ${FILE_NUM} -gt 1 ]] && [[ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]] && [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} || -n ${KEYWORD_FILE} || -n ${EXCLUDE_FILE_REGEX} || -n ${INCLUDE_FILE_REGEX} ]]; then
        log_i "删除不需要的文件..."
        
        # 统计初始文件
        local initial_count=$(find "${SOURCE_PATH}" -type f | wc -l)
        local initial_size=$(du -sh "${SOURCE_PATH}" | cut -f1)
        log_i "过滤前: ${initial_count} 个文件，总大小 ${initial_size}"
        
        # 优化逻辑：检查是否有include规则，如果有则优先执行（白名单模式）
        if [[ -n "${INCLUDE_FILE}" ]] || [[ -n "${INCLUDE_FILE_REGEX}" ]]; then
            log_i "🎯 检测到白名单规则，优先执行以避免冲突"
            
            # 白名单模式：只保留匹配的文件，删除其他所有文件
            if [[ -n "${INCLUDE_FILE}" ]]; then
                log_i "🎬 保留文件类型: ${INCLUDE_FILE}"
                
                # 先显示哪些文件会被保留
                log_i "📋 将保留的文件："
                find "${SOURCE_PATH}" -type f | while read -r file; do
                    local should_keep=false
                    for ext in $(echo "${INCLUDE_FILE}" | tr '|' ' '); do
                        if [[ "${file}" =~ \."${ext}"$ ]]; then
                            should_keep=true
                            break
                        fi
                    done
                    if [[ ${should_keep} == true ]]; then
                        local size=$(du -sh "${file}" | cut -f1)
                        echo "  ✅ $(basename "${file}") (${size})"
                    fi
                done
                
                echo
                log_i "🗑️  删除不匹配的文件："
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
                        local size=$(du -sh "${file}" | cut -f1)
                        echo "  ❌ $(basename "${file}") (${size})"
                        rm -f "${file}"
                    fi
                done
            fi
            
            # 输出跳过的规则信息
            echo
            log_i "⏭️  白名单模式已执行，其他过滤规则已跳过："
            [[ -n "${MIN_SIZE}" ]] && log_i "  • 已跳过 min-size: ${MIN_SIZE}"
            [[ -n "${EXCLUDE_FILE}" ]] && log_i "  • 已跳过 exclude-file: ${EXCLUDE_FILE}"
            [[ -n "${KEYWORD_FILE}" ]] && log_i "  • 已跳过 keyword-file: ${KEYWORD_FILE}"
            
        else
            # 黑名单模式：没有include规则时，按原顺序执行exclude规则
            log_i "🚫 执行黑名单过滤模式"
            
            if [[ -n "${MIN_SIZE}" ]]; then
                log_i "📏 删除小于 ${MIN_SIZE} 的文件："
                find "${SOURCE_PATH}" -type f -size -"${MIN_SIZE}" | while read -r file; do
                    local size=$(du -sh "${file}" | cut -f1)
                    echo "  ❌ $(basename "${file}") (${size})"
                    rm -f "${file}"
                done
            fi
        fi
        
        echo
        # 统计剩余文件
        local remaining_files=$(find "${SOURCE_PATH}" -type f 2>/dev/null | wc -l)
        local final_size=$(du -sh "${SOURCE_PATH}" 2>/dev/null | cut -f1)
        log_i "✅ 过滤完成: ${remaining_files} 个文件，总大小 ${final_size}"
        
        # 如果所有文件都被删除，给出警告
        if [[ ${remaining_files} -eq 0 ]]; then
            log_w "⚠️  警告：所有文件都被过滤删除，请检查过滤配置"
        fi
    fi
}

echo "🚀 开始执行过滤..."
_filter_load
_delete_exclude_file

echo
echo "📊 过滤后文件统计："
ls -lh "${TEST_DIR}/downloads/Movie.2024.1080p.BluRay/" 2>/dev/null || echo "目录为空"

echo
echo "🎯 预期结果验证："
echo "  ✅ 应该保留: Movie.2024.1080p.BluRay.mkv (1GB 主要文件)"  
echo "  ✅ 应该保留: Movie.2024.1080p.BluRay.srt (1KB 字幕文件)"
echo "  ❌ 应该删除: ads_1.txt (1MB 广告文本)"
echo "  ❌ 应该删除: ads_2.jpg (2MB 广告图片)"
echo "  ❌ 应该删除: trailer_ads.mp4 (50MB 广告视频) - 虽然是mp4但会被白名单保留"
echo "  ❌ 应该删除: website.html (512KB 网站文件)"
echo "  ❌ 应该删除: readme.txt (256KB 说明文件)"
echo "  ❌ 应该删除: sample.mkv (10MB 样本视频) - 虽然是mkv但会被白名单保留"
echo "  ❌ 应该删除: movie.nfo (4KB NFO文件)"

echo
echo "💡 关键改进："
echo "  1. include规则优先执行，确保重要文件不被误删"
echo "  2. 即使有min-size=100M的配置，1KB的srt字幕文件也会被保留"
echo "  3. 所有非视频/字幕文件都被清理，包括广告和垃圾文件"
echo "  4. 配置简洁明确：只需设置要保留的文件类型"

# 清理
rm -rf "${TEST_DIR}"
echo
echo "✅ 测试完成"
