#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154,SC2034
# 事件处理：on-download-pause（下载暂停）
# 职责：当 setting.conf 中启用 move-paused-task（MPT=true）时，模拟“完成”后的处理：
#   - 将当前任务移动到 completed 目录（MOVE 强制设为 true）。
#   - 处理 BT 的 .torrent 文件。
# 输入参数：$1=GID  $2=FILE_NUM  $3=FILE_PATH
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
completed_path
get_final_path

if [[ "${MPT}" = "true" ]]; then # 仅在配置开启时生效
	if [[ "${FILE_NUM}" -eq 0 ]] || [[ -z "${FILE_PATH}" ]]; then
		exit 0
	elif [[ "${GET_PATH_INFO:-}" = "error" ]]; then
		log_e "GID:${TASK_GID} 获取任务路径失败!"
		exit 1
	else
		MOVE=true # 强制移动（忽略 dmof 限制）
		move_file
		check_torrent # 根据 TOR 策略处理 .torrent
	fi
fi
