#!/usr/bin/env bash
# =============================================================================
# 路径处理模块 - 文件路径解析和计算
# 设计哲学：路径处理集中化，逻辑清晰，错误检测
# =============================================================================

# 路径相关常量
readonly DEFAULT_DOWNLOAD_PATH="/downloads"
readonly DEFAULT_COMPLETED_DIR="completed"
readonly DEFAULT_RECYCLE_DIR="recycle"  
readonly DEFAULT_BACKUP_TORRENT_DIR="/config/backup-torrent"

# 全局路径变量
DOWNLOAD_PATH=""
COMPLETED_DIR=""
RECYCLE_DIR=""
BACKUP_TORRENT_DIR=""

# 导出的路径信息变量
export SOURCE_PATH=""
export TARGET_PATH=""
export TASK_NAME=""
export GET_PATH_INFO=""

# 初始化路径配置
# 从环境变量或使用默认值设置路径
init_paths() {
    DOWNLOAD_PATH="${DOWNLOAD_PATH:-$DEFAULT_DOWNLOAD_PATH}"
    BACKUP_TORRENT_DIR="${BAK_TORRENT_DIR:-$DEFAULT_BACKUP_TORRENT_DIR}"
    
    # 确保必要目录存在
    mkdir -p "$DOWNLOAD_PATH"
    mkdir -p "$BACKUP_TORRENT_DIR"
    
    log_debug "路径配置初始化完成"
    log_debug "下载路径: $DOWNLOAD_PATH"
    log_debug "种子备份路径: $BACKUP_TORRENT_DIR"
}

# 设置目标目录为完成目录
set_completed_target() {
    COMPLETED_DIR="${DOWNLOAD_PATH}/${DEFAULT_COMPLETED_DIR}"
    TARGET_DIR="$COMPLETED_DIR"
    
    log_debug "目标目录设置为完成目录: $TARGET_DIR"
}

# 设置目标目录为回收站
set_recycle_target() {
    RECYCLE_DIR="${DOWNLOAD_PATH}/${DEFAULT_RECYCLE_DIR}"
    TARGET_DIR="$RECYCLE_DIR"
    
    log_debug "目标目录设置为回收站: $TARGET_DIR"
}

# 获取任务的源路径
# 参数: FILE_PATH
# 设置: SOURCE_PATH
get_source_path() {
    local file_path="$1"
    
    if [[ -z "$file_path" ]]; then
        log_error "获取源路径：文件路径不能为空"
        GET_PATH_INFO="error"
        return $E_PATH_ERROR
    fi
    
    SOURCE_PATH="$file_path"
    
    # 检查源路径是否存在
    if [[ ! -e "$SOURCE_PATH" ]]; then
        log_warn "源路径不存在: $SOURCE_PATH"
        GET_PATH_INFO="not_exist"
        return $E_PATH_ERROR
    fi
    
    log_debug "源路径: $SOURCE_PATH"
    return 0
}

# 计算目标路径
# 设置: TARGET_PATH
calculate_target_path() {
    if [[ -z "$SOURCE_PATH" || -z "$TARGET_DIR" ]]; then
        log_error "计算目标路径：源路径或目标目录未设置"
        GET_PATH_INFO="error"
        return $E_PATH_ERROR
    fi
    
    # 计算相对路径
    local relative_path="${SOURCE_PATH#"${DOWNLOAD_PATH}/"}"
    TARGET_PATH="${TARGET_DIR}/$(dirname "$relative_path")"
    
    # 检查路径计算是否成功
    if [[ "$TARGET_PATH" == "${TARGET_DIR}//" ]]; then
        log_error "目标路径计算失败，出现双斜杠"
        GET_PATH_INFO="error"
        return $E_PATH_ERROR
    fi
    
    # 处理根目录下载的情况
    if [[ "$TARGET_PATH" == "${TARGET_DIR}/." ]]; then
        TARGET_PATH="$TARGET_DIR"
    fi
    
    log_debug "目标路径: $TARGET_PATH"
    return 0
}

# 获取任务名称
# 参数: FILE_NUM FILE_PATH
# 设置: TASK_NAME
get_task_name() {
    local file_num="$1"
    local file_path="$2"
    
    if [[ "$file_num" -eq 1 ]]; then
        # 单文件任务：使用文件名（去除扩展名）作为任务名
        local filename
        filename="$(basename "$file_path")"
        TASK_NAME="${filename%.*}"
    else
        # 多文件任务：使用目录名作为任务名
        if [[ -d "$SOURCE_PATH" ]]; then
            TASK_NAME="$(basename "$SOURCE_PATH")"
        else
            # 如果不是目录，使用父目录名
            TASK_NAME="$(basename "$(dirname "$SOURCE_PATH")")"
        fi
    fi
    
    # 确保任务名不为空
    if [[ -z "$TASK_NAME" ]]; then
        TASK_NAME="unknown_task_$(date +%s)"
        log_warn "无法确定任务名，使用默认值: $TASK_NAME"
    fi
    
    log_debug "任务名称: $TASK_NAME"
}

# 计算完整的路径信息
# 参数: GID FILE_NUM FILE_PATH
# 设置: SOURCE_PATH, TARGET_PATH, TASK_NAME, GET_PATH_INFO
compute_paths() {
    local gid="$1"
    local file_num="$2" 
    local file_path="$3"
    
    # 重置状态
    GET_PATH_INFO=""
    SOURCE_PATH=""
    TARGET_PATH=""
    TASK_NAME=""
    
    # 参数验证
    if [[ -z "$gid" ]]; then
        log_error "计算路径：GID不能为空"
        GET_PATH_INFO="error"
        return $E_PATH_ERROR
    fi
    
    # 初始化路径配置
    init_paths
    
    # 获取RPC任务信息
    if ! get_task_info "$gid"; then
        log_error "计算路径：获取任务信息失败 GID=$gid"
        GET_PATH_INFO="error"
        return $E_RPC_ERROR
    fi
    
    # 处理特殊情况
    if [[ "$file_num" -eq 0 || -z "$file_path" ]]; then
        log_debug "文件数量为0或文件路径为空，跳过路径计算"
        GET_PATH_INFO="skip"
        return 0
    fi
    
    # 获取源路径
    if ! get_source_path "$file_path"; then
        return $E_PATH_ERROR
    fi
    
    # 获取任务名称
    get_task_name "$file_num" "$file_path"
    
    # 如果已设置目标目录，计算目标路径
    if [[ -n "$TARGET_DIR" ]]; then
        if ! calculate_target_path; then
            return $E_PATH_ERROR  
        fi
    fi
    
    GET_PATH_INFO="success"
    
    log_debug "路径计算完成："
    log_debug "  源路径: $SOURCE_PATH"
    log_debug "  目标路径: $TARGET_PATH"
    log_debug "  任务名: $TASK_NAME"
    
    return 0
}

# 检查路径是否在下载目录内
# 参数: PATH
# 返回: 0表示在内，1表示不在
is_path_in_download_dir() {
    local path="$1"
    local download_path="${DOWNLOAD_PATH:-$DEFAULT_DOWNLOAD_PATH}"
    
    # 规范化路径
    path="$(realpath "$path" 2>/dev/null || echo "$path")"
    download_path="$(realpath "$download_path" 2>/dev/null || echo "$download_path")"
    
    # 检查路径是否以下载目录开始
    [[ "$path" == "$download_path"* ]]
}

# 获取相对于下载目录的路径
# 参数: ABSOLUTE_PATH
# 返回: 相对路径
get_relative_path() {
    local absolute_path="$1"
    local download_path="${DOWNLOAD_PATH:-$DEFAULT_DOWNLOAD_PATH}"
    
    if is_path_in_download_dir "$absolute_path"; then
        echo "${absolute_path#"$download_path/"}"
    else
        echo "$absolute_path"
    fi
}

# 检查路径冲突
# 参数: SOURCE_PATH TARGET_PATH
# 返回: 0表示无冲突，1表示有冲突
check_path_conflict() {
    local source="$1"
    local target="$2"
    
    # 规范化路径
    source="$(realpath "$source" 2>/dev/null || echo "$source")"
    target="$(realpath "$target" 2>/dev/null || echo "$target")"
    
    if [[ "$source" == "$target" ]]; then
        log_warn "源路径和目标路径相同: $source"
        return 1
    fi
    
    # 检查目标路径是否已存在
    if [[ -e "$target/$(basename "$source")" ]]; then
        log_warn "目标位置已存在同名文件/目录: $target/$(basename "$source")"
        return 1
    fi
    
    return 0
}

# 生成安全的文件名（去除特殊字符）
# 参数: FILENAME
# 返回: 安全的文件名
sanitize_filename() {
    local filename="$1"
    
    # 替换或删除危险字符
    filename="${filename//[\/\\:*?\"<>|]/_}"
    filename="${filename//[[:cntrl:]]/_}"
    
    # 去除前后空格和点
    filename="${filename#"${filename%%[![:space:].]*}"}"
    filename="${filename%"${filename##*[![:space:].]*}"}"
    
    # 确保文件名不为空
    if [[ -z "$filename" ]]; then
        filename="unnamed_$(date +%s)"
    fi
    
    echo "$filename"
}

# 兼容旧接口的函数
GET_BASE_PATH() {
    init_paths
}

COMPLETED_PATH() {
    set_completed_target
}

RECYCLE_PATH() {
    set_recycle_target
}

GET_TARGET_PATH() {
    calculate_target_path
}

GET_FINAL_PATH() {
    compute_paths "$TASK_GID" "$FILE_NUM" "$FILE_PATH"
}

# 路径模块加载完成标志
export ARIA2_PATHS_LOADED="true"