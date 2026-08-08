#!/bin/bash

# 导入镜像 tar 包并/或启动开发容器
# 用法：
#   ./import.sh                           # 若镜像存在，删除旧容器并用镜像启动（不挂载）；若不存在报错
#   ./import.sh /path/to/code             # 挂载指定目录启动容器（镜像必须已存在）
#   ./import.sh myimage.tar               # 仅加载 tar（若已有同名镜像则删除并重新加载）
#   ./import.sh myimage.tar /path/to/code # 加载 tar 并启动容器，挂载指定目录
#   ./import.sh -h|--help                 # 显示帮助

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"
CONTAINER_NAME="dev-container"

show_help() {
    cat <<EOF
用法:
  $0                              # 若镜像存在，删除旧容器并用镜像启动（不挂载）；若不存在报错
  $0 /path/to/code                # 启动容器，挂载指定目录（镜像必须已存在）
  $0 myimage.tar                  # 仅加载镜像 tar（若已有同名镜像则删除并重新加载）
  $0 myimage.tar /path/to/code    # 加载镜像 tar 并启动容器，挂载指定目录
  $0 -h|--help                    # 显示帮助

说明:
  镜像名称固定为 ${FULL_IMAGE}
  容器名称固定为 ${CONTAINER_NAME}
  当指定挂载目录时，容器内路径为 /home/vscode/workspace/<目录名>
EOF
}

# 处理帮助
if [ $# -eq 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
    show_help
    exit 0
fi

TAR_FILE=""
MOUNT_DIR=""
JUST_LOAD=false

# 无参数：启动容器但不挂载目录（镜像必须存在）
if [ $# -eq 0 ]; then
    if ! docker image inspect "${FULL_IMAGE}" >/dev/null 2>&1; then
        echo "错误: 镜像 ${FULL_IMAGE} 不存在，请先加载或构建"
        exit 1
    fi
    # MOUNT_DIR 保持为空，进入启动逻辑
else
    # 有参数解析
    if [ $# -eq 1 ]; then
        if [[ "$1" == *.tar ]]; then
            TAR_FILE="$1"
            JUST_LOAD=true   # 仅加载 tar，不启动
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

    if docker image inspect "${FULL_IMAGE}" >/dev/null 2>&1; then
        echo "==> 检测到已存在镜像 ${FULL_IMAGE}，将删除并重新加载"
        docker rmi -f "${FULL_IMAGE}" >/dev/null 2>&1
    fi

    echo "==> 加载镜像: ${TAR_FILE}"
    docker load -i "${TAR_FILE}"
    echo "==> 镜像加载完成"
fi

# 如果仅是加载 tar，则退出
if [ "${JUST_LOAD}" = true ] && [ -z "${MOUNT_DIR}" ]; then
    echo "==> 仅加载镜像，不启动容器"
    exit 0
fi

# 启动容器（镜像必须存在）
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

# 构建 docker run 参数
DOCKER_RUN_ARGS=(
    -d
    --name "${CONTAINER_NAME}"
    --restart unless-stopped
)

if [ -n "${MOUNT_DIR}" ]; then
    MOUNT_BASENAME=$(basename "${MOUNT_DIR}")
    CONTAINER_TARGET="/home/vscode/workspace/${MOUNT_BASENAME}"
    DOCKER_RUN_ARGS+=(-v "${MOUNT_DIR}:${CONTAINER_TARGET}")
    echo "==> 启动容器（挂载目录）: ${CONTAINER_NAME}"
    echo "    挂载宿主机目录: ${MOUNT_DIR} -> ${CONTAINER_TARGET}"
else
    echo "==> 启动容器（无挂载）: ${CONTAINER_NAME}"
fi

docker run "${DOCKER_RUN_ARGS[@]}" "${FULL_IMAGE}"

echo "==> 容器已启动，名称: ${CONTAINER_NAME}"
echo "    进入容器: docker exec -it ${CONTAINER_NAME} bash"
if [ -n "${MOUNT_DIR}" ]; then
    echo "    容器内代码位于: ${CONTAINER_TARGET}"
fi
echo "    使用 VSCode 附加: 打开命令面板 -> '开发容器: 附加到正在运行的容器...'"
