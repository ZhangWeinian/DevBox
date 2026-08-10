#!/bin/bash

# 导入镜像 tar 包并启动开发容器
# 用法：
#   ./import.sh                           # 若本地镜像存在，启动容器并自动挂载 ~/workspace（目录不存在则创建）；否则报错
#   ./import.sh /path/to/code             # 若本地镜像存在，启动容器并挂载指定目录；否则报错
#   ./import.sh myimage.tar               # 加载 tar，删除旧容器/镜像，启动新容器并自动挂载 ~/workspace（目录不存在则创建）
#   ./import.sh myimage.tar /path/to/code # 加载 tar，删除旧容器/镜像，启动新容器并挂载指定目录
#   ./import.sh --allow-arch-mismatch ... # 跳过架构一致性检查（允许 QEMU 模拟运行，会明显变慢）
#   ./import.sh --reset-cache ...         # 清空所有持久化缓存卷后再启动（谨慎使用，见下方说明）
#   ./import.sh -h|--help                 # 显示帮助

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"
CONTAINER_NAME="dev-container"

# 持久化缓存卷清单
# 这里列出的每一项，都会被挂载为一个"具名卷"（named volume），=。具名卷独立于
# image tag 存在，重新 build/import 新镜像时会自动复用旧卷内容，实现
# "镜像随便重建，缓存持续累积"的效果
#
# 原理：具名卷第一次挂载到某路径时，若镜像该路径已有内容，Docker 会自动把镜像
# 内容复制进卷（首次自动预热）；若卷已有内容（不是第一次），则直接使用卷内容，
# 不会被镜像覆盖（持续累积，新旧共存）
#
# 格式："<卷名后缀>:<容器内绝对路径>"，卷的实际名称为 "${IMAGE_NAME}-cache-<后缀>"
CACHE_VOLUME_SPECS=(
    "vcpkg:/home/vscode/.cache/vcpkg"
    "uv:/home/vscode/.cache/uv"
    "pip:/home/vscode/.cache/pip"
    "ccache:/home/vscode/.cache/ccache"
    "npm:/home/vscode/.npm"
    "yarn:/home/vscode/.cache/yarn"
    "pnpm-store:/home/vscode/.local/share/pnpm/store"
    "m2:/home/vscode/.m2"
    "gradle:/home/vscode/.gradle"
    "vscode-server:/home/vscode/.vscode-server"
)

show_help() {
    cat <<EOF
用法:
  $0                              # 若本地镜像存在，启动容器并自动挂载 ~/workspace（目录不存在则创建）；否则报错
  $0 /path/to/code                # 若本地镜像存在，启动容器并挂载指定目录；否则报错
  $0 myimage.tar                  # 加载 tar，删除旧容器/镜像，启动新容器并自动挂载 ~/workspace（目录不存在则创建）
  $0 myimage.tar /path/to/code    # 加载 tar，删除旧容器/镜像，启动新容器并挂载指定目录
  $0 --allow-arch-mismatch [...]  # 跳过镜像架构与宿主机架构的一致性检查
  $0 --reset-cache [...]          # 启动前清空所有持久化缓存卷（vcpkg/uv/npm/.vscode-server 等）
  $0 -h|--help                    # 显示帮助

说明:
  镜像名称固定为 ${FULL_IMAGE}
  容器名称固定为 ${CONTAINER_NAME}
  如果指定了 tar 包，则强制从 tar 加载，覆盖本地同名镜像。
  如果未指定 tar，则使用本地镜像，若不存在则报错。
  默认挂载目录为 ~/workspace（不存在则自动创建）。

  持久化缓存卷（跨镜像重建保留，不受 docker build / docker rmi 影响）:
EOF
    for spec in "${CACHE_VOLUME_SPECS[@]}"; do
        suffix="${spec%%:*}"
        path="${spec#*:}"
        printf "    %-20s -> %s\n" "${IMAGE_NAME}-cache-${suffix}" "${path}"
    done
    cat <<EOF

  如需彻底清空某个缓存（例如怀疑缓存损坏或工具版本发生不兼容的重大变更），
  可手动执行: docker volume rm ${IMAGE_NAME}-cache-<后缀>
  或使用 --reset-cache 一次性清空全部。
EOF
}

ALLOW_ARCH_MISMATCH=0
RESET_CACHE=0
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
        --reset-cache)
            RESET_CACHE=1
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
if [ -z "${MOUNT_DIR}" ]; then
    MOUNT_DIR="${HOME}/workspace"
    mkdir -p "${MOUNT_DIR}"
    echo "==> 未指定挂载目录，使用默认目录: ${MOUNT_DIR}"
fi

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

    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "==> 停止并删除容器 ${CONTAINER_NAME}"
        docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
        docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi

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
    echo "  如需强制运行（依赖 QEMU 模拟），请加 --allow-arch-mismatch" >&2
    echo "==============================================" >&2
    exit 1
elif [ "${IMAGE_ARCH}" != "${HOST_ARCH}" ]; then
    echo "==> 警告: 镜像架构(${IMAGE_ARCH}) 与宿主机架构(${HOST_ARCH}) 不一致，已跳过检查，将依赖 QEMU 模拟运行" >&2
fi

# 删除可能遗留的旧容器
# 注意：这里只删容器和上面的镜像，不涉及缓存卷
# 缓存卷是独立的持久化资源，不会因为容器/镜像的增删而丢失
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "==> 停止并删除旧容器: ${CONTAINER_NAME}"
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

# --reset-cache：显式清空所有持久化缓存卷
# 这是一个破坏性操作，仅在怀疑缓存损坏、或某个工具版本发生不兼容的重大变更
# （例如 uv 缓存格式变化）需要彻底重来时手动使用，默认不会触发
if [ "${RESET_CACHE}" -eq 1 ]; then
    echo "==> --reset-cache 已指定，清空所有持久化缓存卷"
    for spec in "${CACHE_VOLUME_SPECS[@]}"; do
        suffix="${spec%%:*}"
        vol_name="${IMAGE_NAME}-cache-${suffix}"
        if docker volume inspect "${vol_name}" >/dev/null 2>&1; then
            echo "    删除卷: ${vol_name}"
            docker volume rm -f "${vol_name}" >/dev/null 2>&1 || true
        fi
    done
fi

# 提取挂载目录的最后一个文件夹名
MOUNT_BASENAME=$(basename "${MOUNT_DIR}")
CONTAINER_TARGET="/home/vscode/workspace/${MOUNT_BASENAME}"

# 组装 docker run 参数：工作区 bind mount + 全部持久化缓存卷
DOCKER_RUN_ARGS=(
    -d
    --name "${CONTAINER_NAME}"
    --restart unless-stopped
    -v "${MOUNT_DIR}:${CONTAINER_TARGET}"
)

echo "==> 挂载持久化缓存卷："
for spec in "${CACHE_VOLUME_SPECS[@]}"; do
    suffix="${spec%%:*}"
    path="${spec#*:}"
    vol_name="${IMAGE_NAME}-cache-${suffix}"
    DOCKER_RUN_ARGS+=(-v "${vol_name}:${path}")
    printf "    %-20s -> %s\n" "${vol_name}" "${path}"
done

echo "==> 启动容器: ${CONTAINER_NAME}"
echo "    挂载宿主机目录: ${MOUNT_DIR} -> ${CONTAINER_TARGET}"

docker run "${DOCKER_RUN_ARGS[@]}" "${FULL_IMAGE}"

# 修复权限：部分缓存目录（尤其 vcpkg，其内容原本产生于构建期的
# BuildKit cache mount，并未真正提交进镜像文件系统层）在具名卷首次
# 挂载时可能被 Docker 以 root 身份自动创建挂载点，导致以 vscode 身份
# 运行的进程无法写入。这里统一补一次 chown，幂等、开销极小，
# 无论首次挂载具体行为如何都能保证权限正确。
echo "==> 校正缓存目录权限"
CACHE_PATHS=()
for spec in "${CACHE_VOLUME_SPECS[@]}"; do
    CACHE_PATHS+=("${spec#*:}")
done
docker exec --user root "${CONTAINER_NAME}" bash -c \
    "chown -R vscode:vscode ${CACHE_PATHS[*]}"

echo "==> 容器已启动，名称: ${CONTAINER_NAME}"
echo "    进入容器: docker exec -it ${CONTAINER_NAME} bash"
echo "    容器内代码位于: ${CONTAINER_TARGET}"
echo "    使用 VSCode 附加: 打开命令面板 -> '开发容器: 附加到正在运行的容器'"
