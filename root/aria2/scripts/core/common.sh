#!/usr/bin/with-contenv bash
#====================================================================
# common.sh
# 初始化脚本的公共函数库
#====================================================================

set -eo pipefail  # 发生错误时退出
shopt -s nullglob # 空通配符不报错

# 加载已重构的核心模块
source /aria2/scripts/core/logging.sh

# 定义固定的目录结构
declare -A SYSTEM_DIRS=(
    [CONFIG_DIR]="/config"
    [CONFIG_SSL]="/config/ssl"
    [CONFIG_LOGS]="/config/logs"
    [CONFIG_BACKUP]="/config/backup-torrent"
    [DOWNLOADS_DIR]="/downloads"
    [DOWNLOADS_COMPLETED]="/downloads/completed"
    [DOWNLOADS_RECYCLE]="/downloads/recycle"
    [WEBUI_DIR]="/www"
)

# 定义配置文件路径
declare -A CONFIG_FILES=(
    [ARIA2_CONF]="/config/aria2.conf"
    [ARIA2_CONF_DEFAULT]="/aria2/conf/aria2.conf.default"
    [SETTING_CONF]="/config/setting.conf"
    [SETTING_CONF_DEFAULT]="/aria2/conf/setting.conf"
    [FILTER_CONF]="/config/文件过滤.conf"
    [FILTER_CONF_DEFAULT]="/aria2/conf/文件过滤.conf"
)

# 定义日志文件
declare -A LOG_FILES=(
    [MOVE_LOG]="move.log"
    [RECYCLE_LOG]="recycle.log"
    [DELETE_LOG]="delete.log"
    [FILTER_LOG]="文件过滤日志.log"
)

# 创建目录
create_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            log_error "创建目录失败: $dir"
            return 1
        }
        log_info "已创建目录: $dir"
    fi
}

# 复制配置文件
copy_config() {
    local src="$1"
    local dest="$2"
    
    if [[ ! -f "$dest" ]]; then
        cp "$src" "$dest" || {
            log_error "复制配置文件失败: $src -> $dest"
            return 1
        }
        log_info "已复制配置文件: $src -> $dest"
    fi
}

# 设置文件/目录权限
set_owner() {
    local path="$1"
    local user="$2"
    local group="$3"
    local perms="$4"
    
    chown "$user:$group" "$path" || {
        log_error "设置所有者失败: $path"
        return 1
    }
    
    if [[ -n "$perms" ]]; then
        chmod "$perms" "$path" || {
            log_error "设置权限失败: $path"
            return 1
        }
    fi
    
    log_info "已设置权限: $path"
}

# 创建空文件
touch_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        touch "$file" || {
            log_error "创建文件失败: $file"
            return 1
        }
        log_info "已创建文件: $file"
    fi
}

# 更新配置值
update_conf_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    sed -i "s@^${key}=.*@${key}=${value}@" "$file" || {
        log_error "更新配置失败: $key=$value"
        return 1
    }
}

# 检查必需的环境变量
check_env() {
    local var="$1"
    if [[ -z "${!var}" ]]; then
        log_error "必需的环境变量未设置: $var"
        return 1
    fi
}

# 运行命令并检查结果
run_cmd() {
    local cmd="$1"
    local desc="$2"
    
    if ! eval "$cmd"; then
        log_error "$desc 失败"
        return 1
    fi
    log_info "$desc 成功"
}

# 检查进程是否运行
check_process() {
    local name="$1"
    pgrep -f "$name" >/dev/null
}