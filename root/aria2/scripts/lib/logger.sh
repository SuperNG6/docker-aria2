#!/usr/bin/env bash
# shellcheck shell=bash
# 统一日志库：供所有脚本（handlers/utils/cont-init.d）复用
# 仅定义颜色、时间与 log_* 接口，不引入其他依赖

if [[ -n "${_ARIA2_LIB_LOGGER_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_LOGGER_SH_LOADED=1

LOG_RED="\033[31m"
LOG_GREEN="\033[1;32m"
LOG_YELLOW="\033[1;33m"
LOG_CYAN="\033[36m"
LOG_PURPLE="\033[35m"
LOG_BOLD="\033[1m"
LOG_NC="\033[0m"
INFO="[${LOG_GREEN}INFO${LOG_NC}]"
ERROR="[${LOG_RED}ERROR${LOG_NC}]"
WARN="[${LOG_YELLOW}WARN${LOG_NC}]"
now() { date +"%Y/%m/%d %H:%M:%S"; }
log_i() { echo -e "$(now) ${INFO} $*"; }
log_w() { echo -e "$(now) ${WARN} $*"; }
log_e() { echo -e "$(now) ${ERROR} $*"; }

# 支持同时输出到控制台和日志文件的函数
log_i_tee() { echo -e "$(now) ${INFO} $*" | tee -a "${1}"; }
log_w_tee() { echo -e "$(now) ${WARN} $*" | tee -a "${1}"; }
log_e_tee() { echo -e "$(now) ${ERROR} $*" | tee -a "${1}"; }
