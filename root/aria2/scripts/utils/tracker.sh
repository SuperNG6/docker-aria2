#!/usr/bin/env bash
# 工具：Tracker 更新
# 用法：tracker.sh            -> 从默认列表更新到 aria2.conf
#       tracker.sh --local    -> 从 /config/aria2.conf 直接覆盖 bt-tracker（同上）
#       tracker.sh --rpc      -> 通过 RPC 动态更新 bt-tracker（无需重启）

set -euo pipefail
. /aria2/scripts/lib/logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/config.sh
. /aria2/scripts/lib/rpc.sh
. /aria2/scripts/lib/kvconf.sh

# 使用集中化的 ARIA2_CONF
DOWNLOADER="curl -fsSL --connect-timeout 3 --max-time 3 --retry 2"
NL=$'\n'
TRACKER_COUNT=0

get_trackers() {
	# 描述：获取 trackers 列表；优先使用默认源，若设置 CTU（逗号分隔）则按自定义源合并去重。
	if [ -z "${CTU:-}" ]; then
		log_i "获取 bt-tracker ..."
		TRACKER=$(
			${DOWNLOADER} https://trackerslist.com/all_aria2.txt ||
				${DOWNLOADER} https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt ||
				${DOWNLOADER} https://trackers.p3terx.com/all_aria2.txt
		)
	else
		log_i "从自定义地址获取 bt-tracker: ${CTU}"
		local urls
		urls=$(echo "${CTU}" | tr "," "$NL")
		local t=""
		for u in $urls; do
			t+="$(${DOWNLOADER} "$u" | tr "," "\n")$NL"
		done
		TRACKER=$(echo "$t" | awk NF | sort -u | sed 'H;1h;$!d;x;y/\n/,/')
	fi
	[ -n "${TRACKER:-}" ] || {
		log_e "无法获取 trackers，网络错误或链接无效。"
		exit 1
	}

	# 统计数量（按逗号拆分并过滤空行）
	TRACKER_COUNT=$(printf "%s" "${TRACKER}" | tr ',' '\n' | awk 'NF' | wc -l | tr -d ' ')
}

show_trackers() {
	# 描述：打印列表或摘要；默认打印数量摘要，TRACKER_SHOW=list 或 DEBUG=1 时打印完整列表
	local mode="count"
	if [[ "${TRACKER_SHOW:-count}" = "list" || "${DEBUG:-0}" = "1" ]]; then
		mode="list"
	fi
	if [[ "${mode}" = "list" ]]; then
		echo -e "\n--------------------[BitTorrent Trackers]--------------------\n${TRACKER}\n--------------------[BitTorrent Trackers]--------------------\n"
	else
		log_i "获取到 ${TRACKER_COUNT} 条 bt-tracker。"
	fi
}

add_trackers_conf() {
	# 描述：将 TRACKER 列表写入到 /config/aria2.conf 的 bt-tracker 键
	log_i "添加 bt-tracker 到 Aria2 配置文件: ${LOG_PURPLE}${ARIA2_CONF}${LOG_NC}"
	[ -f "$ARIA2_CONF" ] || {
		log_e "配置文件不存在: $ARIA2_CONF"
		exit 1
	}
	conf_upsert_kv "$ARIA2_CONF" bt-tracker "$TRACKER"
	log_i "bt-tracker 已写入配置文件，共 ${TRACKER_COUNT} 条。"
}

add_trackers_rpc() {
	# 描述：通过 RPC 动态更新 bt-tracker，无需重启 aria2
	log_i "通过 RPC 更新 bt-tracker（无需重启）..."
	local res
	res=$(rpc_change_global_option "bt-tracker" "${TRACKER}" || true)
	if echo "$res" | grep -q OK; then
		log_i "RPC 更新成功，共 ${TRACKER_COUNT} 条。"
	else
		log_e "RPC 更新失败或接口无响应。"
	fi
}

main() {
	# 描述：主入口；默认写配置文件，传入 --rpc 参数时改为通过 RPC 更新
	local mode="conf"
	if [ "${1:-}" = "--rpc" ]; then mode="rpc"; fi
	get_trackers
	show_trackers
	if [ "$mode" = "rpc" ]; then
		add_trackers_rpc
	else
		add_trackers_conf
	fi
}

main "$@"
