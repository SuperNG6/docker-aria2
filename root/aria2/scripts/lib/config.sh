#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# 配置管理库（供 handlers/utils 使用）
# 职责：
#   - 读取 /config/setting.conf 的开关项到当前 Shell 环境（handlers 使用）。
#   - 提供回填函数：以模板为基准补齐用户缺失的键（不覆盖已有值）。
# 注意：
#   - 不主动修改 setting.conf，除非显式调用 config_apply_setting_defaults（由 20-config 在初始化阶段调用）。

# 防止重复加载
if [[ -n "${_ARIA2_LIB_CONFIG_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_CONFIG_SH_LOADED=1

# 引入依赖库
# common.sh 已引入 logger.sh
. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/path.sh

# 统一初始化路径变量（SETTING_FILE/ARIA2_CONF/FILTER_FILE 等）
get_base_paths

# 读取 setting.conf 中的开关
# 将键值对加载到当前 shell 环境变量中，供 handlers 使用。
config_load_setting() {
	# 描述：将 setting.conf 的各项开关读入环境变量（RMTASK/MOVE/CF/DET/TOR/RRT/MPT）
	RMTASK=$(kv_get "${SETTING_FILE}" remove-task)
	MOVE=$(kv_get "${SETTING_FILE}" move-task)
	CF=$(kv_get "${SETTING_FILE}" content-filter)
	DET=$(kv_get "${SETTING_FILE}" delete-empty-dir)
	TOR=$(kv_get "${SETTING_FILE}" handle-torrent)
	RRT=$(kv_get "${SETTING_FILE}" remove-repeat-task)
	MPT=$(kv_get "${SETTING_FILE}" move-paused-task)
	
	# 兜底默认值（防御性编程：应对配置文件损坏或缺失键的情况）
	RMTASK="${RMTASK:-rmaria}"
	MOVE="${MOVE:-false}"
	CF="${CF:-false}"
	DET="${DET:-true}"
	TOR="${TOR:-backup-rename}"
	RRT="${RRT:-true}"
	MPT="${MPT:-false}"
}

# 该函数仅保留作参考，不在运行路径中调用；保留兼容思路（模板复制 + 兜底默认）
# 实际策略：尊重用户配置文件，不主动覆盖
config_apply_setting_defaults() {
	# 描述：按模板复制 -> 覆盖用户已设置的值 -> 为缺失键填默认值 -> 原子替换
	# 复制模板
	cp /aria2/conf/setting.conf "${SETTING_FILE}.new"
	# 应用用户设置
	[[ -n "${RMTASK}" ]] && kv_set "${SETTING_FILE}.new" remove-task "${RMTASK}"
	[[ -n "${MOVE}" ]] && kv_set "${SETTING_FILE}.new" move-task "${MOVE}"
	[[ -n "${CF}" ]] && kv_set "${SETTING_FILE}.new" content-filter "${CF}"
	[[ -n "${DET}" ]] && kv_set "${SETTING_FILE}.new" delete-empty-dir "${DET}"
	[[ -n "${TOR}" ]] && kv_set "${SETTING_FILE}.new" handle-torrent "${TOR}"
	[[ -n "${RRT}" ]] && kv_set "${SETTING_FILE}.new" remove-repeat-task "${RRT}"
	[[ -n "${MPT}" ]] && kv_set "${SETTING_FILE}.new" move-paused-task "${MPT}"

	# 兜底默认值，防止缺项
	[[ -z "${RMTASK}" ]] && kv_set "${SETTING_FILE}.new" remove-task rmaria
	[[ -z "${MOVE}" ]] && kv_set "${SETTING_FILE}.new" move-task false
	[[ -z "${CF}" ]] && kv_set "${SETTING_FILE}.new" content-filter false
	[[ -z "${DET}" ]] && kv_set "${SETTING_FILE}.new" delete-empty-dir true
	[[ -z "${TOR}" ]] && kv_set "${SETTING_FILE}.new" handle-torrent backup-rename
	[[ -z "${RRT}" ]] && kv_set "${SETTING_FILE}.new" remove-repeat-task true
	[[ -z "${MPT}" ]] && kv_set "${SETTING_FILE}.new" move-paused-task false

	mv "${SETTING_FILE}.new" "${SETTING_FILE}"
}
