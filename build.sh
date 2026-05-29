#!/usr/bin/env bash
# 本地构建入口：默认构建 standard；传 a2b/all 可验证 BT 优化变体。
# 与 CI 保持一致：a2b 构建必须同时传 VARIANT=a2b 和 A2B_DEFAULT=true。

set -euo pipefail

IMAGE="${IMAGE:-superng6/aria2}"
NO_CACHE="${NO_CACHE:-true}"
VARIANT="${1:-standard}"

DOCKER_ARGS=(--force-rm)
[ "${NO_CACHE}" = "true" ] && DOCKER_ARGS+=(--no-cache)

build_variant() {
    local variant=$1 tag=$2 a2b_default=$3
    echo "构建 ${IMAGE}:${tag} (VARIANT=${variant}, A2B_DEFAULT=${a2b_default})"
    docker build \
        "${DOCKER_ARGS[@]}" \
        --build-arg "VARIANT=${variant}" \
        --build-arg "A2B_DEFAULT=${a2b_default}" \
        --tag "${IMAGE}:${tag}" \
        .
}

case "${VARIANT}" in
    standard)
        build_variant standard dev-latest false
        ;;
    a2b)
        build_variant a2b a2b-dev-latest true
        ;;
    all)
        build_variant standard dev-latest false
        build_variant a2b a2b-dev-latest true
        ;;
    *)
        echo "用法: $0 [standard|a2b|all]" >&2
        echo "可选环境变量: IMAGE=superng6/aria2 NO_CACHE=true|false" >&2
        exit 2
        ;;
esac
