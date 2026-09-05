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
config_prepare() {
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
