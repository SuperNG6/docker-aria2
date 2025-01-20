# 项目中文本文件汇总

tree
.
├── ALL.md
├── Dockerfile
├── README.md
├── build.sh
├── darkhttpd
│   └── 50-config
├── docker-compose.yml
├── export_text_files.sh
├── install.sh
└── root
    ├── aria2
    │   ├── conf
    │   │   ├── aria2.conf.default
    │   │   ├── rpc-tracker0
    │   │   ├── rpc-tracker1
    │   │   ├── setting.conf
    │   │   └── 文件过滤.conf
    │   └── script
    │       ├── completed.sh
    │       ├── core
    │       ├── cron-restart-a2b.sh
    │       ├── pause.sh
    │       ├── rpc_info
    │       ├── rpc_tracker.sh
    │       ├── setting
    │       ├── start.sh
    │       ├── stop.sh
    │       └── tracker.sh
    └── etc
        ├── cont-init.d
        │   ├── 11-version
        │   ├── 20-config
        │   ├── 30-config
        │   ├── 40-config
        │   ├── 90-custom-folders
        │   └── 99-custom-scripts
        └── services.d
            ├── aria2
            │   └── run
            └── aria2b
                └── run

## 文件路径：`./Dockerfile`

```
FROM superng6/alpine:3.21 AS builder

# download static aria2c && AriaNg AllInOne
RUN apk add --no-cache curl wget unzip \
    && ARIANG_VER=$(wget -qO- https://api.github.com/repos/mayswind/AriaNg/tags | grep 'name' | cut -d\" -f4 | head -1 ) \
    && wget -P /tmp https://github.com/mayswind/AriaNg/releases/download/${ARIANG_VER}/AriaNg-${ARIANG_VER}-AllInOne.zip \
    && unzip /tmp/AriaNg-${ARIANG_VER}-AllInOne.zip -d /tmp \
    && A2B_VER=$(wget -qO- https://api.github.com/repos/makeding/aria2b/tags | grep 'name' | cut -d\" -f4 | head -1 ) \
    && wget -P /tmp https://github.com/makeding/aria2b/releases/download/${A2B_VER}/aria2b \
    && curl -fsSL https://git.io/docker-aria2c.sh | bash

# install static aria2c
FROM superng6/alpine:3.21

# set label
LABEL maintainer="NG6"
ENV TZ=Asia/Shanghai UT=true SECRET=yourtoken CACHE=128M QUIET=true \
    SMD=true RUT=true A2B=true CRA2B=2h \
    PORT=6800 WEBUI=true WEBUI_PORT=8080 BTPORT=32516 \
    PUID=1026 PGID=100

# copy local files && aria2c
COPY root/ /
COPY darkhttpd/ /etc/cont-init.d/
COPY --from=builder /tmp/index.html /www/index.html
COPY --from=builder /usr/local/bin/aria2c /usr/local/bin/aria2c
COPY --from=builder /tmp/aria2b /usr/local/bin/aria2b

# install
RUN apk add --no-cache darkhttpd curl jq findutils iptables ip6tables ipset nodejs \
    && chmod a+x /usr/local/bin/aria2c \
    && chmod a+x /usr/local/bin/aria2b \
    && A2B_VER=$(wget -qO- https://api.github.com/repos/makeding/aria2b/tags | grep 'name' | cut -d\" -f4 | head -1 ) \
    && ARIANG_VER=$(wget -qO- https://api.github.com/repos/mayswind/AriaNg/tags | grep 'name' | cut -d\" -f4 | head -1 ) \
    && echo "docker-aria2-$(date +"%Y-%m-%d")" > /aria2/build-date \
    && echo "docker-ariang-$ARIANG_VER" >> /aria2/build-date \
    && echo "docker-aria2b-$A2B_VER" >> /aria2/build-date \
    && rm -rf /var/cache/apk/* /tmp/*

# volume
VOLUME /config /downloads /www

EXPOSE 8080 6800 32516 32516/udp
```

## 文件路径：`./install.sh`

```
#!/usr/bin/env bash

# Check CPU architecture
ARCH=$(uname -m)
ARIAC=1.36.0
echo -e "${INFO} Check CPU architecture ..."
if [[ ${ARCH} == "x86_64" ]]; then
    ARCH="aria2-${ARIAC}-static-linux-amd64.tar.gz"
elif [[ ${ARCH} == "aarch64" ]]; then
    ARCH="aria2-${ARIAC}-static-linux-arm64.tar.gz"
elif [[ ${ARCH} == "armv7l" ]]; then
    ARCH="aria2-${ARIAC}-static-linux-armhf.tar.gz"
else
    echo -e "${ERROR} This architecture is not supported."
    exit 1
fi

# Download files
echo "Downloading binary file: ${ARCH}"
curl -L "https://github.com/SuperNG6/docker-aria2/releases/download/2021.08.24/${ARCH}" | tar -xz
mv aria2c /usr/local/bin
echo "Download binary file: ${ARCH} completed"```

## 文件路径：`./export_text_files.sh`

```
#!/usr/bin/env bash

########################################################################
# 脚本名称: export_text_files.sh
# 作用    : 收集当前项目目录下的纯文本文件内容，汇总到 ALL.md
#
# 注意点：
#   1. 排除 .git, node_modules, vendor 等目录
#   2. 跳过 README.md
#   3. 跳过 ALL.md 自身(否则会不断读写自身导致无限膨胀)
#   4. 限制文件大小 <1MB，避免扫描到过大的文本
#   5. 只输出 MIME 为 text/ 的文件
########################################################################

DEBUG=true                   # 是否输出 DEBUG 日志
OUTPUT_FILE="ALL.md"         # 最终输出的 Markdown 文件
SIZE_LIMIT="-1M"            # 只处理<1MB的文件，可自行调节

EXCLUDE_DIRS=(
    "./.git/*"
    "./node_modules/*"
    "./vendor/*"
)
EXCLUDE_FILES=(
    "README.md"
    "ALL.md"       # 新增：排除脚本正在生成的 ALL.md 文件
)

debug_log() {
  if [ "$DEBUG" = true ]; then
    echo "[DEBUG] $*"
  fi
}

# 如果已存在同名文件，先删除
[ -f "$OUTPUT_FILE" ] && rm "$OUTPUT_FILE"
debug_log "删除已有的 $OUTPUT_FILE"

# 写入标题
echo "# 项目中文本文件汇总" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
debug_log "写入初始标题到 $OUTPUT_FILE"

# 构建 find 命令参数
FIND_CMD=( find . -type f )

# 排除目录
for d in "${EXCLUDE_DIRS[@]}"; do
    FIND_CMD+=( -not -path "$d" )
done

# 排除文件名
for f in "${EXCLUDE_FILES[@]}"; do
    FIND_CMD+=( -not -name "$f" )
done

# 如果设置了文件大小限制
if [ -n "$SIZE_LIMIT" ]; then
  FIND_CMD+=( -size "$SIZE_LIMIT" )
fi

FIND_CMD+=( -print )

debug_log "执行的 find 命令：${FIND_CMD[*]}"

# 开始遍历文件
"${FIND_CMD[@]}" | while IFS= read -r file
do
    debug_log "处理文件：$file"
    mime_info=$(file --mime-type "$file")
    if echo "$mime_info" | grep -q "text/"; then
        debug_log " -> 纯文本文件，添加到 $OUTPUT_FILE"
        echo "## 文件路径：\`$file\`" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "\`\`\`" >> "$OUTPUT_FILE"
        cat "$file" >> "$OUTPUT_FILE"
        echo "\`\`\`" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    else
        debug_log " -> 非文本，跳过"
    fi
done

debug_log "全部文件处理完成。"
echo "脚本执行完毕，所有符合条件的文本文件已汇总到 \`$OUTPUT_FILE\`。"
```

## 文件路径：`./darkhttpd/50-config`

```
#!/usr/bin/with-contenv bash

if [ "$WEBUI" == "true" ]
then
  darkhttpd /www --index index.html --port ${WEBUI_PORT} --daemon
fi
```

## 文件路径：`./build.sh`

```
#!/bin/bash

docker build \
  --tag superng6/aria2:latest \
  --force-rm \
    .
```

## 文件路径：`./.dockerignore`

```
.git
.gitignore
.DS_Store
build.sh
docker-compose.yml
README.md```

## 文件路径：`./.gitignore`

```
.github
Build Image.yml```

## 文件路径：`./.github/workflows/Build Image.yml`

```
name: Build Docker Image

on:
  push:
  workflow_dispatch:

jobs:
  buildx:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v3
      
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v2
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
          
      # ReleaseTag
      - name: Set Version
        id: set-version
        run: |
          echo "::set-output name=version::$(date +"%y-%m-%d")"
          echo $(date +"%y-%m-%d")
          echo "::set-output name=status::success"

      - name: Build dockerfile A2B
        if: steps.set-version.outputs.status == 'success'
        uses: docker/build-push-action@v2
        with:
          file: ./Dockerfile
          platforms: linux/amd64,linux/arm/v7,linux/arm64
          push: true
          tags: |
            superng6/aria2:a2b-stable-${{ steps.set-version.outputs.version }}
            superng6/aria2:a2b-latest  
```

## 文件路径：`./root/aria2/script/rpc_tracker.sh`

```
#!/usr/bin/env bash
# Copyright (c) 2018-2020 P3TERX <https://p3terx.com>

RED_FONT_PREFIX="\033[31m"
GREEN_FONT_PREFIX="\033[32m"
YELLOW_FONT_PREFIX="\033[1;33m"
LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
ARIA2_CONF=${1:-aria2.conf}
DOWNLOADER="curl -fsSL --connect-timeout 3 --max-time 3 --retry 2"
SCRIPT_CONF="/config/setting.conf"
NL=$'\n'

DATE_TIME() {
    date +"%Y/%m/%d %H:%M:%S"
}

GET_TRACKERS() {
    if [[ -z "${CTU}" ]]; then
        echo && echo -e "$(DATE_TIME) ${INFO} Get BT trackers..."
        TRACKER=$(
            ${DOWNLOADER} https://trackerslist.com/all_aria2.txt ||
                ${DOWNLOADER} https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt ||
                ${DOWNLOADER} https://ghp.ci/https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/all_aria2.txt
        )
    else
        echo && echo -e "$(DATE_TIME) ${INFO} Get BT trackers from url(s):${CTU} ..."
        URLS=$(echo ${CTU} | tr "," "$NL")
        for URL in $URLS; do
            TRACKER+="$(${DOWNLOADER} ${URL} | tr "," "\n")$NL"
        done
        TRACKER="$(echo "$TRACKER" | awk NF | sort -u | sed 'H;1h;$!d;x;y/\n/,/' )"
    fi

    [[ -z "${TRACKER}" ]] && {
        echo
        echo -e "$(DATE_TIME) ${ERROR} Unable to get trackers, network failure or invalid links." && exit 1
    }
}


ECHO_TRACKERS() {
    echo -e "
--------------------[BitTorrent Trackers]--------------------
${TRACKER}
--------------------[BitTorrent Trackers]--------------------
"
}


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
    [[ $(echo ${RPC_RESULT} | grep OK) ]] &&
        echo -e "$(DATE_TIME) ${INFO} BT trackers successfully added to Aria2 !" ||
        echo -e "$(DATE_TIME) ${ERROR} Network failure or Aria2 RPC interface error!"
}

RPC_ADDRESS="localhost:${PORT}/jsonrpc"
GET_TRACKERS
ECHO_TRACKERS
ADD_TRACKERS_RPC
ADD_TRACKERS_RPC_STATUS
```

## 文件路径：`./root/aria2/script/core`

```
#!/usr/bin/env bash

GET_BASE_PATH() {
    # Aria2下载目录
    DOWNLOAD_PATH="/downloads"
    # 种子备份目录
    BAK_TORRENT_DIR="/config/backup-torrent"
    # 日志、配置文件保存路径
    SCRIPT_CONF="/config/文件过滤.conf"
    CF_LOG="/config/logs/文件过滤日志.log"
    MOVE_LOG="/config/logs/move.log"
    DELETE_LOG="/config/logs/delete.log"
    RECYCLE_LOG="/config/logs/recycle.log"
}

# ========================GET_TARGET_PATH==============================

COMPLETED_PATH() {
    # 完成任务后转移
    TARGET_DIR="${DOWNLOAD_PATH}/completed"
}

RECYCLE_PATH() {
    # 回收站
    TARGET_DIR="${DOWNLOAD_PATH}/recycle"
}

# ============================颜色==============================

RED_FONT_PREFIX="\033[31m"
LIGHT_GREEN_FONT_PREFIX="\033[1;32m"
YELLOW_FONT_PREFIX="\033[1;33m"
LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${LIGHT_GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
WARRING="[${YELLOW_FONT_PREFIX}WARRING${FONT_COLOR_SUFFIX}]"

# ============================时间==============================

DATE_TIME() {
    date +"%Y/%m/%d %H:%M:%S"
}

# ==========================任务信息===============================

TASK_INFO() {
    echo -e "
-------------------------- [${YELLOW_FONT_PREFIX} 任务信息 ${TASK_TYPE} ${FONT_COLOR_SUFFIX}] --------------------------
${LIGHT_PURPLE_FONT_PREFIX}根下载路径:${FONT_COLOR_SUFFIX} ${DOWNLOAD_PATH}
${LIGHT_PURPLE_FONT_PREFIX}任务位置:${FONT_COLOR_SUFFIX} ${SOURCE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}首个文件位置:${FONT_COLOR_SUFFIX} ${FILE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}任务文件数量:${FONT_COLOR_SUFFIX} ${FILE_NUM}
${LIGHT_PURPLE_FONT_PREFIX}移动至目标文件夹:${FONT_COLOR_SUFFIX} ${TARGET_PATH}
-----------------------------------------------------------------------------------------------------------------------
"
}

DELETE_INFO() {
    echo -e "
-------------------------- [${YELLOW_FONT_PREFIX} 任务信息 ${TASK_TYPE} ${FONT_COLOR_SUFFIX}] --------------------------
${LIGHT_PURPLE_FONT_PREFIX}根下载路径:${FONT_COLOR_SUFFIX} ${DOWNLOAD_PATH}
${LIGHT_PURPLE_FONT_PREFIX}任务位置:${FONT_COLOR_SUFFIX} ${SOURCE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}首个文件位置:${FONT_COLOR_SUFFIX} ${FILE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}任务文件数量:${FONT_COLOR_SUFFIX} ${FILE_NUM}
-----------------------------------------------------------------------------------------------------------------------
"
}

# =============================读取conf文件设置=============================

LOAD_SCRIPT_CONF() {
    MIN_SIZE="$(grep ^min-size "${SCRIPT_CONF}" | cut -d= -f2-)"
    INCLUDE_FILE="$(grep ^include-file "${SCRIPT_CONF}" | cut -d= -f2-)"
    EXCLUDE_FILE="$(grep ^exclude-file "${SCRIPT_CONF}" | cut -d= -f2-)"
    KEYWORD_FILE="$(grep ^keyword-file "${SCRIPT_CONF}" | cut -d= -f2-)"
    INCLUDE_FILE_REGEX="$(grep ^include-file-regex "${SCRIPT_CONF}" | cut -d= -f2-)"
    EXCLUDE_FILE_REGEX="$(grep ^exclude-file-regex "${SCRIPT_CONF}" | cut -d= -f2-)"
}

DELETE_EXCLUDE_FILE() {
    if [[ ${FILE_NUM} -gt 1 ]] && [ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ] && [[ -n ${MIN_SIZE} || -n ${INCLUDE_FILE} || -n ${EXCLUDE_FILE} || -n ${KEYWORD_FILE} || -n ${EXCLUDE_FILE_REGEX} || -n ${INCLUDE_FILE_REGEX} ]]; then
        echo -e "$(DATE_TIME) ${INFO} 删除不需要的文件..."
        [[ -n ${MIN_SIZE} ]] && find "${SOURCE_PATH}" -type f -size -${MIN_SIZE} -print0 | xargs -0 rm -vf | tee -a ${CF_LOG}
        [[ -n ${EXCLUDE_FILE} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*\.(${EXCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a ${CF_LOG}
        [[ -n ${KEYWORD_FILE} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex ".*(${KEYWORD_FILE}).*" -print0 | xargs -0 rm -vf | tee -a ${CF_LOG}
        [[ -n ${INCLUDE_FILE} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex ".*\.(${INCLUDE_FILE})" -print0 | xargs -0 rm -vf | tee -a ${CF_LOG}
        [[ -n ${EXCLUDE_FILE_REGEX} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended -iregex "${EXCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a ${CF_LOG}
        [[ -n ${INCLUDE_FILE_REGEX} ]] && find "${SOURCE_PATH}" -type f -regextype posix-extended ! -iregex "${INCLUDE_FILE_REGEX}" -print0 | xargs -0 rm -vf | tee -a ${CF_LOG}
    fi
}

# =============================删除.ARIA2=============================

RM_ARIA2() {
    if [ -e "${SOURCE_PATH}.aria2" ]; then
        rm -f "${SOURCE_PATH}.aria2"
        echo -e "$(DATE_TIME) ${INFO} 已删除文件: ${SOURCE_PATH}.aria2"
    fi
}

# =============================删除空文件夹=============================

DELETE_EMPTY_DIR() {
    if [ "${DET}" = "true" ]; then
        echo -e "$(DATE_TIME) ${INFO} 删除任务中空的文件夹 ..."
        find "${SOURCE_PATH}" -depth -type d -empty -exec rm -vrf {} \;
    fi
}

# =============================内容过滤=============================

CLEAN_UP() {
    RM_ARIA2
    if [ "$CF" == "true" ] && [ ${FILE_NUM} -gt 1 ] && [ "${SOURCE_PATH}" != "${DOWNLOAD_PATH}" ]; then
        echo -e "$(DATE_TIME) ${INFO} 被过滤文件的任务路径: ${SOURCE_PATH}" | tee -a ${CF_LOG}
        LOAD_SCRIPT_CONF
        DELETE_EXCLUDE_FILE
        DELETE_EMPTY_DIR
    fi
}

# =============================移动文件=============================

MOVE_FILE() {
    # DOWNLOAD_DIR = DOWNLOAD_PATH，说明为在根目录下载的单文件，`dmof时不进行移动
    if [ "${MOVE}" = "false" ]; then
        RM_ARIA2
        return
    elif [ "${MOVE}" = "dmof" ] && [ "${DOWNLOAD_DIR}" = "${DOWNLOAD_PATH}" ] && [ ${FILE_NUM} -eq 1 ]; then
        RM_ARIA2
        return
    elif [ "${MOVE}" = "true" ] || [ "${MOVE}" = "dmof" ]; then
        TASK_TYPE=": 移动任务文件"
        TASK_INFO
        CLEAN_UP
        echo -e "$(DATE_TIME) ${INFO} 开始移动该任务文件到: ${LIGHT_GREEN_FONT_PREFIX}${TARGET_PATH}${FONT_COLOR_SUFFIX}"
        mkdir -p "${TARGET_PATH}"
        mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
        MOVE_EXIT_CODE=$?
        if [ ${MOVE_EXIT_CODE} -eq 0 ]; then
            echo -e "$(DATE_TIME) ${INFO} 已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}"
            [ ${MOVE_LOG} ] && echo -e "$(DATE_TIME) [INFO] 已移动文件至目标文件夹: ${SOURCE_PATH} -> ${TARGET_PATH}" >>"${MOVE_LOG}"
        else
            echo -e "$(DATE_TIME) ${ERROR} 文件移动失败: ${SOURCE_PATH}"
            [ ${MOVE_LOG} ] && echo -e "$(DATE_TIME) [ERROR] 文件移动失败: ${SOURCE_PATH}" >>"${MOVE_LOG}"
            
            # ============== NEW FEATURE: 移动失败后，转移至 /downloads/move-failed ==============
            FAIL_DIR="${DOWNLOAD_PATH}/move-failed"
            mkdir -p "${FAIL_DIR}"
            mv -f "${SOURCE_PATH}" "${FAIL_DIR}"
            MOVE_FAIL_EXIT_CODE=$?
            if [ ${MOVE_FAIL_EXIT_CODE} -eq 0 ]; then
                echo -e "$(DATE_TIME) ${INFO} 已将文件移动至备用文件夹: ${SOURCE_PATH} -> ${FAIL_DIR}"
                [ ${MOVE_LOG} ] && echo -e "$(DATE_TIME) [INFO] 已将文件移动至备用文件夹: ${SOURCE_PATH} -> ${FAIL_DIR}" >>"${MOVE_LOG}"
            else
                echo -e "$(DATE_TIME) ${ERROR} 移动到备用文件夹依然失败: ${SOURCE_PATH}"
                [ ${MOVE_LOG} ] && echo -e "$(DATE_TIME) [ERROR] 移动到备用文件夹依然失败: ${SOURCE_PATH}" >>"${MOVE_LOG}"
            fi
            # ============== NEW FEATURE END ==============
        fi
    fi
}

# =============================删除文件=============================

DELETE_FILE() {
    TASK_TYPE=": 删除任务文件"
    DELETE_INFO
    echo -e "$(DATE_TIME) ${INFO} 下载已停止，开始删除文件..."
    rm -rf "${SOURCE_PATH}"
    MOVE_EXIT_CODE=$?
    if [ ${MOVE_EXIT_CODE} -eq 0 ]; then
        echo -e "$(DATE_TIME) ${INFO} 已删除文件: ${SOURCE_PATH}"
        [ ${DELETE_LOG} ] && echo -e "$(DATE_TIME) [INFO] 文件删除成功: ${SOURCE_PATH}" >>${DELETE_LOG}
    else
        echo -e "$(DATE_TIME) ${ERROR} delete failed: ${SOURCE_PATH}"
        [ ${DELETE_LOG} ] && echo -e "$(DATE_TIME) [ERROR] 文件删除失败: ${SOURCE_PATH}" >>${DELETE_LOG}
    fi
}

# =============================回收站=============================

MOVE_RECYCLE() {
    TASK_TYPE=": 移动任务文件至回收站"
    TASK_INFO
    echo -e "$(DATE_TIME) ${INFO} 开始移动已下载的任务至回收站 ${LIGHT_GREEN_FONT_PREFIX}${TARGET_PATH}${FONT_COLOR_SUFFIX}"
    mkdir -p "${TARGET_PATH}"
    mv -f "${SOURCE_PATH}" "${TARGET_PATH}"
    MOVE_EXIT_CODE=$?
    if [ ${MOVE_EXIT_CODE} -eq 0 ]; then
        echo -e "$(DATE_TIME) ${INFO} 已移至回收站: ${SOURCE_PATH} -> ${TARGET_PATH}"
        [ ${RECYCLE_LOG} ] && echo -e "$(DATE_TIME) [INFO] 成功移动文件到回收站: ${SOURCE_PATH} -> ${TARGET_PATH}" >>${RECYCLE_LOG}
    else
        echo -e "$(DATE_TIME) ${ERROR} 移动文件到回收站失败: ${SOURCE_PATH}"
        echo -e "$(DATE_TIME) ${INFO} 已删除文件: ${SOURCE_PATH}"
        rm -rf "${SOURCE_PATH}"
        [ ${RECYCLE_LOG} ] && echo -e "$(DATE_TIME) [ERROR] 移动文件到回收站失败: ${SOURCE_PATH}" >>${RECYCLE_LOG}
    fi
}

# =============================处理种子文件=============================

HANDLE_TORRENT() {
    if [ "${TOR}" = "retain" ]; then
        return
    elif [ "${TOR}" = "delete" ]; then
        echo -e "$(DATE_TIME) ${INFO} 已删除种子文件: ${TORRENT_FILE}"
        rm -f "${TORRENT_FILE}"
        return
    elif [ "${TOR}" = "rename" ]; then
        echo -e "$(DATE_TIME) ${INFO} 已删除种子文件: ${TORRENT_FILE}"
        mv -f "${TORRENT_FILE}" "${TASK_NAME}.torrent"
    elif [ "${TOR}" = "backup" ]; then
        echo -e "$(DATE_TIME) ${INFO} 备份种子文件: ${TORRENT_FILE}"
        mv -vf "${TORRENT_FILE}" "${BAK_TORRENT_DIR}"
    elif [ "${TOR}" = "backup-rename" ]; then
        echo -e "$(DATE_TIME) ${INFO} 重命名并备份种子文件: ${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
        mv -f "${TORRENT_FILE}" "${BAK_TORRENT_DIR}/${TASK_NAME}.torrent"
    fi
}

CHECK_TORRENT() {
    if [ -e "${TORRENT_FILE}" ]; then
        HANDLE_TORRENT
    fi
}

# =============================判断文件路径=============================

GET_TARGET_PATH() {
    RELATIVE_PATH="${SOURCE_PATH#"${DOWNLOAD_PATH}/"}"
    TARGET_PATH="${TARGET_DIR}/$(dirname "${RELATIVE_PATH}")"
    # 出现 // 说明路径获取失败，为防止后续操作继续执行返回 error
    if [ "${TARGET_PATH}" == "${TARGET_DIR}//" ]; then
        GET_PATH_INFO="error"
        return
    # /downloads根目录下载会出现 /.
    elif [ "${TARGET_PATH}" = "${TARGET_DIR}/." ]; then
        TARGET_PATH="${TARGET_DIR}"
    fi
}

GET_FINAL_PATH() { 
    if [ -z "${FILE_PATH}" ]; then
        return
    # 判断是否为在文件夹内的单文件BT下载任务（会出现移动文件后文件夹保留的情况），如果是则降级到目录
    # 修复Mac下能够正常运行，Linux下失败的问题
    elif [ "${FILE_NUM}" -gt 1 ] || [ "$(dirname "${FILE_PATH}")" != "${DOWNLOAD_DIR}" ]; then
        RELATIVE_PATH="${FILE_PATH#"${DOWNLOAD_DIR}/"}"
        TASK_NAME="${RELATIVE_PATH%%/*}"
        SOURCE_PATH="${DOWNLOAD_DIR}/${TASK_NAME}"
        GET_TARGET_PATH
        COMPLETED_DIR="${TARGET_PATH}/${TASK_NAME}"
        return
    elif [ "${FILE_NUM}" -eq 1 ]; then
        SOURCE_PATH="${FILE_PATH}"
        RELATIVE_PATH="${FILE_PATH#"${DOWNLOAD_DIR}/"}"
        # 单文件，去除.
        TASK_NAME="${RELATIVE_PATH%.*}"
        GET_TARGET_PATH
        return
    fi
}
```

## 文件路径：`./root/aria2/script/tracker.sh`

```
#!/usr/bin/env bash
#
# https://github.com/P3TERX/aria2.conf
# File name：tracker.sh
# Description: Get BT trackers and add to Aria2

RED_FONT_PREFIX="\033[31m"
GREEN_FONT_PREFIX="\033[32m"
YELLOW_FONT_PREFIX="\033[1;33m"
LIGHT_PURPLE_FONT_PREFIX="\033[1;35m"
FONT_COLOR_SUFFIX="\033[0m"
INFO="[${GREEN_FONT_PREFIX}INFO${FONT_COLOR_SUFFIX}]"
ERROR="[${RED_FONT_PREFIX}ERROR${FONT_COLOR_SUFFIX}]"
ARIA2_CONF=${1:-aria2.conf}
DOWNLOADER="curl -fsSL --connect-timeout 3 --max-time 3 --retry 2"
SCRIPT_CONF="/config/setting.conf"
NL=$'\n'
echo && echo -e "$INFO Get trackers ..."
ARIA2_CONF="/config/aria2.conf"

DATE_TIME() {
    date +"%Y/%m/%d %H:%M:%S"
}


GET_TRACKERS() {
    if [[ -z "${CTU}" ]]; then
        echo && echo -e "$(DATE_TIME) ${INFO} Get BT trackers..."
        TRACKER=$(
            ${DOWNLOADER} https://trackerslist.com/all_aria2.txt ||
                ${DOWNLOADER} https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all_aria2.txt ||
                ${DOWNLOADER} https://trackers.p3terx.com/all_aria2.txt
        )
    else
        echo && echo -e "$(DATE_TIME) ${INFO} Get BT trackers from url(s):${CTU} ..."
        URLS=$(echo ${CTU} | tr "," "$NL")
        for URL in $URLS; do
            TRACKER+="$(${DOWNLOADER} ${URL} | tr "," "\n")$NL"
        done
        TRACKER="$(echo "$TRACKER" | awk NF | sort -u | sed 'H;1h;$!d;x;y/\n/,/' )"
    fi

    [[ -z "${TRACKER}" ]] && {
        echo
        echo -e "$(DATE_TIME) ${ERROR} Unable to get trackers, network failure or invalid links." && exit 1
    }
}

ECHO_TRACKERS() {
    echo -e "
--------------------[BitTorrent Trackers]--------------------
${TRACKER}
--------------------[BitTorrent Trackers]--------------------
"
}


ADD_TRACKERS() {
    echo -e "$(DATE_TIME) ${INFO} 添加 BT trackers 到 Aria2 配置文件中 ${LIGHT_PURPLE_FONT_PREFIX}${ARIA2_CONF}${FONT_COLOR_SUFFIX} ..." && echo
    if [ ! -f ${ARIA2_CONF} ]; then
        echo -e "$(DATE_TIME) ${ERROR} '${ARIA2_CONF}' 不存在"
        exit 1
    else
        [ -z $(grep "bt-tracker=" ${ARIA2_CONF}) ] && echo "bt-tracker=" >>${ARIA2_CONF}
        sed -i "s@^\(bt-tracker=\).*@\1${TRACKER}@" ${ARIA2_CONF} && echo -e "$(DATE_TIME) ${INFO} 成功添加 BT trackers 到 Aria2 配置文件中!"
    fi
}

GET_TRACKERS
ECHO_TRACKERS
ADD_TRACKERS
```

## 文件路径：`./root/aria2/script/pause.sh`

```
#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"
. "$(dirname $0)/rpc_info"

TASK_GID=$1
FILE_NUM=$2
FILE_PATH=$3

GET_BASE_PATH
COMPLETED_PATH
GET_RPC_INFO
GET_FINAL_PATH

MOVE_PAUSED() {
    if [ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ]; then
        exit 0
    elif [ "${GET_PATH_INFO}" = "error" ]; then
        echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"
        exit 1
    else
        MOVE=true
        MOVE_FILE
        CHECK_TORRENT
    fi
}

if [ "${MPT}" = true ]; then
    MOVE_PAUSED
fi
```

## 文件路径：`./root/aria2/script/cron-restart-a2b.sh`

```
#!/bin/bash

# 获取环境变量 CRA2B 的值
CRA2B_VALUE=$CRA2B

# 检查 CRA2B 的值是否为 "false"
if [ "$CRA2B_VALUE" = "false" ]; then
    # 删除现有的 aria2b cron 任务
    (crontab -l | grep -v "ps -ef | grep aria2b | grep -v grep | awk '{print \$2}' | xargs kill -9") | crontab -
    echo "CRA2B 设置为 false。已移除定时重启 aria2b 定时任务。"
else
    # 使用 sed 提取用户输入中的数字部分
    HOURS=$(echo "$CRA2B_VALUE" | sed 's/[^0-9]*//g')
    
    # 检查 CRA2B 的值是否在 "1-24h" 范围内
    if [[ $HOURS =~ ^[1-9]$|^1[0-9]$|^2[0-4]$ ]]; then
        # 删除现有的 aria2b cron 任务
        (crontab -l | grep -v "ps -ef | grep aria2b | grep -v grep | awk '{print \$2}' | xargs kill -9") | crontab -
        echo "已移除现有的定时重启 aria2b 任务。"

        # 设置新的 cron job，在每小时的整点执行重启 aria2b 进程的命令
        (crontab -l ; echo "0 */$HOURS * * * ps -ef | grep aria2b | grep -v grep | awk '{print \$2}' | xargs kill -9") | crontab -
        echo "已设置定时任务，在每 $HOURS 小时的整点执行重启 aria2b 进程的命令。"
    else
        # 默认将 CRA2B 设置为 2 小时
        HOURS=2
        # 删除现有的 aria2b cron 任务
        (crontab -l | grep -v "ps -ef | grep aria2b | grep -v grep | awk '{print \$2}' | xargs kill -9") | crontab -
        echo "CRA2B 的值无效。已将 CRA2B 设置为默认值 2 小时。"

        # 设置新的 cron job，在整点执行重启 aria2b 进程的命令
        (crontab -l ; echo "0 */$HOURS * * * ps -ef | grep aria2b | grep -v grep | awk '{print \$2}' | xargs kill -9") | crontab -
        echo "已设置定时任务，在每 $HOURS 小时的整点执行重启 aria2b 进程的命令。"
    fi
fi
```

## 文件路径：`./root/aria2/script/completed.sh`

```
#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"
. "$(dirname $0)/rpc_info"

TASK_GID=$1
FILE_NUM=$2
FILE_PATH=$3

GET_BASE_PATH
COMPLETED_PATH
GET_RPC_INFO
GET_FINAL_PATH

if [ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ]; then
    exit 0
elif [ "${GET_PATH_INFO}" = "error" ]; then
    echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"
    exit 1
else
    MOVE_FILE
    CHECK_TORRENT
fi
```

## 文件路径：`./root/aria2/script/rpc_info`

```
#!/usr/bin/env bash

RPC_TASK_INFO() {
    if [[ "${SECRET}" ]]; then
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.tellStatus","id":"NG6","params":["token:'${SECRET}'","'${TASK_GID}'"]}'
    else
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.tellStatus","id":"NG6","params":["'${TASK_GID}'"]}'
    fi
    curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}"
}

# ==================================RPC删除任务==================================
REMOVE_REPEAT_TASK() {
    sleep 3s
    RPC_ADDRESS="localhost:${PORT}/jsonrpc"
    if [[ "${SECRET}" ]]; then
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.remove","id":"NG6","params":["token:'${SECRET}'","'${TASK_GID}'"]}'
    else
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.remove","id":"NG6","params":["'${TASK_GID}'"]}'
    fi
    curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}"
}

GET_RPC_RESULT() {
    RPC_ADDRESS="localhost:${PORT}/jsonrpc"
    RPC_RESULT="$(RPC_TASK_INFO)"
}

# ======================================================================

GET_DOWNLOAD_DIR() {
    [[ -z ${RPC_RESULT} ]] && {
        echo -e "$(DATE_TIME) ${ERROR} Aria2 RPC interface error!"
        exit 1
    }
    DOWNLOAD_DIR=$(echo "${RPC_RESULT}" | jq -r '.result.dir')
    [[ -z "${DOWNLOAD_DIR}" || "${DOWNLOAD_DIR}" = "null" ]] && {
        echo ${RPC_RESULT} | jq '.result'
        echo -e "$(DATE_TIME) ${ERROR} Failed to get download directory!"
        exit 1
    }
}

GET_TASK_STATUS() {
    TASK_STATUS=$(echo "${RPC_RESULT}" | jq -r '.result.status')
    [[ -z "${TASK_STATUS}" || "${TASK_STATUS}" = "null" ]] && {
        echo "${RPC_RESULT}" | jq '.result'
        echo -e "$(DATE_TIME) ${ERROR} Failed to get task status!"
        exit 1
    }
}

GET_INFO_HASH() {
    INFO_HASH=$(echo "${RPC_RESULT}" | jq -r '.result.infoHash')
    if [[ -z "${INFO_HASH}" ]]; then
        echo "${RPC_RESULT}" | jq '.result'
        echo -e "$(DATE_TIME) ${ERROR} Failed to get Info Hash!"
        exit 1
    elif [[ "${INFO_HASH}" = "null" ]]; then
        return 1
    else
        TORRENT_PATH="${DOWNLOAD_DIR}/${INFO_HASH}"
        TORRENT_FILE="${DOWNLOAD_DIR}/${INFO_HASH}.torrent"
    fi
}


GET_RPC_INFO() {
    GET_RPC_RESULT
    GET_TASK_STATUS
    GET_DOWNLOAD_DIR
    GET_INFO_HASH
}
```

## 文件路径：`./root/aria2/script/stop.sh`

```
#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"
. "$(dirname $0)/rpc_info"

TASK_GID=$1
FILE_NUM=$2
FILE_PATH=$3

GET_BASE_PATH
RECYCLE_PATH
GET_RPC_INFO
GET_FINAL_PATH

STOP() {
    if [ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ]; then
        exit 0
    elif [ "${GET_PATH_INFO}" = "error" ]; then
        echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"
        exit 1
    elif [ "${RMTASK}" = "recycle" ] && [ "${TASK_STATUS}" != "error" ]; then
        MOVE_RECYCLE
        CHECK_TORRENT
        RM_ARIA2
        exit 0
    elif [ "${RMTASK}" = "delete" ] && [ "${TASK_STATUS}" != "error" ]; then
        DELETE_FILE
        CHECK_TORRENT
        RM_ARIA2
        exit 0
    elif [ "${RMTASK}" = "rmaria" ] && [ "${TASK_STATUS}" != "error" ]; then
        CHECK_TORRENT
        RM_ARIA2
        exit 0
    fi
}

# 判断`SOURCE_PATH`是否存：start.sh可能已经删除文件或文件夹，不存在`SOURCE_PATH`则不进行任何操作
if [ -d "${SOURCE_PATH}" ] || [ -e "${SOURCE_PATH}" ]; then
    STOP
fi
```

## 文件路径：`./root/aria2/script/setting`

```
#!/usr/bin/env bash

SCRIPT_CONF="/config/setting.conf"

LOAD_CONF() {
    RMTASK="$(grep ^remove-task "${SCRIPT_CONF}" | cut -d= -f2-)"
    MOVE="$(grep ^move-task "${SCRIPT_CONF}" | cut -d= -f2-)"
    CF="$(grep ^content-filter "${SCRIPT_CONF}" | cut -d= -f2-)"
    DET="$(grep ^delete-empty-dir "${SCRIPT_CONF}" | cut -d= -f2-)"
    TOR="$(grep ^handle-torrent "${SCRIPT_CONF}" | cut -d= -f2-)"
    RRT="$(grep ^remove-repeat-task "${SCRIPT_CONF}" | cut -d= -f2-)"
    MPT="$(grep ^move-paused-task "${SCRIPT_CONF}" | cut -d= -f2-)"
}

SED_CONF() {
    # 复制用户配置文件
    cp /aria2/conf/setting.conf /config/setting.conf.new
    # 复原用户配置文件参数
    sed -i "s@^\(remove-task=\).*@\1${RMTASK}@" /config/setting.conf.new
    sed -i "s@^\(move-task=\).*@\1${MOVE}@" /config/setting.conf.new
    sed -i "s@^\(content-filter=\).*@\1${CF}@" /config/setting.conf.new
    sed -i "s@^\(delete-empty-dir=\).*@\1${DET}@" /config/setting.conf.new
    sed -i "s@^\(handle-torrent=\).*@\1${TOR}@" /config/setting.conf.new
    sed -i "s@^\(remove-repeat-task=\).*@\1${RRT}@" /config/setting.conf.new
    sed -i "s@^\(move-paused-task=\).*@\1${MPT}@" /config/setting.conf.new
    # 如某项参数不存在，则使用默认参数，防止程序运行出错
    if [[ -z "${RMTASK}" ]]; then
        sed -i "s@^\(remove-task=\).*@\1rmaria@" /config/setting.conf.new
    elif [[ -z "${MOVE}" ]]; then
        sed -i "s@^\(move-task=\).*@\1false@" /config/setting.conf.new
    elif [[ -z "${CF}" ]]; then
        sed -i "s@^\(content-filter=\).*@\1false@" /config/setting.conf.new
    elif [[ -z "${DET}" ]]; then
        sed -i "s@^\(delete-empty-dir=\).*@\1true@" /config/setting.conf.new
    elif [[ -z "${TOR}" ]]; then
        sed -i "s@^\(handle-torrent=\).*@\1backup-rename@" /config/setting.conf.new
    elif [[ -z "${RRT}" ]]; then
        sed -i "s@^\(remove-repeat-task=\).*@\1true@" /config/setting.conf.new
    elif [[ -z "${MPT}" ]]; then
        sed -i "s@^\(move-paused-task=\).*@\1false@" /config/setting.conf.new
    fi

    rm -f /config/setting.conf
    mv /config/setting.conf.new /config/setting.conf
}

LOAD_CONF
```

## 文件路径：`./root/aria2/script/start.sh`

```
#!/usr/bin/env bash

. "$(dirname $0)/setting"
. "$(dirname $0)/core"
. "$(dirname $0)/rpc_info"

TASK_GID=$1
FILE_NUM=$2
FILE_PATH=$3

GET_BASE_PATH
COMPLETED_PATH
GET_RPC_INFO
GET_FINAL_PATH

START() {
    # aria2开始任务时，单文件不会传递`FILE_PATH`，磁力`FILE_NUM`为0；`TASK_STATUS`为`error`时，多为存在`.aria2控制文件`,任务文件已存在
    # 判断`COMPLETED_DIR`是否存在已完成任务，如果有，则通过rpc删除该任务，同时删除该任务文件和控制文件
    if [ "${FILE_NUM}" -eq 0 ] || [ -z "${FILE_PATH}" ]; then
        exit 0
    elif [ "${GET_PATH_INFO}" = "error" ]; then
        echo -e "$(DATE_TIME) ${ERROR} GID:${TASK_GID} GET TASK PATH ERROR!"
        exit 1
    elif [ -d "${COMPLETED_DIR}" ] && [ "${TASK_STATUS}" != "error" ]; then
        echo -e "$(DATE_TIME) ${WARRING} 发现目标文件夹已存在当前任务 ${LIGHT_GREEN_FONT_PREFIX}${COMPLETED_DIR}${FONT_COLOR_SUFFIX}"
        echo -e "$(DATE_TIME) ${WARRING} 正在删除该任务，并清除相关文件... ${LIGHT_GREEN_FONT_PREFIX}${SOURCE_PATH}${FONT_COLOR_SUFFIX}"
        RM_ARIA2
        rm -rf "${SOURCE_PATH}"
        REMOVE_REPEAT_TASK
        exit 0
    fi
}

if [ "${RRT}" = "true" ]; then
    START
fi
```

## 文件路径：`./root/aria2/conf/文件过滤.conf`

```
## 文件过滤设置(全局) ##

# 仅 BT 多文件下载时有效，用于过滤无用文件。
# 可自定义；如需启用请删除对应行的注释 # 

# 排除小文件。低于此大小的文件将在下载完成后被删除。
#min-size=10M

# 保留文件类型。其它文件类型将在下载完成后被删除。
#include-file=mp4|mkv|rmvb|mov|avi|srt|ass

# 排除文件类型。排除的文件类型将在下载完成后被删除。
#exclude-file=html|url|lnk|txt|jpg|png

# 按关键词排除。包含以下关键字的文件将在下载完成后被删除。
#keyword-file=广告1|广告2|广告3

# 保留文件(正则表达式)。其它文件类型将在下载完成后被删除。
#include-file-regex=

# 排除文件(正则表达式)。排除的文件类型将在下载完成后被删除。
# 示例为排除比特彗星的 padding file
#exclude-file-regex="(.*/)_+(padding)(_*)(file)(.*)(_+)"```

## 文件路径：`./root/aria2/conf/aria2.conf.default`

```
## '#'开头为注释内容, 选项都有相应的注释说明, 根据需要修改 ##
## 被注释的选项使用的是默认值, 建议在需要使用时再取消注释  ##

## RPC相关设置 ##

# 启用RPC, 默认:false
enable-rpc=true
# 允许所有来源, 默认:false
rpc-allow-origin-all=true
# 允许非外部访问, 默认:false
rpc-listen-all=true
# 事件轮询方式, 取值:[epoll, kqueue, port, poll, select], 不同系统默认值不同
#event-poll=select
# RPC监听端口, 端口被占用时可以修改, 默认:6800
rpc-listen-port=6800
# 设置的RPC授权令牌, v1.18.4新增功能, 取代 --rpc-user 和 --rpc-passwd 选项
#rpc-secret=yourtoken
# 设置的RPC访问用户名（1.15.2以上，1.18.6以下版本）, 此选项新版已废弃, 建议改用 --rpc-secret 选项
#rpc-user=<USER>
# 设置的RPC访问密码（1.15.2以上，1.18.6以下版本）, 此选项新版已废弃, 建议改用 --rpc-secret 选项
#rpc-passwd=<PASSWD>
# 是否启用 RPC 服务的 SSL/TLS 加密,
# 启用加密后 RPC 服务需要使用 https 或者 wss 协议连接
# rpc-secure=true
# 在 RPC 服务中启用 SSL/TLS 加密时的证书文件(.pem/.crt)
# rpc-certificate=/config/ssl/full_chain.pem
# 在 RPC 服务中启用 SSL/TLS 加密时的私钥文件(.key)
# rpc-private-key=/config/ssl/private.key

## 文件保存相关 ##

# 文件的保存路径(可使用绝对路径或相对路径), 默认: 当前启动位置
dir=/downloads
# 启用磁盘缓存, 0为禁用缓存, 需1.16以上版本, 默认:16M
# disk-cache=512M
# 文件预分配方式, 能有效降低磁盘碎片, 默认:prealloc
# 预分配所需时间: none < falloc ? trunc < prealloc
# falloc和trunc则需要文件系统和内核支持
# NTFS、EXT4 建议使用 falloc, EXT3 建议 trunc, MAC 下需要注释此项
file-allocation=falloc
# 断点续传
continue=true
# 获取服务器文件时间，默认:false
remote-time=true

## 下载连接相关 ##

# 文件未找到重试次数，默认:0
# 重试时同时会记录重试次数，所以也需要设置 --max-tries 这个选项
max-file-not-found=5
# 最大尝试次数，0表示无限，默认:5
max-tries=0
# 重试等待时间（秒）, 默认:0
retry-wait=10
# 使用 UTF-8 处理 Content-Disposition ，默认:false
content-disposition-default-utf8=true
# 最大同时下载任务数, 运行时可修改, 默认:5，路由建议值: 3
max-concurrent-downloads=50
# 同一服务器连接数, 添加时可指定, 默认:1
max-connection-per-server=16
# 最小文件分片大小, 添加时可指定, 取值范围1M -1024M, 默认:20M
# 假定size=10M, 文件为20MiB 则使用两个来源下载; 文件为15MiB 则使用一个来源下载
min-split-size=4M
# 单个任务最大线程数, 添加时可指定, 默认:5，路由建议值: 5
split=16
# 整体下载速度限制, 运行时可修改, 默认:0
#max-overall-download-limit=0
# 单个任务下载速度限制, 默认:0
#max-download-limit=0
# 整体上传速度限制, 运行时可修改, 默认:0
max-overall-upload-limit=2M
# 单个任务上传速度限制, 默认:0
max-upload-limit=512K
# 禁用IPv6, 默认:false
disable-ipv6=true
# 支持GZip，默认:false
http-accept-gzip=true
# URI复用，默认: true
reuse-uri=false
# 禁用 netrc 支持，默认:false
no-netrc=true

## 进度保存相关 ##

# 从会话文件中读取下载任务
input-file=/config/aria2.session
# 在Aria2退出时保存`错误/未完成`的下载任务到会话文件
save-session=/config/aria2.session
# 定时保存会话, 0为退出时才保存, 需1.16.1以上版本, 默认:0
save-session-interval=1
# 自动保存任务进度，0为退出时才保存，默认：60
auto-save-interval=60
# 强制保存会话, 即使任务已经完成, 默认:false
# 较新的版本开启后会在任务完成后依然保留.aria2文件
force-save=false
# 允许覆盖，当相关控制文件不存在时从头开始重新下载。默认:false
allow-overwrite=false
## BT/PT下载相关 ##

# 当下载的是一个种子(以.torrent结尾)时, 自动开始BT任务, 默认:true，可选：false|mem
#follow-torrent=true
# BT监听端口, 当端口被屏蔽时使用, 默认:6881-6999
listen-port=6881
# 单个种子最大连接数，0为不限制，默认:55
bt-max-peers=100
# DHT（IPv4）文件
dht-file-path=/config/dht.dat
# DHT（IPv6）文件
# dht-file-path6=/root/.aria2/dht6.dat
# 打开DHT功能, PT需要禁用, 默认:true
enable-dht=true
# 打开IPv6 DHT功能, PT需要禁用
enable-dht6=false
# DHT网络监听端口, 默认:6881-6999
dht-listen-port=6881
# 本地节点查找, PT需要禁用, 默认:false
bt-enable-lpd=true
# 种子交换, PT需要禁用, 默认:true
enable-peer-exchange=true
# 期望下载速度，Aria2会临时提高连接数以提高下载速度，单位K或M。默认:50K
bt-request-peer-speed-limit=10M
# 客户端伪装, PT需要保持user-agent和peer-agent两个参数一致
user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36
#user-agent=qBittorrent v4.6.6
peer-agent=qBittorrent v4.6.6
peer-id-prefix=-qB4660-
#peer-agent=uTorrentMac/1870(43796)
#peer-id-prefix=-UM1870-
#peer-agent=Deluge 1.3.15
#peer-id-prefix=-DE13F0-
#peer-agent=Transmission/2.92
#peer-id-prefix=-TR2920-
# 当种子的分享率达到这个数时, 自动停止做种, 0为一直做种, 默认:1.0
seed-ratio=1.0
# 最小做种时间。此选项设置为0时，将在BT任务下载完成后不进行做种。
seed-time=0
# BT校验相关, 默认:true
#bt-hash-check-seed=true
# 继续之前的BT任务时, 无需再次校验, 默认:false
#bt-seed-unverified=true
# 保存磁力链接元数据为种子文件(.torrent文件), 默认:false
bt-save-metadata=false
# 加载已保存的元数据文件，默认:false
bt-load-saved-metadata=true
# 删除未选择文件，默认:false
bt-remove-unselected-file=true
# 保存上传的种子，默认:true
#rpc-save-upload-metadata=false

# 是否发送 Want-Digest HTTP 标头。默认：false (不发送)
# 部分网站会把此标头作为特征来检测和屏蔽 Aria2
#http-want-digest=false

## 执行额外命令 ##

# 下载停止后执行的命令（下载停止包含下载错误和下载完成这两个状态，如果没有单独设置，则执行此项命令。）
# 移动文件或文件夹至回收站/downloads/recycle,并删除.aria2后缀名文件
on-download-stop=/aria2/script/stop.sh
# 下载完成后执行的命令（移动文件或文件夹到/downloads/recycle)
on-download-complete=/aria2/script/completed.sh
# 下载错误后执行的命令（下载停止包含下载错误这个状态，如果没被设置或被注释，则执行下载停止后执行的命令。）
#on-download-error=
# 下载暂停后执行的命令
# 显示下载任务信息
on-download-pause=/aria2/script/pause.sh
# 下载开始后执行的命令
on-download-start=/aria2/script/start.sh

## BT服务器 ##
bt-tracker=```

## 文件路径：`./root/aria2/conf/setting.conf`

```
## docker aria2 功能设置 ##
# 配置文件为本项目的自定义设置选项
# 重置配置文件：删除本文件后重启容器
# 所有设置无需重启容器,即刻生效

# 删除任务，`delete`为删除任务后删除文件，`recycle`为删除文件至回收站，`rmaria`为只删除.aria2文件
remove-task=rmaria

# 下载完成后执行操作选项，默认`false`
# `true`，下载完成后保留目录结构移动
# `dmof`非自定义目录任务，单文件，不执行移动操作。自定义目录、单文件，保留目录结构移动（推荐）
move-task=false

# 文件过滤，任务下载完成后删除不需要的文件内容，`false`、`true`
# 由于aria2自身限制，无法在下载前取消不需要的文件（只能在任务完成后删除文件）
content-filter=false

# 下载完成后删除空文件夹，默认`true`，需要开启文件过滤功能才能生效
# 开启内容过滤后，可能会产生空文件夹，开启`DET`选项后可以删除当前任务中的空文件夹
delete-empty-dir=true

# 对磁力链接生成的种子文件进行操作
# 在开启`SMD`选项后生效，上传的种子无法更名、移动、删除，仅对通过磁力链接保存的种子生效
# 默认保留`retain`,可选删除`delete`，备份种子文件`backup`、重命名种子文件`rename`，重命名种子文件并备份`backup-rename`
# 种子备份位于`/config/backup-torrent`
handle-torrent=backup-rename

# 删除重复任务，检测已完成文件夹，如果有该任务文件，则删除任务，并删除文件，仅针对文件数量大于1的任务生效
# 默认`true`，可选`false`关闭该功能
remove-repeat-task=true

# 任务暂停后移动文件，部分任务下载至百分之99时无法下载，可以启动本选项
# 建议仅在需要时开启该功能，使用完后请记得关闭
# 默认`false`，可选`true`开启该功能
move-paused-task=false
```

## 文件路径：`./root/aria2/conf/rpc-tracker0`

```
# do daily/weekly/monthly maintenance
# min   hour    day     month   weekday command
0       *       *       *       *       run-parts /etc/periodic/hourly
0       2       *       *       *       run-parts /etc/periodic/daily
0       3       *       *       6       run-parts /etc/periodic/weekly
0       5       1       *       *       run-parts /etc/periodic/monthly```

## 文件路径：`./root/aria2/conf/rpc-tracker1`

```
# do daily/weekly/monthly maintenance
# min   hour    day     month   weekday command
0       5       *       *       *       bash /aria2/script/rpc_tracker.sh```

## 文件路径：`./root/etc/cont-init.d/40-config`

```
#!/usr/bin/with-contenv bash

# permissions
chown -R abc:abc \
    /config \
    /www \
    /downloads
  
chmod a+x \
  /aria2/script/*

# set cron-restart-a2b
bash /aria2/script/cron-restart-a2b.sh
```

## 文件路径：`./root/etc/cont-init.d/90-custom-folders`

```
#!/usr/bin/with-contenv bash
```

## 文件路径：`./root/etc/cont-init.d/99-custom-scripts`

```
#!/usr/bin/with-contenv bash
```

## 文件路径：`./root/etc/cont-init.d/20-config`

```
#!/usr/bin/with-contenv bash

# make folders
mkdir -p \
	/config/ssl \
  /config/logs \
  /config/backup-torrent \
  /downloads/completed \
  /downloads/recycle

# copy files
if [[ ! -e /config/aria2.conf ]]
then
  cp /aria2/conf/aria2.conf.default /config/aria2.conf
fi

if [[ ! -e /config/setting.conf ]]
then
  cp /aria2/conf/setting.conf /config/setting.conf
fi

# 保留配置、更新修改配置文件
if [[ -e /config/setting.conf ]]
then
  . /aria2/script/setting
  SED_CONF
fi

if [[ ! -e /config/文件过滤.conf ]]
then
  cp /aria2/conf/文件过滤.conf /config/文件过滤.conf
fi

if [[ ! -e /config/aria2.session ]]
then
  touch /config/aria2.session
fi

if [[ ! -e /config/dht.dat ]]
then
  touch /config/dht.dat
fi

# 2021.03.15 变更：日志文件地址变更为`/config/logs`
if [[ -e /config/move.log || -e /config/recycle.log || -e /config/delete.log || -e /config/文件过滤日志.log ]]
then
  mv /config/*.log /config/logs/
fi

# 创建日志文件
if [[ ! -e /config/logs/move.log ]]
then
  touch /config/logs/move.log
fi

if [[ ! -e /config/logs/recycle.log ]]
then
  touch /config/logs/recycle.log
fi

if [[ ! -e /config/logs/delete.log ]]
then
  touch /config/logs/delete.log
fi

if [[ ! -e /config/logs/文件过滤日志.log ]]
then
  touch /config/logs/文件过滤日志.log
fi```

## 文件路径：`./root/etc/cont-init.d/11-version`

```
#!/usr/bin/with-contenv bash

echo "
-------------------------------------

当前正在运行Docker-Aria2 & AriaNg版本为：
$(cat /aria2/build-date)

Aria2c版本为：
1.37.0

更新内容请见：
https://github.com/SuperNG6/docker-aria2
https://sleele.com/2019/09/27/docker-aria2的最佳实践

-------------------------------------"```

## 文件路径：`./root/etc/cont-init.d/30-config`

```
#!/usr/bin/with-contenv bash

# extra function
sed -i 's@^\(on-download-stop=\).*@\1/aria2/script/stop.sh@' /config/aria2.conf
sed -i 's@^\(on-download-complete=\).*@\1/aria2/script/completed.sh@' /config/aria2.conf
sed -i "s/.*on-download-pause.*/on-download-pause=\/aria2\/script\/pause.sh/" /config/aria2.conf
sed -i "s/.*on-download-start.*/on-download-start=\/aria2\/script\/start.sh/" /config/aria2.conf
# port
sed -i "s@^\(rpc-listen-port=\).*@\1${PORT}@" /config/aria2.conf
sed -i "s@^\(dht-listen-port=\).*@\1${BTPORT}@" /config/aria2.conf
sed -i "s@^\(listen-port=\).*@\1${BTPORT}@" /config/aria2.conf

# bt-save-metadata
if [[ "$SMD" = "true" ]]
then
    sed -i 's@^\(bt-save-metadata=\).*@\1true@' /config/aria2.conf
else
    sed -i 's@^\(bt-save-metadata=\).*@\1false@' /config/aria2.conf
fi

# file-allocation
if [[ "$FA" = "falloc" ]]
then
    sed -i 's@^\(file-allocation=\).*@\1falloc@' /config/aria2.conf
elif [[ "$FA" = "trunc" ]]
then
    sed -i 's@^\(file-allocation=\).*@\1trunc@' /config/aria2.conf
elif [[ "$FA" = "prealloc" ]]
then
    sed -i 's@^\(file-allocation=\).*@\1prealloc@' /config/aria2.conf
else
    sed -i 's@^\(file-allocation=\).*@\1none@' /config/aria2.conf 
fi

# auto updatetracker
if [ "$UT" == "true" ]
then
  bash /aria2/script/tracker.sh
fi

# rpc update tracker
if [ "$RUT" == "true" ]
then
  cp /aria2/conf/rpc-tracker1 /etc/crontabs/root
  /usr/sbin/crond
else
  cp /aria2/conf/rpc-tracker0 /etc/crontabs/root
fi

```

## 文件路径：`./root/etc/services.d/aria2b/run`

```
#!/usr/bin/with-contenv bash

if [ "$A2B" == "true" ]
then
  exec aria2b -c "/config/aria2.conf" -u "http://127.0.0.1:${PORT}/jsonrpc" -s $SECRET
fi
```

## 文件路径：`./root/etc/services.d/aria2/run`

```
#!/usr/bin/with-contenv bash

if [[ ! -z $SECRET ]];then
  SECRET_TOKEN="--rpc-secret=${SECRET}"
fi

exec \
	s6-setuidgid abc aria2c \
    --conf-path=/config/aria2.conf \
    $SECRET_TOKEN \
    --disk-cache=$CACHE \
    --quiet=$QUIET
  > /dev/stdout \
  2 > /dev/stderr

echo 'Exiting aria2'
```

## 文件路径：`./docker-compose.yml`

```
version: "3.6"
services:
  aria2:
    image: superng6/aria2:a2b-latest
    container_name: aria2
    network_mode: host
    cap_add:
      - NET_ADMIN
    environment:
      - PUID=1026
      - PGID=100
      - TZ=Asia/Shanghai
      - SECRET=yourtoken
      - CACHE=512M
      - PORT=6800
      - WEBUI=true
      - WEBUI_PORT=8080
      - BTPORT=32516
      - UT=true
      - QUIET=true
      - SMD=true
      - A2B=true
      - CRA2B=2h
    volumes:
      - $PWD/config:/config
      - $PWD/downloads:/downloads
      - /lib/modules:/lib/modules
    restart: unless-stopped   ```

