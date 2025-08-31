#!/usr/bin/env bash
# 完整演示版：模拟file_ops.sh在各种场景下的输出效果

echo "🎬 Docker Aria2 文件操作库 - 输出效果演示"
echo "============================================="
echo

# 设置颜色变量以展示彩色输出
LOG_RED="\033[31m"
LOG_GREEN="\033[1;32m" 
LOG_YELLOW="\033[1;33m"
LOG_CYAN="\033[36m"
LOG_PURPLE="\033[1;35m"
LOG_BOLD="\033[1m"
LOG_NC="\033[0m"

now() { date +"%Y/%m/%d %H:%M:%S"; }
INFO="[${LOG_GREEN}INFO${LOG_NC}]"
ERROR="[${LOG_RED}ERROR${LOG_NC}]"
WARN="[${LOG_YELLOW}WARN${LOG_NC}]"

echo "📋 场景演示目录："
echo "  1️⃣  单文件移动任务"
echo "  2️⃣  多文件移动任务（带过滤）"
echo "  3️⃣  删除任务文件"
echo "  4️⃣  回收站移动"
echo "  5️⃣  磁盘空间不足处理"
echo "  6️⃣  移动失败重试"
echo "  7️⃣  种子文件处理"
echo

# ==================== 场景1：单文件移动任务 ====================
echo "1️⃣  场景1: 单文件移动任务"
echo "================================================"

echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${LOG_GREEN}: 移动任务文件${LOG_NC} ${LOG_YELLOW}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} /downloads
${LOG_PURPLE}任务位置:${LOG_NC} /downloads/[Movie] Avatar.2009.BluRay.1080p.mkv
${LOG_PURPLE}首个文件位置:${LOG_NC} /downloads/[Movie] Avatar.2009.BluRay.1080p.mkv
${LOG_PURPLE}任务文件数量:${LOG_NC} 1
${LOG_PURPLE}移动至目标文件夹:${LOG_NC} /downloads/completed
------------------------------------------------------------------------------------------"

echo -e "$(now) ${INFO} 已删除文件: /downloads/[Movie] Avatar.2009.BluRay.1080p.mkv.aria2"
echo -e "$(now) ${INFO} 开始移动该任务文件到: ${LOG_GREEN}/downloads/completed${LOG_NC}"
echo -e "$(now) ${INFO} 检测为同磁盘移动，无需检查空间。"
echo -e "$(now) ${INFO} 已移动文件至目标文件夹: /downloads/[Movie] Avatar.2009.BluRay.1080p.mkv -> /downloads/completed"
echo -e "$(now) ${INFO} 成功移动文件到目标目录: /downloads/[Movie] Avatar.2009.BluRay.1080p.mkv -> /downloads/completed" | tee -a /dev/null
echo

# ==================== 场景2：多文件移动任务（带过滤） ====================
echo "2️⃣  场景2: 多文件移动任务（带过滤）"
echo "================================================"

echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${LOG_GREEN}: 移动任务文件${LOG_NC} ${LOG_YELLOW}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} /downloads
${LOG_PURPLE}任务位置:${LOG_NC} /downloads/The.Matrix.1999.BluRay.1080p
${LOG_PURPLE}首个文件位置:${LOG_NC} /downloads/The.Matrix.1999.BluRay.1080p/The.Matrix.1999.BluRay.1080p.mkv
${LOG_PURPLE}任务文件数量:${LOG_NC} 8
${LOG_PURPLE}移动至目标文件夹:${LOG_NC} /downloads/completed
------------------------------------------------------------------------------------------"

echo -e "$(now) ${INFO} 已删除文件: /downloads/The.Matrix.1999.BluRay.1080p.aria2"
echo -e "$(now) ${INFO} 被过滤文件的任务路径: /downloads/The.Matrix.1999.BluRay.1080p"
echo -e "$(now) ${INFO} 删除不需要的文件..."
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/readme.txt'"
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/sample.mkv'"
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/movie.nfo'"
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/debug.log'"
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/small_file.tmp'"
echo -e "$(now) ${INFO} 删除任务中空的文件夹 ..."
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/extras'"
echo -e "$(now) ${INFO} 开始移动该任务文件到: ${LOG_GREEN}/downloads/completed${LOG_NC}"
echo -e "$(now) ${INFO} 检测为同磁盘移动，无需检查空间。"
echo -e "$(now) ${INFO} 已移动文件至目标文件夹: /downloads/The.Matrix.1999.BluRay.1080p -> /downloads/completed"
echo -e "$(now) ${INFO} 成功移动文件到目标目录: /downloads/The.Matrix.1999.BluRay.1080p -> /downloads/completed" | tee -a /dev/null
echo

# ==================== 场景3：删除任务文件 ====================
echo "3️⃣  场景3: 删除任务文件"
echo "================================================"

echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${LOG_RED}: 删除任务文件${LOG_NC} ${LOG_YELLOW}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} /downloads
${LOG_PURPLE}任务位置:${LOG_NC} /downloads/Corrupted.Download.2024
${LOG_PURPLE}首个文件位置:${LOG_NC} /downloads/Corrupted.Download.2024/movie.part1.rar
${LOG_PURPLE}任务文件数量:${LOG_NC} 3
------------------------------------------------------------------------------------------"

echo -e "$(now) ${INFO} 下载已停止，开始删除文件..."
echo -e "$(now) ${INFO} 删除文件夹中的所有文件:"
echo "removed '/downloads/Corrupted.Download.2024/movie.part1.rar'"
echo "removed '/downloads/Corrupted.Download.2024/movie.part2.rar'"
echo "removed '/downloads/Corrupted.Download.2024/movie.part3.rar'"
echo -e "$(now) ${INFO} 已删除文件: /downloads/Corrupted.Download.2024"
echo -e "$(now) ${INFO} 文件删除成功: /downloads/Corrupted.Download.2024" | tee -a /dev/null
echo -e "$(now) ${INFO} 已删除文件: /downloads/Corrupted.Download.2024.aria2"
echo

# ==================== 场景4：回收站移动 ====================
echo "4️⃣  场景4: 回收站移动"
echo "================================================"

echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${LOG_GREEN}: 移动任务文件至回收站${LOG_NC} ${LOG_YELLOW}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} /downloads
${LOG_PURPLE}任务位置:${LOG_NC} /downloads/Old.TV.Show.S01E01.mkv
${LOG_PURPLE}首个文件位置:${LOG_NC} /downloads/Old.TV.Show.S01E01.mkv
${LOG_PURPLE}任务文件数量:${LOG_NC} 1
${LOG_PURPLE}移动至目标文件夹:${LOG_NC} /downloads/recycle
------------------------------------------------------------------------------------------"

echo -e "$(now) ${INFO} 开始移动已下载的任务至回收站 ${LOG_GREEN}/downloads/recycle${LOG_NC}"
echo -e "$(now) ${INFO} 已移至回收站: /downloads/Old.TV.Show.S01E01.mkv -> /downloads/recycle"
echo -e "$(now) ${INFO} 成功移动文件到回收站: /downloads/Old.TV.Show.S01E01.mkv -> /downloads/recycle" | tee -a /dev/null
echo

# ==================== 场景5：磁盘空间不足处理 ====================
echo "5️⃣  场景5: 磁盘空间不足处理"
echo "================================================"

echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${LOG_GREEN}: 移动任务文件${LOG_NC} ${LOG_YELLOW}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} /downloads
${LOG_PURPLE}任务位置:${LOG_NC} /downloads/Large.Movie.4K.2024
${LOG_PURPLE}首个文件位置:${LOG_NC} /downloads/Large.Movie.4K.2024/movie.mkv
${LOG_PURPLE}任务文件数量:${LOG_NC} 1
${LOG_PURPLE}移动至目标文件夹:${LOG_NC} /mnt/storage/completed
------------------------------------------------------------------------------------------"

echo -e "$(now) ${INFO} 已删除文件: /downloads/Large.Movie.4K.2024.aria2"
echo -e "$(now) ${INFO} 开始移动该任务文件到: ${LOG_GREEN}/mnt/storage/completed${LOG_NC}"
echo -e "$(now) ${INFO} 检测到跨磁盘移动，正在检查目标磁盘空间..."
echo -e "$(now) ${ERROR} 目标磁盘空间不足，所需: 45.67GB，可用: 12.34GB"
echo -e "$(now) ${ERROR} 目标磁盘空间不足，移动失败。所需空间:45.67 GB, 可用空间:12.34 GB. 源:/downloads/Large.Movie.4K.2024 -> 目标:/mnt/storage/completed" | tee -a /dev/null
echo -e "$(now) ${WARN} 尝试将任务移动到: /downloads/move-failed"
echo -e "$(now) ${INFO} 因目标磁盘空间不足，已将文件移动至: /downloads/Large.Movie.4K.2024 -> /downloads/move-failed"
echo -e "$(now) ${INFO} 因目标磁盘空间不足，已将文件移动至: /downloads/Large.Movie.4K.2024 -> /downloads/move-failed" | tee -a /dev/null
echo

# ==================== 场景6：移动失败重试 ====================
echo "6️⃣  场景6: 移动失败重试"
echo "================================================"

echo -e "
-------------------------- [${LOG_YELLOW} 任务信息 ${LOG_GREEN}: 移动任务文件${LOG_NC} ${LOG_YELLOW}] --------------------------
${LOG_PURPLE}根下载路径:${LOG_NC} /downloads
${LOG_PURPLE}任务位置:${LOG_NC} /downloads/Problem.File.2024.mkv
${LOG_PURPLE}首个文件位置:${LOG_NC} /downloads/Problem.File.2024.mkv
${LOG_PURPLE}任务文件数量:${LOG_NC} 1
${LOG_PURPLE}移动至目标文件夹:${LOG_NC} /downloads/completed
------------------------------------------------------------------------------------------"

echo -e "$(now) ${INFO} 已删除文件: /downloads/Problem.File.2024.mkv.aria2"
echo -e "$(now) ${INFO} 开始移动该任务文件到: ${LOG_GREEN}/downloads/completed${LOG_NC}"
echo -e "$(now) ${INFO} 检测为同磁盘移动，无需检查空间。"
echo -e "$(now) ${ERROR} 文件移动失败: /downloads/Problem.File.2024.mkv"
echo -e "$(now) ${ERROR} 文件移动失败: /downloads/Problem.File.2024.mkv" | tee -a /dev/null
echo -e "$(now) ${INFO} 已将文件移动至: /downloads/Problem.File.2024.mkv -> /downloads/move-failed"
echo -e "$(now) ${INFO} 已将文件移动至: /downloads/Problem.File.2024.mkv -> /downloads/move-failed" | tee -a /dev/null
echo

# ==================== 场景7：种子文件处理 ====================
echo "7️⃣  场景7: 种子文件处理"
echo "================================================"

echo "📁 种子文件处理策略演示："
echo
echo "策略: retain (保留)"
echo -e "$(now) ${INFO} 种子已保留: [Movie]_Avatar_2009.torrent -> /downloads/completed"

echo
echo "策略: delete (删除)"
echo -e "$(now) ${INFO} 已删除种子文件: /downloads/The.Matrix.1999.torrent"
echo -e "$(now) ${INFO} 种子已删除: The.Matrix.1999.torrent -> /downloads/completed"

echo
echo "策略: rename (重命名)"
echo -e "$(now) ${INFO} 已重命名种子文件: /downloads/random_hash.torrent -> The.Matrix.1999.torrent"
echo -e "$(now) ${INFO} 种子已重命名: The.Matrix.1999.torrent -> /downloads/completed"

echo
echo "策略: backup (备份)"
echo -e "$(now) ${INFO} 备份种子文件: /downloads/random_hash.torrent"
echo "'/downloads/random_hash.torrent' -> '/config/backup-torrent/random_hash.torrent'"
echo -e "$(now) ${INFO} 种子已备份: random_hash.torrent -> /config/backup-torrent"

echo
echo "策略: backup-rename (重命名并备份)"
echo -e "$(now) ${INFO} 重命名并备份种子文件: /config/backup-torrent/The.Matrix.1999.torrent"
echo -e "$(now) ${INFO} 种子已重命名并备份: The.Matrix.1999.torrent -> /config/backup-torrent"
echo

# ==================== 日志文件示例 ====================
echo "📊 生成的日志文件示例："
echo "================================================"

echo
echo "📄 移动日志 (/config/logs/move.log):"
echo "--------------------------------------------"
echo "$(now) [INFO] 成功移动文件到目标目录: /downloads/[Movie] Avatar.2009.BluRay.1080p.mkv -> /downloads/completed"
echo "$(now) [INFO] 成功移动文件到目标目录: /downloads/The.Matrix.1999.BluRay.1080p -> /downloads/completed"
echo "$(now) [ERROR] 目标磁盘空间不足，移动失败。所需空间:45.67 GB, 可用空间:12.34 GB. 源:/downloads/Large.Movie.4K.2024 -> 目标:/mnt/storage/completed"
echo "$(now) [INFO] 因目标磁盘空间不足，已将文件移动至: /downloads/Large.Movie.4K.2024 -> /downloads/move-failed"
echo "$(now) [ERROR] 文件移动失败: /downloads/Problem.File.2024.mkv"
echo "$(now) [INFO] 已将文件移动至: /downloads/Problem.File.2024.mkv -> /downloads/move-failed"

echo
echo "📄 删除日志 (/config/logs/delete.log):"
echo "--------------------------------------------"
echo "$(now) [INFO] 文件删除成功: /downloads/Corrupted.Download.2024"

echo
echo "📄 回收站日志 (/config/logs/recycle.log):"
echo "--------------------------------------------"
echo "$(now) [INFO] 成功移动文件到回收站: /downloads/Old.TV.Show.S01E01.mkv -> /downloads/recycle"

echo
echo "📄 文件过滤日志 (/config/logs/文件过滤日志.log):"
echo "--------------------------------------------"
echo "$(now) [INFO] 被过滤文件的任务路径: /downloads/The.Matrix.1999.BluRay.1080p"
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/readme.txt'"
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/sample.mkv'"
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/movie.nfo'"
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/debug.log'"
echo "removed '/downloads/The.Matrix.1999.BluRay.1080p/small_file.tmp'"

echo
echo "📄 种子处理日志 (/config/logs/torrent.log):"
echo "--------------------------------------------"
echo "$(now) [INFO] 种子已保留: [Movie]_Avatar_2009.torrent -> /downloads/completed"
echo "$(now) [INFO] 种子已删除: The.Matrix.1999.torrent -> /downloads/completed"
echo "$(now) [INFO] 种子已重命名: The.Matrix.1999.torrent -> /downloads/completed"
echo "$(now) [INFO] 种子已备份: random_hash.torrent -> /config/backup-torrent"
echo "$(now) [INFO] 种子已重命名并备份: The.Matrix.1999.torrent -> /config/backup-torrent"

echo
echo "📁 目录结构示例："
echo "================================================"
cat << 'EOF'
/downloads/
├── completed/
│   ├── [Movie] Avatar.2009.BluRay.1080p.mkv
│   └── The.Matrix.1999.BluRay.1080p/
│       ├── The.Matrix.1999.BluRay.1080p.mkv
│       └── subtitles/
├── recycle/
│   └── Old.TV.Show.S01E01.mkv
└── move-failed/
    ├── Large.Movie.4K.2024/
    └── Problem.File.2024.mkv

/config/
├── logs/
│   ├── move.log
│   ├── delete.log
│   ├── recycle.log
│   ├── torrent.log
│   └── 文件过滤日志.log
└── backup-torrent/
    ├── random_hash.torrent
    └── The.Matrix.1999.torrent
EOF

echo
echo "🔧 核心功能特性："
echo "================================================"
echo "✅ 自动删除 .aria2 控制文件"
echo "✅ 智能文件过滤（按大小、扩展名、关键词）"
echo "✅ 跨磁盘空间检查"
echo "✅ 移动失败自动重试"
echo "✅ 完整的日志记录"
echo "✅ 彩色控制台输出"
echo "✅ 多种种子文件处理策略"
echo "✅ 错误恢复机制"
echo "✅ 目录结构保持"

echo
echo "🎯 适用场景："
echo "================================================"
echo "• 🎬 电影下载完成后自动整理"
echo "• 📺 电视剧批量管理"
echo "• 🗑️  失败任务自动清理"
echo "• ♻️   文件误删恢复（回收站）"
echo "• 💾 磁盘空间管理"
echo "• 🔍 内容过滤和清理"

echo
echo "✨ 演示完成！这就是 file_ops.sh 在实际使用中的输出效果。"
