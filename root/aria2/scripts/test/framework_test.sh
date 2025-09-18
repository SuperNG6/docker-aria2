#!/usr/bin/env bash
# =============================================================================
# 简单的框架功能测试
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
TEST_LOG_DIR="/tmp/aria2-test-logs"

# 清理测试环境
cleanup() {
    rm -rf "$TEST_LOG_DIR"
}

# 设置测试环境
setup() {
    mkdir -p "$TEST_LOG_DIR"
    export DRY_RUN="true"
    export DEBUG_MODE="true"
}

# 测试框架加载
test_framework_loading() {
    echo "测试框架加载..."
    
    # 加载库
    source "$SCRIPT_DIR/../lib/lib.sh"
    
    # 初始化
    init_lib "/tmp/test-config" "$TEST_LOG_DIR"
    
    # 验证模块是否加载
    if [[ "$ARIA2_LIB_LOADED" == "true" ]] && \
       [[ "$ARIA2_UTIL_LOADED" == "true" ]] && \
       [[ "$ARIA2_LOG_LOADED" == "true" ]] && \
       [[ "$ARIA2_RPC_LOADED" == "true" ]] && \
       [[ "$ARIA2_PATHS_LOADED" == "true" ]] && \
       [[ "$ARIA2_FSOPS_LOADED" == "true" ]] && \
       [[ "$ARIA2_TORRENT_LOADED" == "true" ]]; then
        echo "✓ 所有模块加载成功"
        return 0
    else
        echo "✗ 模块加载失败"
        return 1
    fi
}

# 测试日志功能
test_logging() {
    echo "测试日志功能..."
    
    log_info "这是一条信息日志"
    log_warn "这是一条警告日志"
    log_debug "这是一条调试日志"
    
    echo "✓ 日志功能测试完成"
}

# 测试工具函数
test_utilities() {
    echo "测试工具函数..."
    
    # 测试布尔值解析
    local result
    result=$(parse_bool "true")
    [[ "$result" == "true" ]] || { echo "✗ parse_bool 测试失败"; return 1; }
    
    # 测试大小转换
    result=$(to_bytes "1G")
    [[ "$result" == "1073741824" ]] || { echo "✗ to_bytes 测试失败"; return 1; }
    
    # 测试时间格式化
    result=$(date_time)
    [[ -n "$result" ]] || { echo "✗ date_time 测试失败"; return 1; }
    
    echo "✓ 工具函数测试完成"
}

# 测试配置解析
test_config_parsing() {
    echo "测试配置解析..."
    
    # 创建测试配置文件
    local test_config="/tmp/test-setting.conf"
    cat > "$test_config" << EOF
# 测试配置文件
test-option=true
move-task=false
remove-task=rmaria
# 注释行应该被忽略
handle-torrent=backup-rename
EOF

    # 加载配置
    if load_config "$test_config"; then
        echo "✓ 配置文件加载成功"
    else
        echo "✗ 配置文件加载失败"
        return 1
    fi
    
    # 清理
    rm -f "$test_config"
}

# 主测试函数
main() {
    echo "=== Aria2脚本框架测试开始 ==="
    
    setup
    
    # 运行测试
    test_framework_loading || exit 1
    test_logging || exit 1
    test_utilities || exit 1
    test_config_parsing || exit 1
    
    echo "=== 所有测试通过！ ==="
    
    cleanup
}

# 错误处理
trap cleanup EXIT

main "$@"