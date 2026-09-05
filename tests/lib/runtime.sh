#!/usr/bin/env bash
# 容器内 RPC 辅助；不加载生产库，也不推导生产任务路径。
rpc() {
    local method=$1 params=${2:-[]} response
    response=$(jq -nc --arg method "${method}" --arg secret "${SECRET}" --argjson params "${params}" \
        '{jsonrpc:"2.0",id:"test",method:$method,params:(["token:"+$secret]+$params)}' \
        | curl -fsS --connect-timeout 1 --max-time 3 "http://127.0.0.1:${PORT}/jsonrpc" \
            -H 'Content-Type: application/json' --data-binary @-) || return 1
    if ! jq -e 'has("result") and (has("error") | not)' <<< "${response}" >/dev/null; then
        printf '%s\n' "${response}" >&2
        return 1
    fi
    printf '%s\n' "${response}"
}
status_is() {
    local gid=$1 expected=$2 response
    response=$(rpc aria2.tellStatus "[\"${gid}\"]") || return 1
    [ "$(jq -r '.result.status' <<< "${response}")" = "${expected}" ]
}
wait_status() { eventually 45 "GID $1 状态 $2" status_is "$1" "$2"; }
setting() {
    local key=$1 value=$2
    # 不接受任意 sed 表达式，场景只传入显式的配置键值。
    assert "设置 ${key}" sed -i "s/^${key}=.*/${key}=${value}/" /config/setting.conf
    assert "设置已落盘 ${key}" grep -Fxq "${key}=${value}" /config/setting.conf
}
add_torrent() {
    local fixture=$1 options=${2:-'{}'} payload response
    payload=$(jq -nc --arg data "$(base64 -w0 "${TESTS}/fixtures/${fixture}.torrent")" \
        --argjson options "${options}" '[$data,[],({"dir":"/downloads","seed-time":"0","file-allocation":"none","bt-enable-lpd":"false","enable-peer-exchange":"false"}+$options)]') || return 1
    response=$(rpc aria2.addTorrent "${payload}") || return 1
    jq -er '.result | select(length == 16)' <<< "${response}"
}
add_http() {
    local out=$1 params response
    params=$(jq -nc --arg out "${out}" '[["http://127.0.0.1:8080/index.html"],{"out":$out,"dir":"/downloads"}]') || return 1
    response=$(rpc aria2.addUri "${params}") || return 1
    jq -er '.result | select(length == 16)' <<< "${response}"
}
complete_fixture() {
    assert '创建 BT 目录' mkdir -p /downloads/fixture-task
    assert '准备 BT 文件' cp "${TESTS}/fixtures/keep.mp4" "${TESTS}/fixtures/remove.txt" /downloads/fixture-task/
}
sentinel() {
    assert '建立无关历史目录' mkdir -p /downloads/completed/history /downloads/sibling
    printf 'HISTORY\n' > /downloads/completed/history/sentinel
    printf 'SIBLING\n' > /downloads/sibling/sentinel
}
sentinels_unchanged() {
    equal HISTORY "$(cat /downloads/completed/history/sentinel)" '历史内容保持不变'
    equal SIBLING "$(cat /downloads/sibling/sentinel)" '兄弟任务保持不变'
}
owner_is_abc() {
    equal "$(id -u):$(id -g)" "$(stat -c '%u:%g' "$1")" "文件所有者 $1"
}
hook_idle() {
    # 已知 hook 的子进程也保留脚本命令行；等待整条执行链退出再断言静态结果。
    ! pgrep -f '^bash /aria2/scripts/(start|stop|pause|completed)\.sh( |$)' >/dev/null
}
