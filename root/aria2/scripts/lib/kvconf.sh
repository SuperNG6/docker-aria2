#!/usr/bin/env bash
# 通用 kv 配置文件操作（key=value，允许 key\s*=\s*value）
# 提供 upsert：存在则替换，不存在则追加到文件末尾。
# 约定：不改变文件中其他内容的顺序；仅单行键操作。

set -euo pipefail

# conf_upsert_kv <file> <key> <value>
conf_upsert_kv() {
	local file="$1" key="$2" value="$3"
	# 若文件不存在，直接创建
	if [[ ! -f "$file" ]]; then
		printf '%s=%s\n' "$key" "$value" >"$file"
		return 0
	fi
	# 匹配 key[space]*=[space]*
	if grep -Eq "^${key}[[:space:]]*=" "$file"; then
		# 使用 sed 兼容空白的替换
		# shellcheck disable=SC2016
		sed -i "s@^${key}[[:space:]]*=.*@${key}=${value}@" "$file"
	else
		printf '%s=%s\n' "$key" "$value" >>"$file"
	fi
}

# conf_upsert_path <file> <key> </path/value>
# 用于包含路径的值，避免 sed 中出现分隔符冲突，仍使用 @ 作为 sed 分隔符
conf_upsert_path() {
	conf_upsert_kv "$@"
}
