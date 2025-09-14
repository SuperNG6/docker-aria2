#!/usr/bin/env bash

# 定义颜色变量
INFO="\033[1;32m[INFO]\033[0m"
ERROR="\033[1;31m[ERROR]\033[0m"

# Check CPU architecture
ARCH=$(uname -m)
ARIA2_VERSION=1.36.0
echo -e "${INFO} Check CPU architecture ..."
if [[ ${ARCH} == "x86_64" ]]; then
    ARCH="aria2-${ARIA2_VERSION}-static-linux-amd64.tar.gz"
elif [[ ${ARCH} == "aarch64" ]]; then
    ARCH="aria2-${ARIA2_VERSION}-static-linux-arm64.tar.gz"
elif [[ ${ARCH} == "armv7l" ]]; then
    ARCH="aria2-${ARIA2_VERSION}-static-linux-armhf.tar.gz"
else
    echo -e "${ERROR} This architecture is not supported."
    exit 1
fi

# Download files
echo "Downloading binary file: ${ARCH}"
curl -L "https://github.com/SuperNG6/docker-aria2/releases/download/2021.08.24/${ARCH}" | tar -xz
mv aria2c /usr/local/bin
echo "Download binary file: ${ARCH} completed"