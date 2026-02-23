#!/usr/bin/env bash
# Copyright (c) 2018-2020 P3TERX <https://p3terx.com>

. "$(dirname "$0")/tracker_common"

# 通过 RPC 把 trackers 写入 Aria2 全局选项。
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
    if echo "${RPC_RESULT}" | jq -e '.result == "OK"' >/dev/null 2>&1; then
        LOG_INFO "已成功将 BT trackers 更新到 Aria2！"
    else
        LOG_ERROR "更新 BT trackers 失败：网络异常或 Aria2 RPC 接口错误！"
    fi
}

RPC_ADDRESS="localhost:${PORT}/jsonrpc"
GET_TRACKERS \
    "https://trackerslist.com/all_aria2.txt" \
    "https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt" \
    "https://ghp.ci/https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/all_aria2.txt"
ECHO_TRACKERS
ADD_TRACKERS_RPC_STATUS
