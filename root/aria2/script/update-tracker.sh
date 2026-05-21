#!/usr/bin/env bash
# BT tracker 列表更新脚本（双模式）
# 用法：update-tracker.sh [file|rpc] [aria2.conf 路径]
#   file（默认）- 把 tracker 列表写入 aria2.conf；由 cont-init.d/30-config 在启动时调用（UT=true）
#   rpc         - 通过 Aria2 JSON-RPC 动态更新 tracker，无需重启；由 cron 调用（RUT=true）
# aria2.conf 路径仅 file 模式使用，默认 /config/aria2.conf

_D="$(dirname "$0")/lib"
. "${_D}/log.sh"     # 颜色变量和 DATE_TIME
. "${_D}/tracker.sh" # GET_TRACKERS、ECHO_TRACKERS

# 把 tracker 列表写入 aria2.conf 的 bt-tracker 行
_update_file() {
    local conf=$1
    if [ ! -f "${conf}" ]; then
        echo -e "$(DATE_TIME) ${ERROR} '${conf}' 不存在"
        exit 1
    fi
    # 若 bt-tracker= 行尚不存在，先追加空行，确保 sed 能匹配
    grep -q "^bt-tracker=" "${conf}" || echo "bt-tracker=" >> "${conf}"
    sed -i "s@^\(bt-tracker=\).*@\1${TRACKER}@" "${conf}" && \
        echo -e "$(DATE_TIME) ${INFO} 成功添加 BT trackers 到 Aria2 配置文件中!"
}

# 通过 RPC 调用 aria2.changeGlobalOption 动态更新 tracker
# 优先 http，失败自动降级为 https（自签证书用 -k 跳过验证）
_update_rpc() {
    local addr="localhost:${PORT}/jsonrpc"
    local payload result
    # jq 构造 payload：SECRET / TRACKER 中的特殊字符会被正确转义
    payload=$(jq -nc \
        --arg secret "${SECRET}" \
        --arg tracker "${TRACKER}" \
        '{jsonrpc:"2.0",method:"aria2.changeGlobalOption",id:"NG6",
          params:(if $secret == ""
                  then [{"bt-tracker": $tracker}]
                  else ["token:" + $secret, {"bt-tracker": $tracker}]
                  end)}')
    result=$(curl "${addr}" -fsSd "${payload}" || curl "https://${addr}" -kfsSd "${payload}")
    if echo "${result}" | grep -q OK; then
        echo -e "$(DATE_TIME) ${INFO} BT trackers 更新成功!"
    else
        echo -e "$(DATE_TIME) ${ERROR} 网络故障或 Aria2 RPC 接口错误!"
    fi
}

GET_TRACKERS   # 从公共源或自定义地址（CTU 变量）拉取 tracker 列表
ECHO_TRACKERS  # 打印到终端，便于日志确认

case "${1:-file}" in
    file) _update_file "${2:-/config/aria2.conf}" ;;
    rpc)  _update_rpc ;;
    *)
        echo -e "$(DATE_TIME) ${ERROR} 未知模式: ${1}（应为 file 或 rpc）"
        exit 1
        ;;
esac
