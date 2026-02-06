#!/usr/bin/env bash
# Copyright (c) 2018-2020 P3TERX <https://p3terx.com>

. "$(dirname "$0")/tracker_common"

ADD_TRACKERS_RPC() {
    if [[ "${SECRET}" ]]; then
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"NG6","params":["token:'${SECRET}'",{"bt-tracker":"'${TRACKER}'"}]}'
    else
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.changeGlobalOption","id":"NG6","params":[{"bt-tracker":"'${TRACKER}'"}]}'
    fi
    curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}"
}

ADD_TRACKERS_RPC_STATUS() {
    RPC_RESULT=$(ADD_TRACKERS_RPC)
    [[ $(echo "${RPC_RESULT}" | grep OK) ]] &&
        echo -e "$(DATE_TIME) ${INFO} BT trackers successfully added to Aria2 !" ||
        echo -e "$(DATE_TIME) ${ERROR} Network failure or Aria2 RPC interface error!"
}

RPC_ADDRESS="localhost:${PORT}/jsonrpc"
GET_TRACKERS
ECHO_TRACKERS
ADD_TRACKERS_RPC
ADD_TRACKERS_RPC_STATUS
