#!/bin/bash

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"
DOCKERFILE_PATH=".devcontainer/Dockerfile"
CONTEXT=".devcontainer"

HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
    x86_64|amd64)
        ;;
    *)
        echo "错误：不支持在当前宿主机架构上构建此镜像" >&2
        echo "  检测到宿主机架构: ${HOST_ARCH}" >&2
        echo "  本 Dockerfile 的交叉编译工具链与 vcpkg triplet 均假设宿主机为 x86_64(amd64)" >&2
        echo "  请改用 x86_64 机器 / CI runner 构建，" >&2
        echo "  或参考本脚本 --force-emulate 选项，用 QEMU 模拟 amd64（速度会明显变慢）" >&2
        exit 1
        ;;
esac

USE_CACHE=0
for arg in "$@"; do
    case "$arg" in
        --use-cache)
            USE_CACHE=1
            ;;
        -h|--help)
            echo "用法: $0 [--use-cache]"
            echo ""
            echo "  默认（不带参数）：完全重新构建（--no-cache --pull）"
            echo "      系统包、工具链、vcpkg 依赖全部拉取构建这一刻的最新版本"
            echo "      适用于正式构建 / 定期刷新"
            echo ""
            echo "  --use-cache：吃 Docker 层缓存，仅供调试 Dockerfile 时加速迭代"
            echo "      不保证是最新版本，正式使用前请去掉此参数重新构建一次"
            exit 0
            ;;
        *)
            echo "未知参数: $arg" >&2
            echo "使用 -h 查看用法" >&2
            exit 1
            ;;
    esac
done

BUILD_ARGS=(--pull)
if [ "${USE_CACHE}" -eq 0 ]; then
    BUILD_ARGS+=(--no-cache)
fi

echo "==> 构建镜像: ${IMAGE_NAME}:${TAG}（use_cache=${USE_CACHE}）"
DOCKER_BUILDKIT=1 docker build "${BUILD_ARGS[@]}" -t "${IMAGE_NAME}:${TAG}" -f "${DOCKERFILE_PATH}" "${CONTEXT}"
echo "==> 构建完成"
