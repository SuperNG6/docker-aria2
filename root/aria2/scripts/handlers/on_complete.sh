#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# 事件处理：on-download-complete（下载完成）
# 职责：
#   - 读取 setting.conf、RPC 任务信息与路径，解析最终位置。
#   - 按 MOVE/CF/DET 等策略执行内容清理与文件移动；
#   - 若为 BT 且保存了 .torrent，按 TOR 策略处理种子文件。
# 输入参数（aria2 传入）：
#   $1=GID  $2=FILE_NUM  $3=FILE_PATH
# 退出码：0 正常；非 0 表示获取路径失败等异常。
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

# 路径错误防护：无有效文件信息直接返回；解析失败时报错退出
if [[ "${FILE_NUM}" -eq 0 ]] || [[ -z "${FILE_PATH}" ]]; then
	exit 0
elif [[ "${GET_PATH_INFO:-}" = "error" ]]; then
	log_e "GID:${TASK_GID} 获取任务路径失败!"
	exit 1
else
	move_file     # 按 MOVE/CF/DET 等策略执行移动与清理
	check_torrent # 若存在 .torrent 文件则按 TOR 策略处理
fi
