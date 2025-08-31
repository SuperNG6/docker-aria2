#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2034
# RPC 相关操作库
# 职责：
#   - 构造 JSON-RPC 请求（含可选 SECRET 鉴权）。
#   - 提供通用调用封装：获取任务状态、删除任务、修改全局配置。
#   - 解析返回并导出常用字段供 handlers 使用。
# 约定：PORT/SECRET 若存在，则用于拼装 RPC 地址与鉴权。

if [[ -n "${_ARIA2_LIB_RPC_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_RPC_SH_LOADED=1

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh

RPC_ADDR() { echo "http://localhost:${PORT:-6800}/jsonrpc"; } # 生成 RPC 地址，默认 6800

rpc_call() {
	# 统一的 RPC 调用入口：先 HTTP，失败回退 HTTPS（-k）
	# $1: json payload
	local payload="$1"
	curl "$(RPC_ADDR)" -fsSd "${payload}" -H 'Content-Type: application/json' || curl "$(RPC_ADDR | sed "s@http:@https:@")" -kfsSd "${payload}" -H 'Content-Type: application/json'
}

rpc_payload_status() {
	# 生成 tellStatus 请求体；若设置 SECRET 则携带 token
	# $1: gid
	local gid="$1"
	local id="NG6"
	if [[ -n "${SECRET:-}" ]]; then
		echo '{"jsonrpc":"2.0","method":"aria2.tellStatus","id":"'"${id}"'","params":["token:'"${SECRET}"'","'"${gid}"'"]}'
	else
		echo '{"jsonrpc":"2.0","method":"aria2.tellStatus","id":"'"${id}"'","params":["'"${gid}"'"]}'
	fi
}

rpc_payload_remove() {
	# 生成 remove 请求体；若设置 SECRET 则携带 token
	local gid="$1"
	local id="NG6"
	if [[ -n "${SECRET:-}" ]]; then
		echo '{"jsonrpc":"2.0","method":"aria2.remove","id":"'"${id}"'","params":["token:'"${SECRET}"'","'"${gid}"'"]}'
	else
		echo '{"jsonrpc":"2.0","method":"aria2.remove","id":"'"${id}"'","params":["'"${gid}"'"]}'
	fi
}

rpc_payload_change_global() {
	# 生成 changeGlobalOption 请求体；若设置 SECRET 则携带 token
	# $1: key $2: value
	local key="$1" val="$2" id="NG6"
	if [[ -n "${SECRET:-}" ]]; then
		echo '{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"'"${id}"'","params":["token:'"${SECRET}"'",{"'"${key}"'":"'"${val}"'"}]}'
	else
		echo '{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"'"${id}"'","params":[{"'"${key}"'":"'"${val}"'"}]}'
	fi
}

rpc_get_status() {
	# 执行 tellStatus 并返回原始 JSON
	# $1: gid -> stdout json
	local payload
	payload=$(rpc_payload_status "$1")
	rpc_call "${payload}"
}

rpc_remove_task() {
	# 执行 remove 删除任务
	local payload
	payload=$(rpc_payload_remove "$1")
	rpc_call "${payload}"
}

rpc_change_global_option() {
	# 修改 aria2 的全局配置（如 bt-tracker）
	local key="$1" val="$2" payload
	payload=$(rpc_payload_change_global "${key}" "${val}")
	rpc_call "${payload}"
}

rpc_get_parsed_fields() {
	# 获取并解析任务核心字段，失败时返回非 0
	# $1: gid -> set global vars: RPC_RESULT, TASK_STATUS, DOWNLOAD_DIR, INFO_HASH, TORRENT_PATH, TORRENT_FILE
	local gid="$1"
	RPC_RESULT=$(rpc_get_status "${gid}")
	if [[ -z "${RPC_RESULT}" ]]; then
		log_e "Aria2 RPC 接口错误。"
		return 1
	fi
	TASK_STATUS=$(echo "${RPC_RESULT}" | jq -r '.result.status')
	DOWNLOAD_DIR=$(echo "${RPC_RESULT}" | jq -r '.result.dir')
	INFO_HASH=$(echo "${RPC_RESULT}" | jq -r '.result.infoHash // empty')
	if [[ -z "${TASK_STATUS}" ]] || [[ -z "${DOWNLOAD_DIR}" ]]; then
		echo "${RPC_RESULT}" | jq '.result' 2>/dev/null || true
		log_e "获取任务状态或下载目录失败。"
		return 1
	fi
	if [[ -n "${INFO_HASH}" ]] && [[ "${INFO_HASH}" != "null" ]]; then
		TORRENT_PATH="${DOWNLOAD_DIR}/${INFO_HASH}"
		TORRENT_FILE="${DOWNLOAD_DIR}/${INFO_HASH}.torrent"
	else
		TORRENT_PATH=""
		TORRENT_FILE=""
	fi
}

# 仅用于重复任务移除：延迟 3s 后忽略错误尝试 remove
rpc_remove_repeat_task() {
	local gid="$1"
	sleep 3
	rpc_remove_task "${gid}" >/dev/null 2>&1 || true
}
