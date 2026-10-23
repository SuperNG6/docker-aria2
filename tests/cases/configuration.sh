#!/usr/bin/env bash
identity() {
    local pid
    pid=$(pgrep -x aria2c)
    equal "$(id -u)" "$(stat -c %u "/proc/${pid}")" 'aria2 运行身份'
    assert '配置可写' test -w /config/setting.conf
    assert '下载目录可写' test -w /downloads
    assert '默认文件预分配' grep -Fxq file-allocation=falloc /config/aria2.conf
    assert '保存磁力元数据' grep -Fxq bt-save-metadata=true /config/aria2.conf
    local event script
    for event in start pause stop complete; do
        script=${event}
        [ "${event}" != complete ] || script=completed
        assert "注册 ${event} hook" grep -Fxq "on-download-${event}=/aria2/scripts/${script}.sh" /config/aria2.conf
    done
}
config_upgrade_prepare() {
    printf 'remove-task=recycle\nmove-task=dmof\n' > /config/setting.conf
    printf '\n# retained-by-upgrade-test\n' >> /config/aria2.conf
}
config_upgrade() {
    # 每一条断言独立失败，不让后面的键存在检查掩盖用户值丢失。
    assert '保留用户回收设置' grep -Fxq remove-task=recycle /config/setting.conf
    assert '保留用户移动设置' grep -Fxq move-task=dmof /config/setting.conf
    local key
    for key in remove-task move-task content-filter delete-empty-dir handle-torrent remove-repeat-task move-paused-task; do
        equal 1 "$(grep -c "^${key}=" /config/setting.conf)" "配置键唯一 ${key}"
    done
    assert '补充新键的默认值' grep -Fxq move-paused-task=false /config/setting.conf
    assert '保留 aria2 用户配置' grep -Fxq '# retained-by-upgrade-test' /config/aria2.conf
    assert '升级后配置可写' test -w /config/setting.conf
}
ownership() {
    local pid gid
    # 按 PUID/PGID 运行：aria2c 身份、配置文件与移动后文件的所有者都应是指定值。
    equal "${EXPECT_UID}:${EXPECT_GID}" "$(id -u):$(id -g)" 'abc 映射到 PUID/PGID'
    pid=$(pgrep -x aria2c)
    equal "${EXPECT_UID}" "$(stat -c %u "/proc/${pid}")" 'aria2 运行身份'
    equal "${EXPECT_UID}:${EXPECT_GID}" "$(stat -c '%u:%g' /config/setting.conf)" '配置文件所有者'
    setting move-task true
    complete_fixture
    gid=$(add_torrent multi '{"check-integrity":"true"}') || die 'BT 添加失败'
    wait_status "${gid}" complete
    eventually 15 'BT 完成移动' test -f /downloads/completed/fixture-task/keep.mp4
    owner_is_abc /downloads/completed/fixture-task
    owner_is_abc /downloads/completed/fixture-task/keep.mp4
}
hook_registration_prepare() {
    # 模拟用户换用其他项目的 aria2.conf：缺少 hook 与端口行、hook 指向别处、只有注释行、末尾无换行。
    local conf=/config/aria2.conf
    sed -i -e '/^on-download-\(start\|pause\|complete\)=/d' -e '/^listen-port=/d' \
        -e '/^file-allocation=/d' -e 's@^on-download-stop=.*@on-download-stop=/root/.aria2c/delete.sh@' "${conf}"
    printf '#on-download-complete=/root/.aria2c/clean.sh\n# kept-by-hook-test' >> "${conf}"
}
hook_registration() {
    local conf=/config/aria2.conf pair gid
    for pair in on-download-start=/aria2/scripts/start.sh on-download-pause=/aria2/scripts/pause.sh \
        on-download-complete=/aria2/scripts/completed.sh on-download-stop=/aria2/scripts/stop.sh \
        listen-port=32516 file-allocation=falloc; do
        equal 1 "$(grep -c "^${pair%%=*}=" "${conf}")" "配置键唯一 ${pair%%=*}"
        assert "补齐或改正 ${pair}" grep -Fxq "${pair}" "${conf}"
    done
    assert '保留用户注释' grep -Fxq '# kept-by-hook-test' "${conf}"
    # 配置行存在还不够：用一次真实完成证明 hook 已被 aria2 调用。
    setting move-task true
    gid=$(add_http hook/a.html) || die 'HTTP 添加失败'
    wait_status "${gid}" complete
    eventually 15 'hook 执行移动' test -f /downloads/completed/hook/a.html
}
rpc_tls_prepare() {
    assert '安装测试证书' cp /tmp/tests/tls/cert.pem /config/ssl/rpc.crt
    assert '安装测试私钥' cp /tmp/tests/tls/key.pem /config/ssl/rpc.key
    # 先补换行：旧版模板末尾没有换行，直接追加会拼到最后一行的值里。
    printf '\nrpc-secure=true\nrpc-certificate=/config/ssl/rpc.crt\nrpc-private-key=/config/ssl/rpc.key\n' >> /config/aria2.conf
}
rpc_tls() {
    local gid
    # 开启 rpc-secure 后明文 RPC 不再可用；hook 的 RPC 查询需走 HTTPS 回退，文件处理照常。
    # 用真实 RPC 调用探测：裸 GET 在未开启 TLS 时也返回 400，无法区分。
    if RPC_URL=http://127.0.0.1:6800/jsonrpc rpc aria2.getVersion >/dev/null 2>&1; then
        die '明文 RPC 仍可访问，TLS 未生效'
    fi
    setting move-task true
    gid=$(add_http tls/a.html) || die 'HTTP 添加失败'
    wait_status "${gid}" complete
    eventually 15 'TLS 下 hook 执行移动' test -f /downloads/completed/tls/a.html
}
