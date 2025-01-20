#!/usr/bin/env bash
#====================================================================
# completed.sh
# 处理下载任务完成时的操作
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

# 完成处理函数
handle_complete() {
    # 加载基础配置
    init_config
    
    # 获取下载目录
    COMPLETED_PATH   # 设置完成目录为目标目录
    
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
    
    # 处理文件移动
    move_file
    
    # 处理种子文件
    check_torrent
}

# 执行主流程
handle_complete