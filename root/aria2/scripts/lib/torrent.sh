#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# 种子文件处理
# 职责：根据 setting.conf 的 handle-torrent 选项处理磁力保存的 .torrent 文件。
# 支持策略：retain/delete/rename/backup/backup-rename。

if [[ -n "${_ARIA2_LIB_TORRENT_SH_LOADED:-}" ]]; then
	return 0
fi
_ARIA2_LIB_TORRENT_SH_LOADED=1

. /aria2/scripts/lib/common.sh
. /aria2/scripts/lib/path.sh

handle_torrent() {
	# 描述：按 TOR 指定的策略处理 .torrent 文件
	# 依赖: TOR, TORRENT_FILE, TASK_NAME, BAK_TORRENT_DIR
	[[ -n "${TOR:-}" ]] || return 0
	[[ -n "${TORRENT_FILE:-}" ]] || return 0
	case "${TOR}" in
	retain)
		# 保留种子文件，不做处理
		log_torrent "种子已保留: $(basename "${TORRENT_FILE}") -> ${SAVE_PATH:-unknown}"
		;;
	delete)
		log_i "已删除种子文件: ${TORRENT_FILE}"
		rm -f "${TORRENT_FILE}"
		log_torrent "种子已删除: $(basename "${TORRENT_FILE}") -> ${SAVE_PATH:-unknown}"
		;;
	rename)
		log_i "已重命名种子文件: ${TORRENT_FILE} -> ${TASK_NAME}.torrent"
		mv -f "${TORRENT_FILE}" "$(dirname "${TORRENT_FILE}")/${TASK_NAME}.torrent"
		log_torrent "种子已重命名: ${TASK_NAME}.torrent -> ${SAVE_PATH:-unknown}"
		;;
	backup)
		log_i "备份种子文件: ${TORRENT_FILE}"
		mkdir -p "${BAK_TORRENT_DIR}" && mv -vf "${TORRENT_FILE}" "${BAK_TORRENT_DIR}"
		log_torrent "种子已备份: $(basename "${TORRENT_FILE}") -> ${BAK_TORRENT_DIR}"
		;;
	backup-rename)
		log_i "重命名并备份种子文件: ${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
		mkdir -p "${BAK_TORRENT_DIR}" && mv -f "${TORRENT_FILE}" "${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
		log_torrent "种子已重命名并备份: ${TASK_NAME}.torrent -> ${BAK_TORRENT_DIR}"
		;;
	*)
		:
		;;
	esac
}

check_torrent() { [[ -e "${TORRENT_FILE:-}" ]] && handle_torrent; } # 若存在 .torrent 文件才进行处理
