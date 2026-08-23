#!/bin/bash

# 用法：
#   ./export.sh                 # 导出压缩包到当前目录
#   ./export.sh /path/to/dir    # 导出压缩包到指定目录（不存在则自动创建）

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"

# 确保待导出的镜像存在
if ! docker image inspect "${FULL_IMAGE}" >/dev/null 2>&1; then
    echo "错误: 镜像 ${FULL_IMAGE} 不存在，请先构建" >&2
    exit 1
fi

ARCH_NAME="$(docker image inspect "${FULL_IMAGE}" --format '{{.Architecture}}')"
DATE=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILENAME="devenv-${ARCH_NAME}-${DATE}.tar.gz"

# 处理输出目录
OUTPUT_DIR="${1:-.}"
mkdir -p "${OUTPUT_DIR}"
OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILENAME}"

echo "==> 导出并压缩镜像 ${FULL_IMAGE} 到 ${OUTPUT_PATH} (镜像架构: ${ARCH_NAME})"
docker save "${FULL_IMAGE}" | gzip -c > "${OUTPUT_PATH}"
echo "==> 导出完成，文件: ${OUTPUT_PATH} ($(du -h "${OUTPUT_PATH}" | cut -f1))"
