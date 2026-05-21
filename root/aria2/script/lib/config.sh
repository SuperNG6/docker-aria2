#!/usr/bin/env bash

SCRIPT_CONF="/config/setting.conf"

declare -a CONFIG_ITEMS=(
    "remove-task:RMTASK:rmaria"
    "move-task:MOVE:false"
    "content-filter:CF:false"
    "delete-empty-dir:DET:true"
    "handle-torrent:TOR:backup-rename"
    "remove-repeat-task:RRT:true"
    "move-paused-task:MPT:false"
)

LOAD_CONF() {
    for config_item in "${CONFIG_ITEMS[@]}"; do
        IFS=':' read -r key var_name default_value <<< "$config_item"
        local value=""
        [ -f "${SCRIPT_CONF}" ] && value="$(grep "^${key}=" "${SCRIPT_CONF}" 2>/dev/null | cut -d= -f2-)"
        declare -g "${var_name}"="${value:-${default_value}}"
    done
}

SED_CONF() {
    cp /aria2/conf/setting.conf /config/setting.conf.new
    local failed=0
    for config_item in "${CONFIG_ITEMS[@]}"; do
        IFS=':' read -r key var_name default_value <<< "$config_item"
        sed -i "s@^\(${key}=\).*@\1${!var_name}@" /config/setting.conf.new || failed=1
    done
    if [ "${failed}" -eq 0 ]; then
        rm -f /config/setting.conf
        mv /config/setting.conf.new /config/setting.conf
    else
        echo "错误: 无法更新配置"
        rm -f /config/setting.conf.new
        return 1
    fi
}

LOAD_CONF
