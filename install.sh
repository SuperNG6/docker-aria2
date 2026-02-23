#!/usr/bin/env bash

# Check CPU architecture
ARCH=$(uname -m)
ARIA2_VERSION=1.36.0
INFO="[INFO]"
ERROR="[ERROR]"
echo -e "${INFO} Check CPU architecture ..."
if [[ ${ARCH} == "x86_64" ]]; then
    ARCHIVE_NAME="aria2-${ARIA2_VERSION}-static-linux-amd64.tar.gz"
elif [[ ${ARCH} == "aarch64" ]]; then
    ARCHIVE_NAME="aria2-${ARIA2_VERSION}-static-linux-arm64.tar.gz"
elif [[ ${ARCH} == "armv7l" ]]; then
    ARCHIVE_NAME="aria2-${ARIA2_VERSION}-static-linux-armhf.tar.gz"
else
    echo -e "${ERROR} This architecture is not supported."
    exit 1
fi

# Download files
echo "Downloading binary file: ${ARCHIVE_NAME}"
curl -L "https://github.com/SuperNG6/docker-aria2/releases/download/2021.08.24/${ARCHIVE_NAME}" | tar -xz
mv aria2c /usr/local/bin
echo "Download binary file: ${ARCHIVE_NAME} completed"
