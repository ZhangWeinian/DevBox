#!/bin/bash

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"

# 获取当前系统架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_NAME="amd64" ;;
    aarch64) ARCH_NAME="arm64" ;;
    *)       ARCH_NAME="$ARCH" ;;
esac

DATE=$(date +%Y%m%d_%H%M%S)
OUTPUT="devenv-${ARCH_NAME}-${DATE}.tar"

echo "==> 导出镜像 ${IMAGE_NAME}:${TAG} 到 ${OUTPUT} (架构: ${ARCH_NAME})"
docker save "${IMAGE_NAME}:${TAG}" -o "${OUTPUT}"
echo "==> 导出完成，文件: ${OUTPUT} ($(du -h ${OUTPUT} | cut -f1))"
