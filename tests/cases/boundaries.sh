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

move_target_unavailable() {
    # 目标目录无法创建（/proc 下不可建目录）时应直接走 move-failed，并记录真实原因，
    # 不能因 stat 取不到目标设备号而误报磁盘空间不足。
    local task="${TEST_ROOT}/fallback-task" output
    assert '创建移动夹具' mkdir -p "${task}"
    assert '写入移动夹具' bash -c 'printf KEEP > "$1"' bash "${task}/keep.mp4"
    SOURCE_PATH="${task}"
    TARGET_PATH=/proc/aria2-test-unavailable/category
    DOWNLOAD_DIR=/downloads
    FILE_PATH="${task}/keep.mp4"
    FILE_NUM=2
    MOVE=true
    CF=false
    output=$(MOVE_FILE 2>&1)
    equal KEEP "$(cat /downloads/move-failed/fallback-task/keep.mp4)" '任务移入 move-failed'
    absent "${task}"
    assert '记录目标目录无法创建' grep -Fq '无法创建目标文件夹' "${MOVE_LOG}"
    [[ "${output}" != *"空间不足"* ]] || die '不应误报磁盘空间不足'
    if grep -Fq '空间不足' "${MOVE_LOG}"; then die '日志不应记录磁盘空间不足'; fi
}

crlf_settings() {
    # Windows 编辑器保存的 CRLF 配置也要生效；升级合并后写回的文件不再带 CR。
    local out
    assert '写入 CRLF 配置' bash -c 'printf "move-task=true\r\nremove-task=recycle\r\n" > /config/setting.conf'
    LOAD_CONF
    equal true "${MOVE}" 'CRLF move-task'
    equal recycle "${RMTASK}" 'CRLF remove-task'
    out=$(bash /etc/cont-init.d/11-version /config/aria2.conf /config/setting.conf 2>&1)
    [[ "${out}" == *"完成任务自动移动: [启用]"* ]] || die '横幅应识别 CRLF 配置值'
    assert '合并 CRLF 配置' SED_CONF
    assert '保留 CRLF 中的用户值' grep -Fxq move-task=true /config/setting.conf
    if grep -q $'\r' /config/setting.conf; then die '合并后的配置不应残留 CR'; fi
}
