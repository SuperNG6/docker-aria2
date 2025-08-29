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
echo "Download binary file: ${ARCH} completed"