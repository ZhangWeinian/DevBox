#!/bin/bash

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"
DOCKERFILE_PATH=".devcontainer/Dockerfile"
CONTEXT=".devcontainer"

echo "==> 构建镜像: ${IMAGE_NAME}:${TAG}"
DOCKER_BUILDKIT=1 docker build -t "${IMAGE_NAME}:${TAG}" -f "${DOCKERFILE_PATH}" "${CONTEXT}"
echo "==> 构建完成"
