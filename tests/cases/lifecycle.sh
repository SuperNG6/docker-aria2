#!/usr/bin/env bash
http_completion() {
    local gid
    # 同一容器中热修改设置；同一分类目录内保留一个未涉及的文件。
    mkdir -p /downloads/category
    printf 'NEIGHBOR\n' > /downloads/category/neighbor
    curl -fsS --max-time 3 http://127.0.0.1:8080/index.html -o /tmp/expected.html
    gid=$(add_http category/stay.html) || die 'HTTP 添加失败'
    wait_status "${gid}" complete
    eventually 15 '不移动 hook 完成' hook_idle
    same_file /tmp/expected.html /downloads/category/stay.html
    absent /downloads/completed/category/stay.html
    setting move-task true
    gid=$(add_http category/move.html) || die 'HTTP 添加失败'
    wait_status "${gid}" complete
    eventually 15 '完成文件移动' test -f /downloads/completed/category/move.html
    same_file /tmp/expected.html /downloads/completed/category/move.html
    absent /downloads/category/move.html
    same_file /tmp/expected.html /downloads/category/stay.html
    equal NEIGHBOR "$(cat /downloads/category/neighbor)" '分类目录其他文件保留'
    owner_is_abc /downloads/completed/category/move.html
    assert '记录移动结果' grep -Fq '/downloads/category/move.html -> /downloads/completed/category' /config/logs/move.log
}
bt_completion() {
    local mode=$1 gid options='{"check-integrity":"true"}'
    setting move-task true
    complete_fixture
    case "${mode}" in
        filter-partial)
            setting content-filter true
            printf 'exclude-file=txt\nkeyword-file=remove\n' > /config/文件过滤.conf ;;
        filter-all)
            setting content-filter true
            printf 'exclude-file=txt\nkeyword-file=keep\n' > /config/文件过滤.conf
            mkdir /downloads/fixture-task/empty ;;
        selected)
            options='{"check-integrity":"true","select-file":"1"}' ;;
    esac
    gid=$(add_torrent multi "${options}") || die 'BT 添加失败'
    wait_status "${gid}" complete
    eventually 15 'BT 完成移动' test -f /downloads/completed/fixture-task/keep.mp4
    same_file "${TESTS}/fixtures/keep.mp4" /downloads/completed/fixture-task/keep.mp4
    absent /downloads/fixture-task
    owner_is_abc /downloads/completed/fixture-task/keep.mp4
    case "${mode}" in
        filter-partial)
            absent /downloads/completed/fixture-task/remove.txt
            assert '记录过滤文件' grep -Fq remove.txt /config/logs/文件过滤日志.log ;;
        filter-all)
            same_file "${TESTS}/fixtures/remove.txt" /downloads/completed/fixture-task/remove.txt
            assert '保护时不清理空目录' test -d /downloads/completed/fixture-task/empty
            assert '记录整次过滤跳过' grep -Fq '会删除当前任务全部文件' /config/logs/文件过滤日志.log ;;
        selected)
            # 未选中文件的原生处理归 aria2；只验证本项目仍正确定位并移动选中内容。
            : ;;
    esac
}
single_bt() {
    local gid
    setting move-task true
    mkdir -p '/downloads/custom dir'
    cp "${TESTS}/fixtures/single.iso" '/downloads/custom dir/single.iso'
    printf NEIGHBOR > '/downloads/custom dir/neighbor'
    gid=$(add_torrent single '{"dir":"/downloads/custom dir/","check-integrity":"true"}') || die '单文件 BT 添加失败'
    wait_status "${gid}" complete
    eventually 15 '单文件 BT 移动' test -f '/downloads/completed/custom dir/single.iso'
    same_file "${TESTS}/fixtures/single.iso" '/downloads/completed/custom dir/single.iso'
    absent '/downloads/custom dir/single.iso'
    equal NEIGHBOR "$(cat '/downloads/custom dir/neighbor')" '保留自定义目录其他内容'
}
move_storage() {
    local mode=$1 gid destination
    setting move-task true
    complete_fixture
    if [ "${mode}" = cross-device ]; then
        [ "$(stat -c %d /downloads)" != "$(stat -c %d /downloads/completed)" ] \
            || die '夹具错误：目标必须位于不同文件系统'
        destination=/downloads/completed/fixture-task
    else
        chmod a-w /downloads/completed
        destination=/downloads/move-failed/fixture-task
    fi
    gid=$(add_torrent multi '{"check-integrity":"true"}') || die '存储场景添加任务失败'
    wait_status "${gid}" complete
    eventually 20 '文件移动到预期存储位置' test -f "${destination}/remove.txt"
    same_file "${TESTS}/fixtures/keep.mp4" "${destination}/keep.mp4"
    same_file "${TESTS}/fixtures/remove.txt" "${destination}/remove.txt"
    absent /downloads/fixture-task
    owner_is_abc "${destination}/keep.mp4"
    if [ "${mode}" = move-failure ]; then
        assert '记录失败和回退' grep -Fq '文件移动失败' /config/logs/move.log
        assert '记录 move-failed 位置' grep -Fq /downloads/move-failed /config/logs/move.log
    fi
}
repeat_task() {
    local gid
    setting remove-repeat-task true
    mkdir /downloads/completed/fixture-task
    printf OLD > /downloads/completed/fixture-task/old
    gid=$(add_torrent multi) || die '重复任务添加失败'
    wait_status "${gid}" removed
    eventually 15 '重复任务清理完成' hook_idle
    absent /downloads/fixture-task
    equal OLD "$(cat /downloads/completed/fixture-task/old)" '已有副本完整'
}
pause_task() {
    local mode=$1 gid
    setting move-paused-task true
    gid=$(add_torrent multi) || die '暂停任务添加失败'
    wait_status "${gid}" active
    eventually 15 '活动任务落盘' test -f /downloads/fixture-task/remove.txt
    rpc aria2.pause "[\"${gid}\"]" >/dev/null
    wait_status "${gid}" paused
    # 等待正式 pause hook 已进入睡眠，确保后续操作真的发生在等待窗口中。
    eventually 10 '暂停 hook 已启动' pgrep -f '^bash /aria2/scripts/pause\.sh( |$)'
    cp /downloads/fixture-task/keep.mp4 /tmp/paused-keep
    cp /downloads/fixture-task/remove.txt /tmp/paused-remove
    case "${mode}" in
        pause-move)
            eventually 50 '暂停后移动' test -f /downloads/completed/fixture-task/keep.mp4
            same_file /tmp/paused-keep /downloads/completed/fixture-task/keep.mp4
            same_file /tmp/paused-remove /downloads/completed/fixture-task/remove.txt
            absent /downloads/fixture-task
            absent /downloads/fixture-task.aria2 ;;
        pause-disable|pause-resume)
            if [ "${mode}" = pause-disable ]; then
                setting move-paused-task false
            else
                rpc aria2.unpause "[\"${gid}\"]" >/dev/null
                wait_status "${gid}" active
            fi
            consistently 35 '暂停取消后文件与控制文件留在原位' pause_files_preserved
            eventually 15 '暂停 hook 退出' hook_idle
            same_file /tmp/paused-keep /downloads/fixture-task/keep.mp4
            same_file /tmp/paused-remove /downloads/fixture-task/remove.txt ;;
    esac
}
pause_files_preserved() {
    [ -f /downloads/fixture-task/keep.mp4 ] && [ -f /downloads/fixture-task/remove.txt ] \
        && [ -f /downloads/fixture-task.aria2 ] && [ ! -e /downloads/completed/fixture-task ]
}
stop_task() {
    local mode=$1 gid destination
    if [ "${mode}" = recycle-failure ]; then
        setting remove-task recycle
        # abc 无写权限，构造真实 mv 失败，不替换生产函数。
        chmod a-w /downloads/recycle
    else
        setting remove-task "${mode}"
    fi
    gid=$(add_torrent multi) || die '停止任务添加失败'
    wait_status "${gid}" active
    eventually 15 '活动文件落盘' test -f /downloads/fixture-task/remove.txt
    cp /downloads/fixture-task/keep.mp4 /tmp/stopped-keep
    cp /downloads/fixture-task/remove.txt /tmp/stopped-remove
    rpc aria2.forceRemove "[\"${gid}\"]" >/dev/null
    wait_status "${gid}" removed
    eventually 15 '停止文件清理' test ! -e /downloads/fixture-task
    eventually 15 '停止 hook 完成' hook_idle
    absent /downloads/fixture-task.aria2
    if [ "${mode}" = recycle ]; then
        destination=/downloads/recycle/fixture-task
        same_file /tmp/stopped-keep "${destination}/keep.mp4"
        same_file /tmp/stopped-remove "${destination}/remove.txt"
        assert '记录回收结果' grep -Fq '成功移动文件到回收站' /config/logs/recycle.log
    elif [ "${mode}" = recycle-failure ]; then
        absent /downloads/recycle/fixture-task
        assert '记录已接受的永久删除退路' grep -Fq '已删除文件' /config/logs/recycle.log
    else
        absent /downloads/recycle/fixture-task
        assert '记录删除结果' grep -Fq '文件删除成功' /config/logs/delete.log
    fi
}
reserved_directory() {
    local gid
    setting remove-task delete
    gid=$(add_torrent reserved '{"dir":"/downloads/"}') || die '共享目录任务添加失败'
    wait_status "${gid}" active
    eventually 15 '共享目录内任务落盘' test -f /downloads/completed/remove.txt
    rpc aria2.forceRemove "[\"${gid}\"]" >/dev/null
    wait_status "${gid}" removed
    eventually 15 '停止 hook 退出' hook_idle
    assert '不对共享目录整删' test -f /downloads/completed/keep.mp4
    sentinels_unchanged
}
