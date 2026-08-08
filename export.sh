#!/bin/bash

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"
DATE=$(date +%Y%m%d_%H%M%S)
OUTPUT="devenv-${DATE}.tar"

echo "==> 导出镜像 ${IMAGE_NAME}:${TAG} 到 ${OUTPUT}"
docker save "${IMAGE_NAME}:${TAG}" -o "${OUTPUT}"
echo "==> 导出完成，文件: ${OUTPUT} ($(du -h ${OUTPUT} | cut -f1))"
