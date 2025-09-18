#!/usr/bin/env bash
# =============================================================================
# 文件系统操作模块 - 安全的文件移动、删除和空间检查
# 设计哲学：安全第一，原子操作，详细日志
# =============================================================================

# 文件操作错误代码
readonly FS_ERROR_SPACE=20
readonly FS_ERROR_PERMISSION=21
readonly FS_ERROR_EXISTS=22
readonly FS_ERROR_MOVE_FAILED=23

# 最小剩余空间阈值（字节）
readonly MIN_FREE_SPACE_BYTES=$((1024 * 1024 * 1024))  # 1GB

# 确保目录存在
# 参数: DIRECTORY [PERMISSIONS]
# 返回: 0表示成功，非0表示失败
ensure_dir() {
    local dir="$1"
    local perms="${2:-755}"
    
    if [[ -z "$dir" ]]; then
        log_error "确保目录存在：目录路径不能为空"
        return $E_FILE_ERROR
    fi
    
    # 如果目录已存在，检查权限
    if [[ -d "$dir" ]]; then
        log_debug "目录已存在: $dir"
        return 0
    fi
    
    # 创建目录
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY_RUN] 将创建目录: $dir"
        return 0
    fi
    
    if mkdir -p "$dir"; then
        chmod "$perms" "$dir" 2>/dev/null || true
        log_debug "目录创建成功: $dir"
        return 0
    else
        log_error "目录创建失败: $dir"
        return $FS_ERROR_PERMISSION
    fi
}

# 检查磁盘空间
# 参数: TARGET_PATH REQUIRED_SIZE
# 返回: 0表示空间足够，非0表示空间不足
check_disk_space() {
    local target_path="$1"
    local required_size="$2"
    
    # 如果没有指定所需大小，尝试从源路径获取
    if [[ -z "$required_size" && -n "$SOURCE_PATH" ]]; then
        required_size=$(get_path_size "$SOURCE_PATH")
    fi
    
    # 如果仍然无法确定大小，跳过检查
    if [[ -z "$required_size" || "$required_size" -eq 0 ]]; then
        log_debug "无法确定所需空间大小，跳过空间检查"
        return 0
    fi
    
    # 获取目标路径的父目录
    local target_dir
    if [[ -d "$target_path" ]]; then
        target_dir="$target_path"
    else
        target_dir="$(dirname "$target_path")"
    fi
    
    # 检查磁盘可用空间
    local available_space
    available_space=$(df -B1 "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [[ -z "$available_space" ]]; then
        log_warn "无法获取磁盘空间信息: $target_dir"
        return 0
    fi
    
    local needed_space=$((required_size + MIN_FREE_SPACE_BYTES))
    
    log_debug "空间检查: 可用=$(human_readable_size "$available_space"), 需要=$(human_readable_size "$needed_space")"
    
    if [[ $available_space -lt $needed_space ]]; then
        log_error "磁盘空间不足: 可用$(human_readable_size "$available_space"), 需要$(human_readable_size "$needed_space")"
        return $FS_ERROR_SPACE
    fi
    
    return 0
}

# 获取路径大小（字节）
# 参数: PATH
# 返回: 路径大小（字节）
get_path_size() {
    local path="$1"
    
    if [[ ! -e "$path" ]]; then
        echo "0"
        return
    fi
    
    if [[ -f "$path" ]]; then
        stat -c%s "$path" 2>/dev/null || echo "0"
    elif [[ -d "$path" ]]; then
        du -sb "$path" 2>/dev/null | cut -f1 || echo "0"
    else
        echo "0"
    fi
}

# 检查设备是否相同（判断是否跨文件系统移动）
# 参数: PATH1 PATH2
# 返回: 0表示同设备，1表示跨设备
is_same_device() {
    local path1="$1"
    local path2="$2"
    
    local device1
    local device2
    
    device1=$(stat -c%d "$path1" 2>/dev/null)
    device2=$(stat -c%d "$(dirname "$path2")" 2>/dev/null)
    
    [[ -n "$device1" && -n "$device2" && "$device1" == "$device2" ]]
}

# 安全移动文件/目录
# 参数: SOURCE DESTINATION
# 返回: 0表示成功，非0表示失败
safe_mv() {
    local source="$1"
    local destination="$2"
    
    if [[ -z "$source" || -z "$destination" ]]; then
        log_error "安全移动：源路径和目标路径不能为空"
        return $E_FILE_ERROR
    fi
    
    if [[ ! -e "$source" ]]; then
        log_error "安全移动：源路径不存在 - $source"
        return $E_FILE_ERROR
    fi
    
    # 确保目标目录存在
    local target_dir="$(dirname "$destination")"
    if ! ensure_dir "$target_dir"; then
        return $FS_ERROR_PERMISSION
    fi
    
    # 检查磁盘空间
    local source_size
    source_size=$(get_path_size "$source")
    if ! check_disk_space "$destination" "$source_size"; then
        # 空间不足，尝试移动到失败目录
        local fail_dir="${DOWNLOAD_PATH}/move-failed"
        log_warn "目标磁盘空间不足，尝试移动到失败目录: $fail_dir"
        
        ensure_dir "$fail_dir"
        local fail_destination="$fail_dir/$(basename "$source")"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY_RUN] 将移动到失败目录: $source -> $fail_destination"
            return 0
        fi
        
        if mv "$source" "$fail_destination"; then
            log_move "因目标磁盘空间不足，已将文件移动至: $source -> $fail_destination"
            return 0
        else
            log_error "移动到失败目录也失败: $source"
            return $FS_ERROR_MOVE_FAILED
        fi
    fi
    
    # 检查目标是否已存在
    local final_destination="$destination"
    if [[ -d "$destination" ]]; then
        final_destination="$destination/$(basename "$source")"
    fi
    
    if [[ -e "$final_destination" ]]; then
        log_warn "目标已存在，生成新名称: $final_destination"
        local counter=1
        local base_name="$(basename "$final_destination")"
        local dir_name="$(dirname "$final_destination")"
        
        while [[ -e "$dir_name/${base_name}_$counter" ]]; do
            ((counter++))
        done
        final_destination="$dir_name/${base_name}_$counter"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY_RUN] 将移动文件: $source -> $final_destination"
        return 0
    fi
    
    # 执行移动操作
    if is_same_device "$source" "$final_destination"; then
        # 同设备，使用mv（原子操作）
        log_debug "同设备移动: $source -> $final_destination"
        if mv "$source" "$final_destination"; then
            log_move "文件移动成功: $source -> $final_destination"
            return 0
        else
            log_error "文件移动失败: $source -> $final_destination"
            return $FS_ERROR_MOVE_FAILED
        fi
    else
        # 跨设备，使用复制+删除
        log_debug "跨设备移动: $source -> $final_destination"
        if cp -a "$source" "$final_destination" && rm -rf "$source"; then
            log_move "文件跨设备移动成功: $source -> $final_destination"
            return 0
        else
            log_error "文件跨设备移动失败: $source -> $final_destination"
            # 清理可能的部分复制
            [[ -e "$final_destination" ]] && rm -rf "$final_destination"
            return $FS_ERROR_MOVE_FAILED
        fi
    fi
}

# 安全删除文件/目录
# 参数: PATH
# 返回: 0表示成功，非0表示失败
safe_rm() {
    local path="$1"
    
    if [[ -z "$path" ]]; then
        log_error "安全删除：路径不能为空"
        return $E_FILE_ERROR
    fi
    
    if [[ ! -e "$path" ]]; then
        log_debug "删除目标不存在，跳过: $path"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY_RUN] 将删除: $path"
        return 0
    fi
    
    # 执行删除
    if rm -rf "$path"; then
        log_delete "文件删除成功: $path"
        return 0
    else
        log_error "文件删除失败: $path"
        return $FS_ERROR_MOVE_FAILED
    fi
}

# 移动到回收站
# 参数: SOURCE
# 返回: 0表示成功，非0表示失败
move_to_recycle() {
    local source="$1"
    
    if [[ -z "$source" ]]; then
        log_error "移动到回收站：源路径不能为空"
        return $E_FILE_ERROR
    fi
    
    if [[ ! -e "$source" ]]; then
        log_error "移动到回收站：源路径不存在 - $source"
        return $E_FILE_ERROR
    fi
    
    # 设置回收站目录
    set_recycle_target
    local recycle_path="$RECYCLE_DIR/$(basename "$source")"
    
    # 确保回收站目录存在
    ensure_dir "$RECYCLE_DIR"
    
    # 如果回收站中已存在同名文件，添加时间戳
    if [[ -e "$recycle_path" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        recycle_path="${RECYCLE_DIR}/$(basename "$source")_$timestamp"
    fi
    
    if safe_mv "$source" "$recycle_path"; then
        log_recycle "文件已移动到回收站: $source -> $recycle_path"
        return 0
    else
        log_error "移动到回收站失败: $source"
        
        # 回收站移动失败，尝试直接删除
        log_warn "回收站移动失败，尝试直接删除: $source"
        if safe_rm "$source"; then
            log_recycle "移动到回收站失败，已直接删除: $source"
            return 0
        else
            log_error "移动到回收站和直接删除都失败: $source"
            return $FS_ERROR_MOVE_FAILED
        fi
    fi
}

# 删除空目录
# 参数: DIRECTORY
# 返回: 0表示成功，非0表示失败
remove_empty_dir() {
    local dir="$1"
    
    if [[ -z "$dir" ]]; then
        return 0
    fi
    
    if [[ ! -d "$dir" ]]; then
        return 0
    fi
    
    # 检查目录是否为空
    if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY_RUN] 将删除空目录: $dir"
            return 0
        fi
        
        if rmdir "$dir" 2>/dev/null; then
            log_delete "空目录删除成功: $dir"
            
            # 递归删除父级空目录
            local parent_dir
            parent_dir="$(dirname "$dir")"
            if [[ "$parent_dir" != "$DOWNLOAD_PATH" && "$parent_dir" != "/" ]]; then
                remove_empty_dir "$parent_dir"
            fi
            
            return 0
        else
            log_debug "空目录删除失败（可能不为空）: $dir"
            return 1
        fi
    fi
    
    return 0
}

# 清理.aria2控制文件
# 参数: BASE_PATH
clean_aria2_files() {
    local base_path="$1"
    
    if [[ -z "$base_path" ]]; then
        return 0
    fi
    
    local aria2_file="${base_path}.aria2"
    
    if [[ -f "$aria2_file" ]]; then
        safe_rm "$aria2_file"
    fi
}

# 兼容旧接口的函数
MOVE_FILE() {
    if [[ "$MOVE" == "false" ]]; then
        clean_aria2_files "$SOURCE_PATH"
        return 0
    elif [[ "$MOVE" == "dmof" && "$DOWNLOAD_DIR" == "$DOWNLOAD_PATH" && "$FILE_NUM" -eq 1 ]]; then
        clean_aria2_files "$SOURCE_PATH"
        return 0
    elif [[ "$MOVE" == "true" || "$MOVE" == "dmof" ]]; then
        set_completed_target
        calculate_target_path
        safe_mv "$SOURCE_PATH" "$TARGET_PATH"
        clean_aria2_files "$SOURCE_PATH"
    fi
}

DELETE_FILE() {
    safe_rm "$SOURCE_PATH"
}

MOVE_RECYCLE() {
    move_to_recycle "$SOURCE_PATH"
}

RM_ARIA2() {
    clean_aria2_files "$SOURCE_PATH"
}

DELETE_EMPTY_DIR() {
    if [[ "$DET" == "true" && -n "$SOURCE_PATH" ]]; then
        local parent_dir
        parent_dir="$(dirname "$SOURCE_PATH")"
        remove_empty_dir "$parent_dir"
    fi
}

# 文件系统操作模块加载完成标志
export ARIA2_FSOPS_LOADED="true"