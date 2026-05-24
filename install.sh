#!/usr/bin/env bash
# 从本仓库固定 release 下载对应架构的 aria2c 静态二进制并安装到 /usr/local/bin
# 固定到 ci-20260521-134555-UTC，避免上游 latest 变动影响复现
# Asset 命名约定：aria2-static-linux-<arch>.tar.gz

INFO="\033[1;32m[INFO]\033[0m"
ERROR="\033[1;31m[ERROR]\033[0m"

case "$(uname -m)" in
    x86_64)  ASSET="aria2-static-linux-x86_64.tar.gz" ;;
    aarch64) ASSET="aria2-static-linux-arm64.tar.gz"  ;;
    armv7l)  ASSET="aria2-static-linux-armhf.tar.gz"  ;;
    i?86)    ASSET="aria2-static-linux-i386.tar.gz"   ;;
    *)
        echo -e "${ERROR} 不支持的 CPU 架构：$(uname -m)"
        exit 1
        ;;
esac

URL="https://github.com/SuperNG6/docker-aria2/releases/download/ci-20260521-134555-UTC/${ASSET}"
echo -e "${INFO} 下载 ${ASSET}"
echo -e "${INFO} 来源 ${URL}"

# curl -f 让 HTTP 错误立即返回非零；pipefail 让管道任意一环失败都终止
set -o pipefail
if ! curl -fL "${URL}" | tar -xz; then
    echo -e "${ERROR} 下载或解压失败"
    exit 1
fi

mv aria2c /usr/local/bin/
echo -e "${INFO} aria2c 已安装到 /usr/local/bin"
