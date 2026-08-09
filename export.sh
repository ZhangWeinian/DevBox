#!/bin/bash

# 用法：
#   ./export.sh                 # 导出到当前目录
#   ./export.sh /path/to/dir    # 导出到指定目录（不存在则自动创建）

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
OUTPUT_FILENAME="devenv-${ARCH_NAME}-${DATE}.tar"

# 处理输出目录
OUTPUT_DIR="${1:-.}"                 # 若未传参，默认为当前目录
mkdir -p "${OUTPUT_DIR}"             # 确保目录存在（会自动创建父目录）
OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILENAME}"

echo "==> 导出镜像 ${IMAGE_NAME}:${TAG} 到 ${OUTPUT_PATH} (架构: ${ARCH_NAME})"
docker save "${IMAGE_NAME}:${TAG}" -o "${OUTPUT_PATH}"
echo "==> 导出完成，文件: ${OUTPUT_PATH} ($(du -h "${OUTPUT_PATH}" | cut -f1))"
