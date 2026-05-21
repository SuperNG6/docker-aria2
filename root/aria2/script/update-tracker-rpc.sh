#!/usr/bin/env bash
#
# 通过 Aria2 RPC 接口动态更新 BT trackers（无需重启容器）
# 由 cron 定时调用（rpc-tracker1 配置文件中设定）

_D="$(dirname "$0")/lib"
. "${_D}/log.sh"
. "${_D}/tracker.sh"

GET_TRACKERS
ECHO_TRACKERS

RPC_ADDRESS="localhost:${PORT}/jsonrpc"

if [[ "${SECRET}" ]]; then
    RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"NG6","params":["token:'${SECRET}'",{"bt-tracker":"'${TRACKER}'"}]}'
else
    RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"NG6","params":[{"bt-tracker":"'${TRACKER}'"}]}'
fi

RPC_RESULT=$(curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}")

[[ $(echo "${RPC_RESULT}" | grep OK) ]] && \
    echo -e "$(DATE_TIME) ${INFO} BT trackers 更新成功!" || \
    echo -e "$(DATE_TIME) ${ERROR} 网络故障或 Aria2 RPC 接口错误!"
