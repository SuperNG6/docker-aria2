#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# 事件处理：on-download-start（下载开始）
# 职责：
#   - 读取 setting.conf 配置与 RPC 任务信息，解析最终路径。
#   - 若启用 remove-repeat-task（RRT=true），当“已存在同名已完成目录”时，将当前重复任务删除并清理已有下载数据。
# 输入参数（aria2 传入）：
#   $1=GID  $2=FILE_NUM  $3=FILE_PATH（开始阶段可能为空）
# 退出码：
#   0 正常；非 0 表示获取路径失败等异常（用于日志定位，aria2 不会中止）。
set -euo pipefail

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/config.sh
. /aria2/scripts/lib/path.sh
. /aria2/scripts/lib/rpc.sh

TASK_GID=${1:-}  # 任务 GID
FILE_NUM=${2:-0} # 文件数量（磁力开始阶段可能为 0）
FILE_PATH=${3:-} # 首个文件路径（开始阶段可能为空）

config_load_setting
rpc_get_parsed_fields "${TASK_GID}" || exit 1
completed_path
get_final_path

# 逻辑：若目标目录已存在同名任务且状态非 error，则移除重复任务并清理现有下载数据
if [[ "${RRT}" = "true" ]]; then
	if [[ "${FILE_NUM}" -eq 0 ]] || [[ -z "${FILE_PATH}" ]]; then
		exit 0
	elif [[ "${GET_PATH_INFO:-}" = "error" ]]; then
		log_e "GID:${TASK_GID} 获取任务路径失败!"
		exit 1
	elif [[ -d "${COMPLETED_DIR:-}" ]] && [[ "${TASK_STATUS}" != "error" ]]; then
		log_w "发现目标文件夹已存在当前任务 ${LOG_GREEN}${COMPLETED_DIR}${LOG_NC}"
		log_w "正在删除该任务，并清除相关文件... ${LOG_GREEN}${SOURCE_PATH}${LOG_NC}"
		# 删除控制文件与源
		[[ -e "${SOURCE_PATH}.aria2" ]] && rm -f "${SOURCE_PATH}.aria2" || true
		rm -rf "${SOURCE_PATH}" || true
		rpc_remove_repeat_task "${TASK_GID}"
		exit 0
	fi
fi
