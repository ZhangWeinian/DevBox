#!/bin/bash

# 导入镜像 tar 包并启动开发容器
# 用法：
#   ./import.sh                           # 若本地镜像存在，启动容器并自动挂载 ~/workspace（目录不存在则创建）；否则报错
#   ./import.sh /path/to/code             # 若本地镜像存在，启动容器并挂载指定目录；否则报错
#   ./import.sh myimage.tar               # 加载 tar，删除旧容器/镜像，启动新容器并自动挂载 ~/workspace（目录不存在则创建）
#   ./import.sh myimage.tar /path/to/code # 加载 tar，删除旧容器/镜像，启动新容器并挂载指定目录
#   ./import.sh --allow-arch-mismatch ... # 跳过架构一致性检查（允许 QEMU 模拟运行，会明显变慢）
#   ./import.sh -h|--help                 # 显示帮助

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"
CONTAINER_NAME="dev-container"

show_help() {
    cat <<EOF
用法:
  $0                              # 若本地镜像存在，启动容器并自动挂载 ~/workspace（目录不存在则创建）；否则报错
  $0 /path/to/code                # 若本地镜像存在，启动容器并挂载指定目录；否则报错
  $0 myimage.tar                  # 加载 tar，删除旧容器/镜像，启动新容器并自动挂载 ~/workspace（目录不存在则创建）
  $0 myimage.tar /path/to/code    # 加载 tar，删除旧容器/镜像，启动新容器并挂载指定目录
  $0 --allow-arch-mismatch [...]  # 跳过镜像架构与宿主机架构的一致性检查
                                     （默认会拒绝运行架构不匹配的镜像，因为该镜像目前只按 amd64 构建）
  $0 -h|--help                    # 显示帮助

说明:
  镜像名称固定为 ${FULL_IMAGE}
  容器名称固定为 ${CONTAINER_NAME}
  如果指定了 tar 包，则强制从 tar 加载，覆盖本地同名镜像。
  如果未指定 tar，则使用本地镜像，若不存在则报错。
  默认挂载目录为 ~/workspace（不存在则自动创建）。
EOF
}

ALLOW_ARCH_MISMATCH=0
ARGS=()
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
        --allow-arch-mismatch)
            ALLOW_ARCH_MISMATCH=1
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

TAR_FILE=""
MOUNT_DIR=""

# 解析剩余的位置参数
if [ $# -eq 0 ]; then
    # 无参数：不加载 tar，不指定目录
    :
elif [ $# -eq 1 ]; then
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

# 处理挂载目录
# 如果未指定挂载目录，则使用默认的 ~/workspace
if [ -z "${MOUNT_DIR}" ]; then
    MOUNT_DIR="${HOME}/workspace"
    mkdir -p "${MOUNT_DIR}"
    echo "==> 未指定挂载目录，使用默认目录: ${MOUNT_DIR}"
fi

# 将挂载目录转为绝对路径（如果失败则退出）
if ! MOUNT_DIR="$(cd "${MOUNT_DIR}" 2>/dev/null && pwd)"; then
    echo "错误: 无法解析目录 '${MOUNT_DIR}'"
    exit 1
fi

# 处理 tar 包（高优先级）
if [ -n "${TAR_FILE}" ]; then
    if [ ! -f "${TAR_FILE}" ]; then
        echo "错误: tar 文件 '${TAR_FILE}' 不存在"
        exit 1
    fi

    # 强制清理：停止并删除现有容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "==> 停止并删除容器 ${CONTAINER_NAME}"
        docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
        docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi

    # 删除旧镜像（如果有）
    if docker image inspect "${FULL_IMAGE}" >/dev/null 2>&1; then
        echo "==> 删除旧镜像 ${FULL_IMAGE}"
        docker rmi -f "${FULL_IMAGE}" >/dev/null 2>&1
    fi

    echo "==> 加载镜像: ${TAR_FILE}"
    docker load -i "${TAR_FILE}"
    echo "==> 镜像加载完成"
fi

# 确保镜像存在
if ! docker image inspect "${FULL_IMAGE}" >/dev/null 2>&1; then
    echo "错误: 镜像 ${FULL_IMAGE} 不存在，请先构建或提供有效的 tar 包"
    exit 1
fi

# 防御性检测：镜像架构 与 宿主机架构 是否一致
# 该镜像目前只按 amd64 单向构建（交叉编译工具链、vcpkg triplet 均硬编码此假设），
# 若在非 amd64 宿主机上运行，Docker 会尝试用 QEMU 静默模拟（若已注册 binfmt handler），
# 表现为运行起来但速度奇慢；若未注册 QEMU，则会在启动容器时直接报错（exec format error 等）
# 两种情况都不直观，故提前显式检测并给出清晰提示
IMAGE_ARCH="$(docker image inspect "${FULL_IMAGE}" --format '{{.Architecture}}')"
HOST_ARCH_RAW="$(uname -m)"
case "${HOST_ARCH_RAW}" in
    x86_64)  HOST_ARCH="amd64" ;;
    aarch64) HOST_ARCH="arm64" ;;
    *)       HOST_ARCH="${HOST_ARCH_RAW}" ;;
esac

if [ "${IMAGE_ARCH}" != "${HOST_ARCH}" ] && [ "${ALLOW_ARCH_MISMATCH}" -eq 0 ]; then
    echo "==============================================" >&2
    echo "错误: 镜像架构与宿主机架构不一致，已阻止启动" >&2
    echo "  镜像架构:   ${IMAGE_ARCH}" >&2
    echo "  宿主机架构: ${HOST_ARCH}（uname -m: ${HOST_ARCH_RAW}）" >&2
    echo "" >&2
    echo "  该镜像目前只支持在 ${IMAGE_ARCH} 宿主机上原生运行。" >&2
    echo "  如果确认已启用 QEMU 跨架构模拟（Docker Desktop 默认启用，" >&2
    echo "  纯 Linux 需自行安装 qemu-user-static 并注册 binfmt handler），" >&2
    echo "  可加 --allow-arch-mismatch 参数跳过此检查强制运行（速度会明显变慢）。" >&2
    echo "==============================================" >&2
    exit 1
elif [ "${IMAGE_ARCH}" != "${HOST_ARCH}" ] && [ "${ALLOW_ARCH_MISMATCH}" -eq 1 ]; then
    echo "==> 警告: 镜像架构(${IMAGE_ARCH}) 与宿主机架构(${HOST_ARCH}) 不一致，" >&2
    echo "    已通过 --allow-arch-mismatch 跳过检查，将依赖 QEMU 模拟运行，性能会明显下降" >&2
fi

# 删除可能遗留的旧容器（确保干净）
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "==> 停止并删除旧容器: ${CONTAINER_NAME}"
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

# 提取挂载目录的最后一个文件夹名
MOUNT_BASENAME=$(basename "${MOUNT_DIR}")
CONTAINER_TARGET="/home/vscode/workspace/${MOUNT_BASENAME}"

# 启动新容器
DOCKER_RUN_ARGS=(
    -d
    --name "${CONTAINER_NAME}"
    --restart unless-stopped
    -v "${MOUNT_DIR}:${CONTAINER_TARGET}"
)

echo "==> 启动容器（挂载目录）: ${CONTAINER_NAME}"
echo "    挂载宿主机目录: ${MOUNT_DIR} -> ${CONTAINER_TARGET}"

docker run "${DOCKER_RUN_ARGS[@]}" "${FULL_IMAGE}"

echo "==> 容器已启动，名称: ${CONTAINER_NAME}"
echo "    进入容器: docker exec -it ${CONTAINER_NAME} bash"
echo "    容器内代码位于: ${CONTAINER_TARGET}"
echo "    使用 VSCode 附加: 打开命令面板 -> '开发容器: 附加到正在运行的容器'"
