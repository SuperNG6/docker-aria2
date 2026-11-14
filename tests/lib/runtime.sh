#!/usr/bin/env bash
# 容器内 RPC 辅助；不加载生产库，也不推导生产任务路径。
rpc() {
    local method=$1 params=${2:-[]} response
    response=$(jq -nc --arg method "${method}" --arg secret "${SECRET}" --argjson params "${params}" \
        '{jsonrpc:"2.0",id:"test",method:$method,params:(["token:"+$secret]+$params)}' \
        | curl -fsSk --connect-timeout 1 --max-time 3 "${RPC_URL:-http://127.0.0.1:${PORT}/jsonrpc}" \
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
# 删除等待队列中的任务（如已暂停）后 aria2 不保留记录，tellStatus 会直接报错；
# 改为确认任务已离开活动与等待队列。
not_queued() {
    local gid=$1 active waiting
    active=$(rpc aria2.tellActive '[["gid"]]') || return 1
    waiting=$(rpc aria2.tellWaiting '[0,1000,["gid"]]') || return 1
    ! jq -e --arg gid "${gid}" 'any(.result[]; .gid == $gid)' <<< "${active}" >/dev/null \
        && ! jq -e --arg gid "${gid}" 'any(.result[]; .gid == $gid)' <<< "${waiting}" >/dev/null
}
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
    local out=$1 options=${2:-'{}'} params response
    params=$(jq -nc --arg out "${out}" --argjson options "${options}" \
        '[["http://127.0.0.1:8080/index.html"],({"out":$out,"dir":"/downloads"}+$options)]') || return 1
    response=$(rpc aria2.addUri "${params}") || return 1
    jq -er '.result | select(length == 16)' <<< "${response}"
}
complete_fixture() {
    assert '创建 BT 目录' mkdir -p /downloads/fixture-task
    assert '准备 BT 文件' cp "${TESTS}/fixtures/keep.mp4" "${TESTS}/fixtures/remove.txt" /downloads/fixture-task/
}
# complex.torrent 的内容：根目录与文件名含中文、方括号、逗号、单引号和空格。
COMPLEX_TASK="[字幕组] 名字 Vol.1, 测试's"
complex_fixture() {
    local root="/downloads/${COMPLEX_TASK}"
    assert '创建复杂路径目录' mkdir -p "${root}/Season 1/Extras" "${root}/Season 2"
    printf 'EPISODE1\n' > "${root}/Season 1/第01集 [1080p].mkv"
    printf 'README\n' > "${root}/Season 1/Extras/说明.txt"
    printf 'EPISODE2\n' > "${root}/Season 2/第01集.mkv"
}
torrent_hash() {
    aria2c -S "${TESTS}/fixtures/$1.torrent" | sed -n 's/^Info Hash: //p'
}
# 离线提供 peer：容器内另起一个 aria2c 做种，再由 WebUI 的静态文件充当 tracker，
# 其响应固定返回 127.0.0.1:51413。只为让磁力任务拿到元数据，不测试 aria2 的下载实现。
start_seeder() {
    assert '准备做种目录' mkdir -p /tmp/seed/fixture-task
    assert '准备做种文件' cp "${TESTS}/fixtures/keep.mp4" "${TESTS}/fixtures/remove.txt" /tmp/seed/fixture-task/
    assert '启动做种端' aria2c --no-conf -D -d /tmp/seed --listen-port=51413 --enable-rpc=false \
        --enable-dht=false --bt-enable-lpd=false --enable-peer-exchange=false \
        --seed-ratio=0 --seed-time=60 -V "${TESTS}/fixtures/multi.torrent"
    printf 'd8:intervali60e5:peers6:\x7f\x00\x00\x01\xc8\xd5e' > /www/announce
}
# peer.torrent：根目录 peer-task，4 个 512 KiB 文件，announce 指向上面的静态 tracker。
# 其余夹具只有十几个字节且没有 peer，"活动任务"始终零进度；本夹具由做种端真实供数，
# 用限速让任务停在"已有进度、尚未完成"的状态，覆盖 aria2 会回写控制文件的那段时间。
PEER_FILES=(a.bin b.bin sub/c.bin sub/d.bin)
peer_content() {
    # 进程替换而非管道：yes 被 SIGPIPE 结束不应让 pipefail 判定失败。
    head -c 524288 < <(yes "peer-fixture $1")
}
seeder_listening() { (exec 3<>/dev/tcp/127.0.0.1/51413) 2>/dev/null; }
# $1 为做种端上传限速，0 表示不限速。
start_peer_seeder() {
    local limit=$1 file
    assert '准备做种目录' mkdir -p /tmp/seed/peer-task/sub
    for file in "${PEER_FILES[@]}"; do
        peer_content "${file}" > "/tmp/seed/peer-task/${file}"
    done
    assert '启动做种端' aria2c --no-conf -D -d /tmp/seed --listen-port=51413 --enable-rpc=false \
        --enable-dht=false --bt-enable-lpd=false --enable-peer-exchange=false \
        --seed-ratio=0 --seed-time=60 --max-overall-upload-limit="${limit}" \
        -V "${TESTS}/fixtures/peer.torrent"
    printf 'd8:intervali60e5:peers6:\x7f\x00\x00\x01\xc8\xd5e' > /www/announce
    eventually 15 '做种端开始监听' seeder_listening
}
completed_length() {
    rpc aria2.tellStatus "[\"$1\",[\"completedLength\"]]" | jq -er '.result.completedLength'
}
has_progress() {
    local length
    length=$(completed_length "$1") || return 1
    ((length > 0))
}
add_magnet() {
    local hash=$1 params response
    params=$(jq -nc --arg uri "magnet:?xt=urn:btih:${hash}&tr=http://127.0.0.1:8080/announce" \
        '[[$uri],{"dir":"/downloads","enable-dht":"false","bt-enable-lpd":"false"}]') || return 1
    response=$(rpc aria2.addUri "${params}") || return 1
    jq -er '.result | select(length == 16)' <<< "${response}"
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
