#!/bin/bash

# 用法：
#   ./import.sh                           # 错误，输出帮助
#   ./import.sh /path/to/code             # 挂载指定目录启动容器（镜像必须已存在）
#   ./import.sh myimage.tar               # 仅加载 tar（若已有同名镜像则删除并重新加载）
#   ./import.sh myimage.tar /path/to/code # 加载 tar 并启动容器，挂载指定目录

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"
CONTAINER_NAME="dev-container"

# 帮助
show_help() {
    cat <<EOF
用法:
  $0                              # 错误，显示帮助
  $0 /path/to/code                # 启动容器，挂载指定目录（镜像必须已存在）
  $0 myimage.tar                  # 仅加载镜像 tar（若已有同名镜像则删除并重新加载）
  $0 myimage.tar /path/to/code    # 加载镜像 tar 并启动容器，挂载指定目录

说明:
  镜像名称固定为 ${FULL_IMAGE}
  容器名称固定为 ${CONTAINER_NAME}
  挂载后，容器内路径为 /home/vscode/workspace/<目录名>
EOF
}

# 检查参数
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

TAR_FILE=""
MOUNT_DIR=""

if [ $# -eq 1 ]; then
    if [[ "$1" == *.tar ]]; then
        TAR_FILE="$1"
    else
        MOUNT_DIR="$1"
    fi
elif [ $# -eq 2 ]; then
    if [[ "$1" == *.tar ]]; then
        TAR_FILE="$1"
        MOUNT_DIR="$2"
    else
        echo "错误: 第一个参数必须是 .tar 文件"
        show_help
        exit 1
    fi
else
    echo "错误: 参数数量不正确"
    show_help
    exit 1
fi

# 处理挂载目录（如果指定）
if [ -n "${MOUNT_DIR}" ]; then
    if ! MOUNT_DIR="$(cd "${MOUNT_DIR}" 2>/dev/null && pwd)"; then
        echo "错误: 无法解析目录 '${MOUNT_DIR}'"
        exit 1
    fi
fi

# 加载镜像（如果指定 tar）
if [ -n "${TAR_FILE}" ]; then
    if [ ! -f "${TAR_FILE}" ]; then
        echo "错误: tar 文件 '${TAR_FILE}' 不存在"
        exit 1
    fi

    # 检查是否存在同名镜像
    if docker image inspect "${FULL_IMAGE}" >/dev/null 2>&1; then
        echo "==> 检测到已存在镜像 ${FULL_IMAGE}，将删除并重新加载"
        docker rmi -f "${FULL_IMAGE}" >/dev/null 2>&1
    fi

    echo "==> 加载镜像: ${TAR_FILE}"
    docker load -i "${TAR_FILE}"
    echo "==> 镜像加载完成"
fi

# 如果仅加载 tar，则退出
if [ -z "${MOUNT_DIR}" ]; then
    echo "==> 仅加载镜像，不启动容器"
    exit 0
fi

# 启动容器
# 确保镜像存在
if ! docker image inspect "${FULL_IMAGE}" >/dev/null 2>&1; then
    echo "错误: 镜像 ${FULL_IMAGE} 不存在，请先加载或构建"
    exit 1
fi

# 停止并删除旧容器
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "==> 停止并删除旧容器: ${CONTAINER_NAME}"
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

# 提取挂载目录的最后一个文件夹名
MOUNT_BASENAME=$(basename "${MOUNT_DIR}")
CONTAINER_TARGET="/home/vscode/workspace/${MOUNT_BASENAME}"

echo "==> 启动容器: ${CONTAINER_NAME}"
echo "    挂载宿主机目录: ${MOUNT_DIR} -> ${CONTAINER_TARGET}"

docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart unless-stopped \
    -v "${MOUNT_DIR}:${CONTAINER_TARGET}" \
    "${FULL_IMAGE}"

echo "==> 容器已启动，名称: ${CONTAINER_NAME}"
echo "    进入容器: docker exec -it ${CONTAINER_NAME} bash"
echo "    容器内代码位于: ${CONTAINER_TARGET}"
echo "    使用 VSCode 附加: 打开命令面板 -> '开发容器: 附加到正在运行的容器...'"
