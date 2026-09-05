#!/usr/bin/env bash
path_aliases() {
    local alias result
    for alias in /downloads/ /downloads//completed /downloads/./recycle \
        /downloads/category/../move-failed /downloads/../config; do
        if IS_TASK_SOURCE_PATH "${alias}"; then die "不应接受路径: ${alias}"; fi
    done
    for alias in /downloads /downloads/ /downloads/./ /downloads/category/..; do
        result=$(
            DOWNLOAD_DIR="${alias}" TARGET_DIR=/downloads/completed
            FILE_PATH="${alias}/剧集 name/episode.mkv" FILE_NUM=2 INFO_HASH=abc123
            GET_FINAL_PATH || exit 1
            printf '%s|%s' "${SOURCE_PATH}" "${TARGET_PATH}"
        ) || die '正常 BT 路径计算失败'
        equal '/downloads/剧集 name|/downloads/completed' "${result}" "等价目录 ${alias}"
    done
}

config_copy_failure() {
    # 只替换不确定的文件复制边界；仍调用完整的正式 SED_CONF。
    assert '准备非默认配置' bash -c 'printf "move-task=dmof\nremove-task=recycle\n" > /config/setting.conf'
    assert '保存旧配置快照' cp /config/setting.conf "${LOG_DIR}/before.conf"
    # shellcheck disable=SC2329
    cp() { : > "$2"; return 1; }
    local rc=0
    SED_CONF > "${LOG_DIR}/copy-failure.log" 2>&1 || rc=$?
    unset -f cp
    [ "${rc}" -ne 0 ] || die '复制失败必须返回非零'
    same_file "${LOG_DIR}/before.conf" /config/setting.conf
    absent /config/setting.conf.new
}
