#!/usr/bin/env bash
#====================================================================
# config.sh
# 负责加载和写入配置项
#====================================================================

source "$(dirname "$0")/logging.sh"

# 加载setting.conf配置文件
load_setting_conf() {
    local config_file="/config/setting.conf"
    
    # 读取配置项
    RMTASK="$(grep ^remove-task "${config_file}" | cut -d= -f2-)"
    MOVE="$(grep ^move-task "${config_file}" | cut -d= -f2-)"
    CF="$(grep ^content-filter "${config_file}" | cut -d= -f2-)"
    DET="$(grep ^delete-empty-dir "${config_file}" | cut -d= -f2-)"
    TOR="$(grep ^handle-torrent "${config_file}" | cut -d= -f2-)"
    RRT="$(grep ^remove-repeat-task "${config_file}" | cut -d= -f2-)"
    MPT="$(grep ^move-paused-task "${config_file}" | cut -d= -f2-)"

    # 验证配置项
    validate_setting_conf
}

# 验证配置值并设置默认值
validate_setting_conf() {
    # remove-task 默认值: rmaria
    [[ -z "${RMTASK}" ]] && RMTASK="rmaria"
    
    # move-task 默认值: false
    [[ -z "${MOVE}" ]] && MOVE="false"
    
    # content-filter 默认值: false
    [[ -z "${CF}" ]] && CF="false"
    
    # delete-empty-dir 默认值: true
    [[ -z "${DET}" ]] && DET="true"
    
    # handle-torrent 默认值: backup-rename
    [[ -z "${TOR}" ]] && TOR="backup-rename"
    
    # remove-repeat-task 默认值: true
    [[ -z "${RRT}" ]] && RRT="true"
    
    # move-paused-task 默认值: false
    [[ -z "${MPT}" ]] && MPT="false"
}

# 加载文件过滤配置
load_filter_conf() {
    local filter_conf="/config/文件过滤.conf"

    MIN_SIZE="$(grep ^min-size "${filter_conf}" | cut -d= -f2-)"
    INCLUDE_FILE="$(grep ^include-file "${filter_conf}" | cut -d= -f2-)"
    EXCLUDE_FILE="$(grep ^exclude-file "${filter_conf}" | cut -d= -f2-)"
    KEYWORD_FILE="$(grep ^keyword-file "${filter_conf}" | cut -d= -f2-)"
    INCLUDE_FILE_REGEX="$(grep ^include-file-regex "${filter_conf}" | cut -d= -f2-)"
    EXCLUDE_FILE_REGEX="$(grep ^exclude-file-regex "${filter_conf}" | cut -d= -f2-)"
}

# 更新配置文件
update_setting_conf() {
    local new_conf="/config/setting.conf.new"
    
    # 复制模板配置文件
    cp "/aria2/conf/setting.conf" "${new_conf}"
    
    # 更新配置值
    sed -i "s@^\(remove-task=\).*@\1${RMTASK}@" "${new_conf}"
    sed -i "s@^\(move-task=\).*@\1${MOVE}@" "${new_conf}"
    sed -i "s@^\(content-filter=\).*@\1${CF}@" "${new_conf}"
    sed -i "s@^\(delete-empty-dir=\).*@\1${DET}@" "${new_conf}"
    sed -i "s@^\(handle-torrent=\).*@\1${TOR}@" "${new_conf}"
    sed -i "s@^\(remove-repeat-task=\).*@\1${RRT}@" "${new_conf}"
    sed -i "s@^\(move-paused-task=\).*@\1${MPT}@" "${new_conf}"

    # 原子性替换配置文件
    mv "${new_conf}" "/config/setting.conf"
}

# 初始化基础路径
init_paths() {
    # Aria2下载目录
    DOWNLOAD_PATH="/downloads"
    
    # 种子备份目录
    BAK_TORRENT_DIR="/config/backup-torrent"
    
    # 日志文件路径
    MOVE_LOG="/config/logs/move.log"
    DELETE_LOG="/config/logs/delete.log"
    RECYCLE_LOG="/config/logs/recycle.log" 
    FILTER_LOG="/config/logs/文件过滤日志.log"
}

# 加载所有配置
init_config() {
    init_paths
    load_setting_conf
    load_filter_conf
}

# 当直接运行此脚本时执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_config
fi