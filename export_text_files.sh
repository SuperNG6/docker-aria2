#!/usr/bin/env bash

########################################################################
# 脚本名称: export_text_files.sh
# 作用    : 收集当前项目目录下的纯文本文件内容，汇总到 ALL.md
#
# 注意点：
#   1. 排除 .git, node_modules, vendor 等目录
#   2. 跳过 README.md
#   3. 跳过 ALL.md 自身(否则会不断读写自身导致无限膨胀)
#   4. 限制文件大小 <1MB，避免扫描到过大的文本
#   5. 只输出 MIME 为 text/ 的文件
########################################################################

DEBUG=true                   # 是否输出 DEBUG 日志
OUTPUT_FILE="ALL.md"         # 最终输出的 Markdown 文件
SIZE_LIMIT="-1M"            # 只处理<1MB的文件，可自行调节

EXCLUDE_DIRS=(
    "./.git/*"
    "./node_modules/*"
    "./vendor/*"
)
EXCLUDE_FILES=(
    "README.md"
    "ALL.md"       # 新增：排除脚本正在生成的 ALL.md 文件
)

debug_log() {
  if [ "$DEBUG" = true ]; then
    echo "[DEBUG] $*"
  fi
}

# 如果已存在同名文件，先删除
[ -f "$OUTPUT_FILE" ] && rm "$OUTPUT_FILE"
debug_log "删除已有的 $OUTPUT_FILE"

# 写入标题
echo "# 项目中文本文件汇总" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
debug_log "写入初始标题到 $OUTPUT_FILE"

# 构建 find 命令参数
FIND_CMD=( find . -type f )

# 排除目录
for d in "${EXCLUDE_DIRS[@]}"; do
    FIND_CMD+=( -not -path "$d" )
done

# 排除文件名
for f in "${EXCLUDE_FILES[@]}"; do
    FIND_CMD+=( -not -name "$f" )
done

# 如果设置了文件大小限制
if [ -n "$SIZE_LIMIT" ]; then
  FIND_CMD+=( -size "$SIZE_LIMIT" )
fi

FIND_CMD+=( -print )

debug_log "执行的 find 命令：${FIND_CMD[*]}"

# 开始遍历文件
"${FIND_CMD[@]}" | while IFS= read -r file
do
    debug_log "处理文件：$file"
    mime_info=$(file --mime-type "$file")
    if echo "$mime_info" | grep -q "text/"; then
        debug_log " -> 纯文本文件，添加到 $OUTPUT_FILE"
        echo "## 文件路径：\`$file\`" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "\`\`\`" >> "$OUTPUT_FILE"
        cat "$file" >> "$OUTPUT_FILE"
        echo "\`\`\`" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    else
        debug_log " -> 非文本，跳过"
    fi
done

debug_log "全部文件处理完成。"
echo "脚本执行完毕，所有符合条件的文本文件已汇总到 \`$OUTPUT_FILE\`。"
