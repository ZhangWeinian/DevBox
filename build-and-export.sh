#!/bin/bash

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"
DATE=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${IMAGE_NAME}-${DATE}.tar"

echo "========================================"
echo " 构建并导出开发环境镜像"
echo " 镜像：${IMAGE_NAME}:${TAG}"
echo " 输出：${OUTPUT_FILE}"
echo "========================================"

echo ""
echo "==> [1/2] 构建镜像（预装所有库）..."
DOCKER_BUILDKIT=1 docker build \
    -t ${IMAGE_NAME}:${TAG} \
    -f .devcontainer/Dockerfile \
    .devcontainer

echo ""
echo "==> [2/2] 导出镜像到 tar 包..."
docker save ${IMAGE_NAME}:${TAG} -o ${OUTPUT_FILE}

echo ""
echo "========================================"
echo " 完成！"
echo " 文件：$(pwd)/${OUTPUT_FILE}"
echo " 大小：$(du -sh ${OUTPUT_FILE} | cut -f1)"
echo ""
echo " 传输到目标设备后："
echo "   docker load -i ${OUTPUT_FILE}"
echo "   docker run -d --name dev-container -v /path/to/code:/workspaces/project ${IMAGE_NAME}:${TAG}"
echo "========================================"