#!/usr/bin/env bash
#====================================================================
# stop.sh
# 处理下载任务停止时的操作
#====================================================================

# 加载依赖模块
script_dir=$(dirname "$0")
source "${script_dir}/../core/logging.sh"
source "${script_dir}/../core/config.sh"
source "${script_dir}/../core/rpc.sh"
source "${script_dir}/../core/functions.sh"

# 获取传入的参数
TASK_GID="$1"
FILE_NUM="$2"
FILE_PATH="$3"

# 停止处理函数
handle_stop() {
    # 加载基础配置
    init_config
    
    # 获取下载目录
    RECYCLE_PATH    # 设置回收站为目标目录
    
    # 获取RPC信息
    get_rpc_info "${TASK_GID}" || {
        log_error "获取RPC信息失败"
        exit 1
    }
    
    # 获取最终路径
    get_final_path
    
    # 验证任务参数
    if [[ ${FILE_NUM} -eq 0 || -z "${FILE_PATH}" ]]; then
        exit 0
    fi
    
    # 检查路径信息
    if [[ "${GET_PATH_INFO}" == "error" ]]; then
        log_error "GID:${TASK_GID} GET TASK PATH ERROR!"
        exit 1
    fi
    
    # 根据配置处理停止任务
    if [[ "${RMTASK}" == "recycle" && "${TASK_STATUS}" != "error" ]]; then
        move_to_recycle
        check_torrent
        remove_aria2_file "${SOURCE_PATH}"
    elif [[ "${RMTASK}" == "delete" && "${TASK_STATUS}" != "error" ]]; then
        delete_file
        check_torrent
        remove_aria2_file "${SOURCE_PATH}"
    elif [[ "${RMTASK}" == "rmaria" && "${TASK_STATUS}" != "error" ]]; then
        check_torrent
        remove_aria2_file "${SOURCE_PATH}"
    fi
}

# 执行主流程
main() {
    # 检查源路径是否存在
    if [[ -d "${SOURCE_PATH}" || -e "${SOURCE_PATH}" ]]; then
        handle_stop
    fi
}

main