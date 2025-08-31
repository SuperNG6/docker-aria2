#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# 事件处理：on-download-stop（下载停止）
# 职责：依据 setting.conf 的 remove-task 选项，对停止的任务执行：
#   - recycle：移动到回收站；
#   - delete：直接删除；
#   - rmaria：仅删除 .aria2 控制文件；
# 并在合适时机处理 .torrent 文件。
# 输入参数：$1=GID  $2=FILE_NUM  $3=FILE_PATH（可能为空）
set -euo pipefail

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/config.sh
. /aria2/scripts/lib/path.sh
. /aria2/scripts/lib/rpc.sh
. /aria2/scripts/lib/file_ops.sh
. /aria2/scripts/lib/torrent.sh

TASK_GID=${1:-}
FILE_NUM=${2:-0}
FILE_PATH=${3:-}

config_load_setting
rpc_get_parsed_fields "${TASK_GID}" || exit 1
recycle_path
get_final_path

stop_handler() {
	# 描述：根据 RMTASK 与 TASK_STATUS 分支执行后处理
	if [[ "${FILE_NUM}" -eq 0 ]] || [[ -z "${FILE_PATH}" ]]; then
		exit 0
	elif [[ "${GET_PATH_INFO:-}" = "error" ]]; then
		log_e "GID:${TASK_GID} 获取任务路径失败!"
		exit 1
	elif [[ "${RMTASK}" = "recycle" ]] && [[ "${TASK_STATUS}" != "error" ]]; then
		move_recycle
		check_torrent
		rm_aria2
		exit 0
	elif [[ "${RMTASK}" = "delete" ]] && [[ "${TASK_STATUS}" != "error" ]]; then
		delete_file
		check_torrent
		rm_aria2
		exit 0
	elif [[ "${RMTASK}" = "rmaria" ]] && [[ "${TASK_STATUS}" != "error" ]]; then
		check_torrent
		rm_aria2
		exit 0
	fi
}

# 若源路径已不存在（可能 start 阶段已清理），则不操作（防止误删）
if [[ -d "${SOURCE_PATH}" ]] || [[ -e "${SOURCE_PATH}" ]]; then
	stop_handler
fi
