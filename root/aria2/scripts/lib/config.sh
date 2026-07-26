#!/usr/bin/env bash
# 脚本配置库：读取和回写 /config/setting.conf
# setting.conf 控制移动、删除、过滤、种子处理等行为，用户可在 WebUI 里修改
# 本文件在被 source 时会自动调用 LOAD_CONF，把配置值注入到全局变量

SETTING_CONF="/config/setting.conf"

# 配置项定义数组，每项格式：配置文件 key:全局变量名:默认值
# 新增配置项只需在这里追加，LOAD_CONF / SED_CONF 自动处理
declare -a CONFIG_ITEMS=(
    "remove-task:RMTASK:rmaria"       # 停止任务后的处理方式：rmaria(仅移除aria2任务) / recycle(回收站) / delete(彻底删除)
    "move-task:MOVE:false"            # 是否自动移动已完成任务到 completed 目录：false / true / dmof(根目录单文件不移动)
    "content-filter:CF:false"         # 是否启用文件内容过滤（按扩展名/关键字删除不需要的文件）
    "delete-empty-dir:DET:true"       # 过滤后是否自动删除空文件夹
    "handle-torrent:TOR:backup-rename" # 种子文件处理方式：retain(保留) / delete(删除) / rename(重命名) / backup(备份) / backup-rename(重命名并备份)
    "remove-repeat-task:RRT:true"     # 是否自动删除重复任务（开始下载时发现 completed 目录已存在同名文件夹则取消）
    "move-paused-task:MPT:false"      # 是否在任务暂停时也移动文件到 completed 目录
)

# 从 setting.conf 读取配置并注入全局变量
# 文件不存在或对应 key 缺失时使用默认值
LOAD_CONF() {
    for config_item in "${CONFIG_ITEMS[@]}"; do
        IFS=':' read -r key var_name default_value <<< "$config_item"
        local value=""
        [ -f "${SETTING_CONF}" ] && value="$(grep "^${key}=" "${SETTING_CONF}" 2>/dev/null | cut -d= -f2-)"
        declare -g "${var_name}"="${value:-${default_value}}"
    done
}

# 将当前全局变量值回写到 setting.conf（升级镜像时合并新模板用）
# 用临时文件保证原子性；任意一条 sed 失败则整体回滚
# 值中的 sed 元字符（反斜杠、&、分隔符 |）逐一转义，避免新增配置项值含特殊字符时炸裂
SED_CONF() {
    cp /aria2/conf/setting.conf /config/setting.conf.new
    local failed=0 key var_name default_value escaped
    for config_item in "${CONFIG_ITEMS[@]}"; do
        IFS=':' read -r key var_name default_value <<< "$config_item"
        escaped=$(printf '%s' "${!var_name}" | sed -e 's/[\&|]/\\&/g')
        sed -i "s|^\(${key}=\).*|\1${escaped}|" /config/setting.conf.new || failed=1
    done
    if [ "${failed}" -eq 0 ]; then
        if ! mv -f /config/setting.conf.new /config/setting.conf; then
            echo "错误: 无法替换配置" >&2
            rm -f /config/setting.conf.new
            return 1
        fi
    else
        echo "错误: 无法更新配置" >&2
        rm -f /config/setting.conf.new
        return 1
    fi
}

# source 本文件时立即加载配置（使变量在后续函数中可用）
LOAD_CONF
