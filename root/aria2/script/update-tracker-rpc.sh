#!/usr/bin/env bash
# 通过 Aria2 RPC 接口动态更新 BT tracker 列表（无需重启容器，立即生效）
# 由 cron 定时调用，调度配置见 /aria2/conf/rpc-tracker1（RUT=true 时启用）
# 每日凌晨 5 点执行一次（定时任务由 cont-init.d/30-config 配置）

_D="$(dirname "$0")/lib"
. "${_D}/log.sh"     # 颜色变量和 DATE_TIME
. "${_D}/tracker.sh" # GET_TRACKERS、ECHO_TRACKERS

GET_TRACKERS   # 从公共源或自定义地址拉取最新 tracker 列表
ECHO_TRACKERS  # 打印到终端，便于查看 cron 日志

# 构造 RPC 地址（PORT 由容器环境变量注入，默认 6800）
RPC_ADDRESS="localhost:${PORT}/jsonrpc"

# 用 jq 构造 payload：SECRET 或 TRACKER 中的 " \ 换行等字符会被正确转义，避免 JSON 解析失败
RPC_PAYLOAD=$(jq -nc \
    --arg secret "${SECRET}" \
    --arg tracker "${TRACKER}" \
    '{jsonrpc:"2.0",method:"aria2.changeGlobalOption",id:"NG6",
      params:(if $secret == ""
              then [{"bt-tracker": $tracker}]
              else ["token:" + $secret, {"bt-tracker": $tracker}]
              end)}')

# 发起 RPC 调用；优先 http，自动降级为 https（自签证书用 -k 跳过验证）
RPC_RESULT=$(curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}")

# 检查返回值中是否含 "OK"（aria2 成功响应的标志）
[[ $(echo "${RPC_RESULT}" | grep OK) ]] && \
    echo -e "$(DATE_TIME) ${INFO} BT trackers 更新成功!" || \
    echo -e "$(DATE_TIME) ${ERROR} 网络故障或 Aria2 RPC 接口错误!"
