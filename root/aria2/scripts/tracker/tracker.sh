#!/usr/bin/env bash
#====================================================================
# tracker.sh
# BT Tracker 更新管理脚本
#====================================================================

# 加载依赖模块
script_dir=$(dirname "$0")
source "${script_dir}/../core/logging.sh"
source "${script_dir}/../core/config.sh"
source "${script_dir}/../core/rpc.sh"

# 下载器配置
DOWNLOADER="curl -fsSL --connect-timeout 3 --max-time 3 --retry 2"

# Tracker源列表
TRACKER_SOURCES=(
    "https://trackerslist.com/all_aria2.txt"
    "https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt"
    "https://ghp.ci/https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/all_aria2.txt"
)

# 获取Tracker列表
get_trackers() {
    local tracker_list=""
    
    if [[ -n "${CTU}" ]]; then
        # 从自定义URL获取
        log_info "从自定义URL获取BT trackers: ${CTU}"
        local urls
        IFS=',' read -ra urls <<< "${CTU}"
        
        for url in "${urls[@]}"; do
            local response
            response=$("${DOWNLOADER}" "${url}")
            [[ -n "${response}" ]] && tracker_list+="${response}"$'\n'
        done
    else
        # 从默认源获取
        log_info "从默认源获取BT trackers..."
        
        for source in "${TRACKER_SOURCES[@]}"; do
            local response
            if response=$("${DOWNLOADER}" "${source}"); then
                tracker_list="${response}"
                break
            fi
        done
    fi
    
    # 验证获取结果
    if [[ -z "${tracker_list}" ]]; then
        log_error "无法获取trackers,网络错误或无效链接"
        return 1
    fi
    
    # 处理tracker列表格式
    if [[ -n "${CTU}" ]]; then
        # 自定义URL的结果需要处理格式
        echo "${tracker_list}" | awk NF | sort -u | sed 'H;1h;$!d;x;y/\n/,/'
    else
        # 默认源已经是正确格式
        echo "${tracker_list}"
    fi
}

# 显示Tracker列表
print_trackers() {
    local tracker_list="$1"
    echo -e "\n--------------------[BitTorrent Trackers]--------------------"
    echo "${tracker_list}"
    echo "--------------------[BitTorrent Trackers]--------------------\n"
}

# 通过配置文件更新Tracker
update_trackers_conf() {
    local tracker_list="$1"
    local aria2_conf="/config/aria2.conf"
    
    log_info "添加 BT trackers 到配置文件 ${aria2_conf}"
    
    if [[ ! -f "${aria2_conf}" ]]; then
        log_error "配置文件不存在: ${aria2_conf}"
        return 1
    fi
    
    # 确保配置项存在
    grep -q "^bt-tracker=" "${aria2_conf}" || echo "bt-tracker=" >> "${aria2_conf}"
    
    # 更新配置
    sed -i "s@^bt-tracker=.*@bt-tracker=${tracker_list}@" "${aria2_conf}"
    
    log_info "成功更新配置文件中的BT trackers!"
    return 0
}

# 更新Tracker的主函数
main() {
    # 获取Tracker列表
    local tracker_list
    tracker_list=$(get_trackers) || {
        log_error "获取Tracker列表失败"
        exit 1
    }
    
    # 显示Tracker列表
    print_trackers "${tracker_list}"
    
    # 根据更新方式选择更新方法
    if [[ "${RUT}" == "true" ]]; then
        # 通过RPC更新
        update_trackers "${tracker_list}" || {
            log_error "通过RPC更新Tracker失败"
            exit 1
        }
    else
        # 通过配置文件更新
        update_trackers_conf "${tracker_list}" || {
            log_error "更新配置文件失败"
            exit 1
        }
    fi
}

# 执行主函数
main

# 设置定时任务(如果需要)
if [[ "${RUT}" == "true" ]]; then
    cp /aria2/conf/rpc-tracker1 /etc/crontabs/root
    /usr/sbin/crond
else
    cp /aria2/conf/rpc-tracker0 /etc/crontabs/root
fi