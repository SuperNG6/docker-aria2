#!/usr/bin/env bash
#====================================================================
# logging.sh
# 日志输出、时间戳、颜色等基础功能
#====================================================================

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[1;33m"
PURPLE="\033[1;35m"
RESET="\033[0m"

# 日志前缀
INFO="[${GREEN}INFO${RESET}]"
WARN="[${YELLOW}WARN${RESET}]"
ERROR="[${RED}ERROR${RESET}]"

# 获取当前时间戳
get_datetime() {
    date "+%Y/%m/%d %H:%M:%S"
}

# 日志输出函数
log_info() {
    local message="$1"
    echo -e "$(get_datetime) ${INFO} ${message}"
}

log_warn() {
    local message="$1"
    echo -e "$(get_datetime) ${WARN} ${message}" >&2
}

log_error() {
    local message="$1"
    echo -e "$(get_datetime) ${ERROR} ${message}" >&2
}

# 输出任务信息
print_task_info() {
    # 任务类型由调用方传入
    local task_type="$1"
    local source_path="$2"
    local file_path="$3"
    local file_num="$4"
    local target_path="${5:-}"

    echo -e "
-------------------------- [${YELLOW} 任务信息 ${task_type} ${RESET}] --------------------------
${PURPLE}根下载路径:${RESET} ${DOWNLOAD_PATH}
${PURPLE}任务位置:${RESET} ${source_path}
${PURPLE}首个文件位置:${RESET} ${file_path}
${PURPLE}任务文件数量:${RESET} ${file_num}"

    # 只有在需要时才显示目标路径
    if [[ -n "${target_path}" ]]; then
        echo -e "${PURPLE}移动至目标文件夹:${RESET} ${target_path}"
    fi

    echo "-----------------------------------------------------------------------------------------------------------------------"
}