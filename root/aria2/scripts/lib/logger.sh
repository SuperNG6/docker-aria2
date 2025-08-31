#!/usr/bin/env bash
# shellcheck shell=bash
# 统一日志库：供所有脚本（handlers/utils/cont-init.d）复用
# 仅定义颜色、时间与 log_* 接口，不引入其他依赖

if [[ -n "${_ARIA2_LIB_LOGGER_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_LOGGER_SH_LOADED=1

# 颜色定义
LOG_RED="\033[31m"
LOG_GREEN="\033[1;32m" 
LOG_YELLOW="\033[1;33m"
# shellcheck disable=SC2034  # LOG_CYAN被file_ops.sh等文件使用
LOG_CYAN="\033[36m"
# shellcheck disable=SC2034  # LOG_PURPLE被file_ops.sh等文件使用
LOG_PURPLE="\033[1;35m"
# shellcheck disable=SC2034  # LOG_BOLD被file_ops.sh等文件使用
LOG_BOLD="\033[1m"
LOG_NC="\033[0m"

# 标签定义（修正拼写错误）
INFO="[${LOG_GREEN}INFO${LOG_NC}]"
ERROR="[${LOG_RED}ERROR${LOG_NC}]"
WARN="[${LOG_YELLOW}WARN${LOG_NC}]"

# 时间函数
now() { date +"%Y/%m/%d %H:%M:%S"; }

# 基础日志函数（仅控制台输出）
log_i() { echo -e "$(now) ${INFO} $*"; }
log_w() { echo -e "$(now) ${WARN} $*"; }
log_e() { echo -e "$(now) ${ERROR} $*"; }

# 彩色日志函数（支持颜色输出到控制台）
log_i_color() { echo -e "$(now) ${INFO} $*"; }
log_w_color() { echo -e "$(now) ${WARN} $*"; }
log_e_color() { echo -e "$(now) ${ERROR} $*"; }

# tee模式：同时输出到控制台和文件（用于重要操作）
log_i_tee() { echo -e "$(now) ${INFO} $*" | tee -a "${1}"; }
log_w_tee() { echo -e "$(now) ${WARN} $*" | tee -a "${1}"; }
log_e_tee() { echo -e "$(now) ${ERROR} $*" | tee -a "${1}"; }

# 文件模式：仅写入文件，使用纯文本格式（兼容原项目的条件日志）
log_file() { 
    local level="$1" file="$2"; shift 2
    [[ -n "${file}" ]] && echo -e "$(now) [${level}] $*" >> "${file}"
}
log_i_file() { log_file "INFO" "$@"; }
log_w_file() { log_file "WARN" "$@"; }
log_e_file() { log_file "ERROR" "$@"; }
