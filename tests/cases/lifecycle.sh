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
    # 从 completed 续种：任务已在目标根目录内，完成后不得再嵌套移动到 completed/completed
    gid=$(add_torrent single '{"dir":"/downloads/completed/custom dir","check-integrity":"true"}') || die '续种任务添加失败'
    wait_status "${gid}" complete
    consistently 5 '续种任务不嵌套移动' test ! -e /downloads/completed/completed
    eventually 15 '续种 hook 完成' hook_idle
    same_file "${TESTS}/fixtures/single.iso" '/downloads/completed/custom dir/single.iso'
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
            # 暂停→恢复→再暂停：两个等待中的 hook 只能移动一次，后到的不得报移动失败
            rpc aria2.unpause "[\"${gid}\"]" >/dev/null
            wait_status "${gid}" active
            rpc aria2.pause "[\"${gid}\"]" >/dev/null
            wait_status "${gid}" paused
            eventually 50 '暂停后移动' test -f /downloads/completed/fixture-task/keep.mp4
            eventually 40 '暂停 hook 全部退出' hook_idle
            same_file /tmp/paused-keep /downloads/completed/fixture-task/keep.mp4
            same_file /tmp/paused-remove /downloads/completed/fixture-task/remove.txt
            absent /downloads/fixture-task
            absent /downloads/fixture-task.aria2
            if grep -q ERROR /config/logs/move.log; then die "重复的暂停 hook 不应记录移动失败: $(cat /config/logs/move.log)"; fi ;;
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
http_nested() {
    local gid
    # 单文件任务移走后，--out 带出的空子目录逐级清理；仍有内容的分类目录必须保留。
    setting move-task true
    curl -fsS --max-time 3 http://127.0.0.1:8080/index.html -o /tmp/expected.html
    mkdir -p '/downloads/剧集 [A]/其他'
    printf 'NEIGHBOR\n' > '/downloads/剧集 [A]/其他/neighbor'
    gid=$(add_http '剧集 [A]/第1季, 特别篇/a.html') || die 'HTTP 添加失败'
    wait_status "${gid}" complete
    eventually 15 '嵌套文件移动' test -f '/downloads/completed/剧集 [A]/第1季, 特别篇/a.html'
    eventually 15 '移动 hook 完成' hook_idle
    same_file /tmp/expected.html '/downloads/completed/剧集 [A]/第1季, 特别篇/a.html'
    absent '/downloads/剧集 [A]/第1季, 特别篇'
    equal NEIGHBOR "$(cat '/downloads/剧集 [A]/其他/neighbor')" '非空分类目录保留'
    gid=$(add_http 'OpenList/测试/b.html') || die 'HTTP 添加失败'
    wait_status "${gid}" complete
    eventually 15 '多级目录文件移动' test -f /downloads/completed/OpenList/测试/b.html
    eventually 15 '移动 hook 完成' hook_idle
    absent /downloads/OpenList
    owner_is_abc /downloads/completed/OpenList/测试/b.html
    # 停止路径同样清理：限速让 HTTP 任务保持活动，再按 remove-task=delete 删除。
    setting remove-task delete
    gid=$(add_http '删除/剧名/c.html' '{"max-download-limit":"1K"}') || die 'HTTP 添加失败'
    wait_status "${gid}" active
    eventually 15 '活动文件落盘' test -f '/downloads/删除/剧名/c.html.aria2'
    rpc aria2.forceRemove "[\"${gid}\"]" >/dev/null
    wait_status "${gid}" removed
    eventually 15 '停止后删除并清理空目录' test ! -e /downloads/删除
    eventually 15 '停止 hook 完成' hook_idle
}
complex_bt() {
    local gid root="/downloads/completed/${COMPLEX_TASK}"
    # 多级目录 + 特殊字符名称：完整移动、按扩展名过滤、过滤后清理空目录。
    setting move-task true
    setting content-filter true
    printf 'exclude-file=txt\n' > /config/文件过滤.conf
    complex_fixture
    gid=$(add_torrent complex '{"check-integrity":"true"}') || die '复杂路径 BT 添加失败'
    wait_status "${gid}" complete
    eventually 15 '复杂路径移动' test -f "${root}/Season 2/第01集.mkv"
    equal EPISODE1 "$(cat "${root}/Season 1/第01集 [1080p].mkv")" '第一季内容完整'
    equal EPISODE2 "$(cat "${root}/Season 2/第01集.mkv")" '第二季内容完整'
    absent "${root}/Season 1/Extras"
    absent "/downloads/${COMPLEX_TASK}"
    owner_is_abc "${root}/Season 1/第01集 [1080p].mkv"
}
magnet_default() {
    local hash gid follow
    # 零配置用户：不改 setting.conf，走磁力两阶段流程（元数据 → .torrent → 接续任务 → 完成）。
    # 默认 move-task=false、handle-torrent=backup-rename：内容留在原处，种子按任务名备份。
    start_seeder
    hash=$(torrent_hash multi)
    gid=$(add_magnet "${hash}") || die '磁力任务添加失败'
    wait_status "${gid}" complete
    follow=$(rpc aria2.tellStatus "[\"${gid}\"]" | jq -er '.result.followedBy[0]') || die '磁力任务未接续下载任务'
    wait_status "${follow}" complete
    eventually 15 '种子按任务名备份' test -f /config/backup-torrent/fixture-task.torrent
    eventually 15 'hook 完成' hook_idle
    equal "${hash}" "$(aria2c -S /config/backup-torrent/fixture-task.torrent | sed -n 's/^Info Hash: //p')" '备份种子即本任务'
    absent "/downloads/${hash}.torrent"
    same_file "${TESTS}/fixtures/keep.mp4" /downloads/fixture-task/keep.mp4
    same_file "${TESTS}/fixtures/remove.txt" /downloads/fixture-task/remove.txt
    absent /downloads/fixture-task.aria2
    absent /downloads/completed/fixture-task
}
inactive_files_kept() {
    [ -f /downloads/fixture-task/keep.mp4 ] && [ -f /downloads/fixture-task/remove.txt ]
}
forget_task() {
    # 已暂停任务被删除后不留记录，清除记录失败是预期内的。
    rpc aria2.removeDownloadResult "[\"$1\"]" >/dev/null 2>&1 || true
    rm -rf /downloads/fixture-task /downloads/fixture-task.aria2
}
stop_inactive() {
    local gid
    # aria2 只在活动任务停止时调用 hook；删除已暂停任务、移除已完成记录不发事件。
    # 固定已文档化的行为：remove-task=delete 时这两种操作都不动文件。
    setting remove-task delete
    gid=$(add_torrent multi) || die '活动任务添加失败'
    wait_status "${gid}" active
    eventually 15 '活动文件落盘' test -f /downloads/fixture-task/remove.txt
    rpc aria2.remove "[\"${gid}\"]" >/dev/null
    wait_status "${gid}" removed
    eventually 15 '活动任务删除文件' test ! -e /downloads/fixture-task
    eventually 15 'hook 完成' hook_idle
    forget_task "${gid}"

    gid=$(add_torrent multi) || die '暂停任务添加失败'
    wait_status "${gid}" active
    eventually 15 '暂停前文件落盘' test -f /downloads/fixture-task/remove.txt
    rpc aria2.forcePause "[\"${gid}\"]" >/dev/null
    wait_status "${gid}" paused
    rpc aria2.remove "[\"${gid}\"]" >/dev/null
    eventually 15 '已暂停任务离开队列' not_queued "${gid}"
    consistently 5 '删除已暂停任务不动文件' inactive_files_kept
    forget_task "${gid}"

    complete_fixture
    gid=$(add_torrent multi '{"check-integrity":"true"}') || die '完成任务添加失败'
    wait_status "${gid}" complete
    eventually 15 'hook 完成' hook_idle
    rpc aria2.removeDownloadResult "[\"${gid}\"]" >/dev/null
    consistently 5 '移除已完成记录不动文件' inactive_files_kept
    equal 1 "$(grep -c '文件删除成功' /config/logs/delete.log)" '只有活动任务触发删除'
}
