#!/usr/bin/env bash
# =============================================================================
# 种子文件处理模块 - 种子文件的备份、重命名、删除操作
# 设计哲学：策略化处理，支持多种处理方式
# =============================================================================

# 种子处理策略常量
readonly TORRENT_RETAIN="retain"
readonly TORRENT_DELETE="delete" 
readonly TORRENT_RENAME="rename"
readonly TORRENT_BACKUP="backup"
readonly TORRENT_BACKUP_RENAME="backup-rename"

# 处理种子文件的主函数
# 参数: TASK_NAME TORRENT_FILE STRATEGY
# 返回: 0表示成功，非0表示失败
handle_torrent() {
    local task_name="$1"
    local torrent_file="$2"
    local strategy="${3:-$TORRENT_RETAIN}"
    
    # 检查种子文件是否存在
    if [[ ! -f "$torrent_file" ]]; then
        log_debug "种子文件不存在，跳过处理: $torrent_file"
        return 0
    fi
    
    # 确保任务名不为空
    if [[ -z "$task_name" ]]; then
        task_name="unknown_$(date +%s)"
        log_warn "任务名为空，使用默认名称: $task_name"
    fi
    
    # 确保备份目录存在
    ensure_dir "$BACKUP_TORRENT_DIR"
    
    log_debug "处理种子文件: $torrent_file, 策略: $strategy"
    
    case "$strategy" in
        "$TORRENT_RETAIN")
            _retain_torrent "$task_name" "$torrent_file"
            ;;
        "$TORRENT_DELETE")
            _delete_torrent "$task_name" "$torrent_file"
            ;;
        "$TORRENT_RENAME")
            _rename_torrent "$task_name" "$torrent_file"
            ;;
        "$TORRENT_BACKUP")
            _backup_torrent "$task_name" "$torrent_file"
            ;;
        "$TORRENT_BACKUP_RENAME")
            _backup_and_rename_torrent "$task_name" "$torrent_file"
            ;;
        *)
            log_warn "未知的种子处理策略: $strategy，使用保留策略"
            _retain_torrent "$task_name" "$torrent_file"
            ;;
    esac
}

# 保留种子文件（不做任何操作）
# 参数: TASK_NAME TORRENT_FILE
_retain_torrent() {
    local task_name="$1"
    local torrent_file="$2"
    
    log_debug "保留种子文件: $torrent_file"
    return 0
}

# 删除种子文件
# 参数: TASK_NAME TORRENT_FILE
_delete_torrent() {
    local task_name="$1"
    local torrent_file="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY_RUN] 将删除种子文件: $torrent_file"
        return 0
    fi
    
    if safe_rm "$torrent_file"; then
        log_info "种子文件删除成功: $torrent_file"
        return 0
    else
        log_error "种子文件删除失败: $torrent_file"
        return 1
    fi
}

# 重命名种子文件
# 参数: TASK_NAME TORRENT_FILE
_rename_torrent() {
    local task_name="$1"
    local torrent_file="$2"
    local torrent_dir
    local new_name
    
    torrent_dir="$(dirname "$torrent_file")"
    new_name="$(sanitize_filename "$task_name").torrent"
    local new_path="$torrent_dir/$new_name"
    
    # 如果新名称和原名称相同，跳过重命名
    if [[ "$torrent_file" == "$new_path" ]]; then
        log_debug "种子文件名无需更改: $torrent_file"
        return 0
    fi
    
    # 如果目标文件已存在，添加序号
    if [[ -f "$new_path" ]]; then
        local counter=1
        local base_name="${new_name%.torrent}"
        
        while [[ -f "$torrent_dir/${base_name}_${counter}.torrent" ]]; do
            ((counter++))
        done
        
        new_path="$torrent_dir/${base_name}_${counter}.torrent"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY_RUN] 将重命名种子文件: $torrent_file -> $new_path"
        return 0
    fi
    
    if mv "$torrent_file" "$new_path"; then
        log_info "种子文件重命名成功: $torrent_file -> $new_path"
        return 0
    else
        log_error "种子文件重命名失败: $torrent_file -> $new_path"
        return 1
    fi
}

# 备份种子文件
# 参数: TASK_NAME TORRENT_FILE
_backup_torrent() {
    local task_name="$1"
    local torrent_file="$2"
    local backup_name
    local backup_path
    
    backup_name="$(sanitize_filename "$task_name").torrent"
    backup_path="$BACKUP_TORRENT_DIR/$backup_name"
    
    # 如果备份文件已存在，添加时间戳
    if [[ -f "$backup_path" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local base_name="${backup_name%.torrent}"
        backup_path="$BACKUP_TORRENT_DIR/${base_name}_${timestamp}.torrent"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY_RUN] 将备份种子文件: $torrent_file -> $backup_path"
        return 0
    fi
    
    if cp "$torrent_file" "$backup_path"; then
        log_info "种子文件备份成功: $torrent_file -> $backup_path"
        return 0
    else
        log_error "种子文件备份失败: $torrent_file -> $backup_path"
        return 1
    fi
}

# 备份并重命名种子文件
# 参数: TASK_NAME TORRENT_FILE
_backup_and_rename_torrent() {
    local task_name="$1"
    local torrent_file="$2"
    
    # 先备份
    if ! _backup_torrent "$task_name" "$torrent_file"; then
        log_error "种子文件备份失败，跳过重命名"
        return 1
    fi
    
    # 再重命名
    _rename_torrent "$task_name" "$torrent_file"
}

# 根据INFO_HASH查找种子文件
# 参数: INFO_HASH DOWNLOAD_DIR
# 返回: 种子文件路径或空字符串
find_torrent_by_hash() {
    local info_hash="$1"
    local download_dir="$2"
    
    if [[ -z "$info_hash" || "$info_hash" == "null" ]]; then
        return 1
    fi
    
    local torrent_file="$download_dir/$info_hash.torrent"
    
    if [[ -f "$torrent_file" ]]; then
        echo "$torrent_file"
        return 0
    fi
    
    return 1
}

# 清理下载目录中的种子文件
# 参数: DOWNLOAD_DIR [PATTERN]
cleanup_torrent_files() {
    local download_dir="$1"
    local pattern="${2:-*.torrent}"
    
    if [[ ! -d "$download_dir" ]]; then
        log_warn "下载目录不存在，跳过种子文件清理: $download_dir"
        return 1
    fi
    
    local torrent_files
    torrent_files=$(find "$download_dir" -maxdepth 1 -name "$pattern" -type f 2>/dev/null)
    
    if [[ -z "$torrent_files" ]]; then
        log_debug "没有找到需要清理的种子文件: $download_dir"
        return 0
    fi
    
    local file
    local count=0
    
    while read -r file; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY_RUN] 将清理种子文件: $file"
            else
                if safe_rm "$file"; then
                    ((count++))
                fi
            fi
        fi
    done <<< "$torrent_files"
    
    if [[ $count -gt 0 ]]; then
        log_info "清理了 $count 个种子文件"
    fi
    
    return 0
}

# 验证种子文件完整性
# 参数: TORRENT_FILE
# 返回: 0表示有效，1表示无效
validate_torrent_file() {
    local torrent_file="$1"
    
    if [[ ! -f "$torrent_file" ]]; then
        return 1
    fi
    
    # 检查文件大小（种子文件通常不会很大）
    local file_size
    file_size=$(stat -c%s "$torrent_file" 2>/dev/null || echo "0")
    
    if [[ $file_size -eq 0 ]]; then
        log_warn "种子文件为空: $torrent_file"
        return 1
    fi
    
    if [[ $file_size -gt $((10 * 1024 * 1024)) ]]; then
        log_warn "种子文件过大（>10MB）: $torrent_file"
        return 1
    fi
    
    # 检查文件头（简单验证）
    local header
    header=$(head -c 10 "$torrent_file" 2>/dev/null | od -t x1 -A n | tr -d ' \n')
    
    # 种子文件通常以 'd' 开头（bencode格式）
    if [[ "$header" =~ ^64 ]]; then
        return 0
    else
        log_warn "种子文件格式可能无效: $torrent_file"
        return 1
    fi
}

# 获取种子文件信息
# 参数: TORRENT_FILE
# 输出: 种子文件的基本信息
get_torrent_info() {
    local torrent_file="$1"
    
    if ! validate_torrent_file "$torrent_file"; then
        log_error "无效的种子文件: $torrent_file"
        return 1
    fi
    
    echo "种子文件: $torrent_file"
    echo "文件大小: $(human_readable_size "$(stat -c%s "$torrent_file")")"
    echo "修改时间: $(stat -c%y "$torrent_file")"
    
    return 0
}

# 批量处理种子文件
# 参数: DIRECTORY STRATEGY
# 处理目录中的所有种子文件
batch_handle_torrents() {
    local directory="$1"
    local strategy="${2:-$TORRENT_RETAIN}"
    
    if [[ ! -d "$directory" ]]; then
        log_error "批量处理种子文件：目录不存在 - $directory"
        return 1
    fi
    
    local torrent_files
    torrent_files=$(find "$directory" -name "*.torrent" -type f 2>/dev/null)
    
    if [[ -z "$torrent_files" ]]; then
        log_debug "目录中没有种子文件: $directory"
        return 0
    fi
    
    local file
    local task_name
    local count=0
    
    while read -r file; do
        if [[ -f "$file" ]]; then
            task_name="$(basename "$file" .torrent)"
            if handle_torrent "$task_name" "$file" "$strategy"; then
                ((count++))
            fi
        fi
    done <<< "$torrent_files"
    
    log_info "批量处理了 $count 个种子文件"
    return 0
}

# 兼容旧接口的函数
HANDLE_TORRENT() {
    local strategy="${TOR:-retain}"
    handle_torrent "$TASK_NAME" "$TORRENT_FILE" "$strategy"
}

CHECK_TORRENT() {
    if [[ -e "$TORRENT_FILE" ]]; then
        HANDLE_TORRENT
    fi
}

# 种子处理模块加载完成标志
export ARIA2_TORRENT_LOADED="true"