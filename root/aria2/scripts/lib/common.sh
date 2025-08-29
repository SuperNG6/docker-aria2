#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091
# 通用函数库（被 handlers、utils 等多处复用）
# 职责：
#   - 提供统一的工具函数：打印面板、容错执行、KV 配置读写、跨盘空间预检、路径拼接与相对路径计算、调试输出。
#   - 约定输入输出：尽量通过参数传递与标准输出返回结果，必要时读/写全局变量（与其他 lib 协作）。
#   - 一次性加载保护：避免重复 source 带来的函数/变量覆盖与性能浪费。
# 兼容性：仅依赖 BusyBox/Alpine 常见命令（grep/sed/awk/df/du/stat 等），适配容器环境。

# 防止重复加载
if [[ -n "${_ARIA2_LIB_COMMON_SH_LOADED:-}" ]]; then
	return 0
fi
#
# panel
# 描述：打印分割面板与可选内容，用于关键阶段的人类可读输出。
# 参数：
#   $1  标题（必填）
#   $2..N  可选：追加打印的多行内容
# 返回：无（stdout 打印）
_ARIA2_LIB_COMMON_SH_LOADED=1

# 引入统一日志库
. /aria2/scripts/lib/logger.sh

# 打印分割面板
panel() {
	local title="$1"
	shift || true
	#
	# try_run
	# 描述：安全执行命令，发生错误不 exit，中转返回码给调用方自行处理。
	# 参数：
	#   $@  需要执行的命令与参数
	# 返回：命令的实际退出码
	echo -e "==============================================================================="
	echo -e "${title}"
	echo -e "==============================================================================="
	[[ "$#" -gt 0 ]] && echo -e "$*"
}
#
# kv_get
# 描述：从 key=value 结构文件中读取某个键的值（取首个匹配），不处理空格与转义。
# 参数：
#   $1  文件路径（必须存在）
#   $2  键名（不含 =）
# 返回：将值写到 stdout；读取失败返回码非 0

# 安全执行：出错也继续，但返回码可被外层获取
try_run() {
	"$@"
	return $?
}
#
# kv_set
# 描述：在 key=value 结构文件中安全地写入键值。若键存在则替换，不存在则追加。
# 参数：
#   $1  文件路径（不存在将创建）
#   $2  键名
#   $3  值（原样写入，不做转义）
# 返回：0 表示写入成功

# 读文件键值对：key=value（不带空格）
# 入参：$1 配置文件路径；$2 键名
# 返回：将值输出到标准输出
kv_get() {
	# $1: file, $2: key
	[[ -f "$1" ]] || return 1
	grep -E "^$2=" "${1}" | sed -E 's/^([^=]+)=//'
}

# 以 sed 安全替换 key=value（若键不存在则追加）
#
# check_space_before_move
# 描述：在“跨磁盘/分区移动”前进行空间校验；同设备移动则直接放行。
# 参数：
#   $1  源路径（文件或目录）
#   $2  目标目录
# 返回：
#   0 -> 空间充足或同一设备；1 -> 目标空间不足
# 副作用：必要时创建目标目录；通过日志输出提示信息。
# 入参：$1 配置文件路径；$2 键名；$3 值
kv_set() {
	# $1: file, $2: key, $3: value
	local f="$1" k="$2" v="$3"
	touch "${f}"
	if grep -qE "^${k}=" "${f}"; then
		sed -i "s@^\(${k}=\).*@\\1${v}@" "${f}"
	else
		echo "${k}=${v}" >>"${f}"
	fi
}

# 磁盘空间检查（移动前建议调用）
# 功能：当源与目标不在同一文件系统时，预估源大小并检测目标可用空间。
# 入参：$1 源路径（文件或目录）；$2 目标目录。
# 返回：0 表示空间充足或为同分区移动；1 表示目标空间不足。
check_space_before_move() {
	# $1: source_path $2: target_dir
	local sp="$1" td="$2"
	
	# Docker环境下的基础检查：确保源文件和目标目录可访问
	if [[ ! -e "${sp}" ]]; then
		log_e "源文件不存在: ${sp}"
		return 1
	fi
	
	mkdir -p "${td}" || {
		log_e "无法创建目标目录: ${td}"
		return 1
	}
	
	local sdev tdev req avail
	# Docker环境下，这些命令通常是可靠的，但添加基础错误处理
	sdev=$(stat -c %d "${sp}" 2>/dev/null) || {
		log_w "无法获取源设备信息，跳过空间检查"
		return 0
	}
	tdev=$(stat -c %d "${td}" 2>/dev/null) || {
		log_w "无法获取目标设备信息，跳过空间检查"
		return 0
	}
	req=$(du -sb "${sp}" 2>/dev/null | awk '{print $1}') || {
		log_w "无法获取源文件大小，跳过空间检查"
		return 0
	}
	avail=$(df --output=avail -B1 "${td}" 2>/dev/null | sed '1d') || {
		log_w "无法获取目标可用空间，跳过空间检查"
		return 0
	}

	if [[ "${sdev}" != "${tdev}" ]]; then
		log_i "检测到跨磁盘移动，检查目标磁盘空间..."
	else
		log_i "检查目标磁盘空间..."
	fi

	if [[ "${avail}" -lt "${req}" ]]; then
		local req_g avail_g
		req_g=$(awk "BEGIN {printf \"%.2f\", ${req}/1024/1024/1024}")
		avail_g=$(awk "BEGIN {printf \"%.2f\", ${avail}/1024/1024/1024}")
		log_e "目标磁盘空间不足，所需: ${req_g}GB，可用: ${avail_g}GB"
		# 仅在空间不足时设置全局变量供调用方使用
		REQ_SPACE_BYTES="${req}"
		AVAIL_SPACE_BYTES="${avail}"
		return 1
	fi
	log_i "目标磁盘空间充足。"
	# 空间充足时清空变量，避免状态混乱
	REQ_SPACE_BYTES=""
	AVAIL_SPACE_BYTES=""
	return 0
}

# 路径拼接（去除多余斜杠）
# 入参：base 基准路径；subpath 子路径
# 返回：拼接后的路径
path_join() {
	#
	# _dbg
	# 描述：仅当 DEBUG=1 时输出调试日志到 stderr。
	# 参数：
	#   $@  任意要输出的内容
	# 返回：无
	# 用法: path_join base subpath
	local base="$1" sub="$2"
	if [[ -z "${base}" ]]; then
		echo "${sub}"
		return
	fi
	if [[ -z "${sub}" ]]; then
		echo "${base}"
		return
	fi
	echo "${base%/}/${sub#/}"
}

# 获取相对路径（去除前缀 base/）
# 入参：$1 base 基准路径；$2 full 完整路径
# 返回：full 相对 base 的子路径
relative_path() {
	# $1: base $2: full
	local base="$1" full="$2"
	echo "${full#"${base%/}/"}"
}

# 仅在 DEBUG=1 时输出
_dbg() {
	[[ "${DEBUG:-0}" = "1" ]] && echo -e "[DBG] $*" >&2 || true
}
