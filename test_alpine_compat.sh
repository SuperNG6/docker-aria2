#!/usr/bin/env bash
# 测试 Alpine Linux find 命令兼容性

echo "🔍 测试 Alpine Linux find 命令兼容性"
echo "======================================"

# 创建测试环境
TEST_DIR="/tmp/alpine_compat_test_$(date +%s)"
mkdir -p "${TEST_DIR}"

cd "${TEST_DIR}"
echo "测试文件" > "test.mkv"
echo "其他文件" > "other.txt"

echo "📋 测试文件："
ls -la

echo
echo "🧪 测试1: 标准 find 命令（应该支持）"
find . -type f -name "*.mkv"

echo
echo "🧪 测试2: 尝试 -regextype 选项（可能不支持）"
if find . -type f -regextype posix-extended -iregex ".*\.mkv" 2>/dev/null; then
    echo "✅ 支持 -regextype posix-extended"
else
    echo "❌ 不支持 -regextype posix-extended"
    echo "需要使用替代方案"
fi

echo
echo "🧪 测试3: 基本正则表达式（应该支持）"
if find . -type f -regex ".*\.mkv" 2>/dev/null; then
    echo "✅ 支持基本正则表达式"
else
    echo "❌ 不支持基本正则表达式"
fi

echo
echo "🧪 测试4: 测试可用的 find 选项"
echo "find 版本信息："
find --version 2>/dev/null || echo "无版本信息（可能是 BusyBox find）"

echo
echo "可用的 find 选项测试："
echo "- name 模式匹配："
find . -type f -name "*.mkv"

echo "- iname 大小写不敏感："
find . -type f -iname "*.MKV"

echo
echo "🔧 Alpine Linux 兼容的解决方案："
echo "1. 使用 -name 和 -iname 进行简单匹配"
echo "2. 使用 grep 进行正则表达式过滤"
echo "3. 使用 shell 模式匹配"

echo
echo "示例替代方案："
echo "原始: find . -regextype posix-extended -iregex '.*\.(mkv|mp4)'"
echo "替代1: find . -name '*.mkv' -o -name '*.mp4'"
echo "替代2: find . -type f | grep -iE '\.(mkv|mp4)$'"

# 测试替代方案
echo
echo "🚀 测试替代方案："

echo "方案1 - 多个 -name 条件："
find . -type f \( -name "*.mkv" -o -name "*.txt" \)

echo "方案2 - 管道 grep："
find . -type f | grep -E '\.(mkv|txt)$'

echo "方案3 - 大小写不敏感 grep："
find . -type f | grep -iE '\.(mkv|txt)$'

# 清理
cd /
rm -rf "${TEST_DIR}"

echo
echo "✅ 兼容性测试完成"
