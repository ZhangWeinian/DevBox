#!/usr/bin/env bash

# 用途：把基础开发镜像 + 工具链缓存 + 项目代码打包成可离线传输的静态镜像 tar 包。
# 用法：bash .devcontainer/scripts/freeze-export.sh <项目源码目录> [输出文件名（不含 .tar）]
# 示例：bash .devcontainer/scripts/freeze-export.sh ~/projects/my-demo my-demo-snapshot

set -euo pipefail

PROJECT_SRC_DIR="${1:?错误：请传入项目源码目录，例如: bash .devcontainer/scripts/freeze-export.sh ~/projects/my-demo}"
PROJECT_NAME="$(basename "${PROJECT_SRC_DIR}")"
OUTPUT_NAME="${2:-${PROJECT_NAME}-$(dpkg --print-architecture)-$(date +%Y%m%d)}"

# scripts/ 与 Dockerfile 同处 .devcontainer/ 下，无需再拼接额外层级
DEVCONTAINER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_ROOT="${HOME}/.devcontainer-caches"
BASE_IMAGE="devenv:latest"
FREEZE_TAG="devenv:freeze-${OUTPUT_NAME}"

echo "========================================"
echo " 项目：${PROJECT_NAME}"
echo " 输出：${OUTPUT_NAME}.tar"
echo " 架构：$(dpkg --print-architecture)"
echo " 缓存：${CACHE_ROOT}"
echo "========================================"

echo ""
echo "==> [1/4] 检查基础镜像 ${BASE_IMAGE}"
if ! docker image inspect "${BASE_IMAGE}" >/dev/null 2>&1; then
    echo "    基础镜像不存在，开始构建..."
    DOCKER_BUILDKIT=1 docker build \
        -t "${BASE_IMAGE}" \
        -f "${DEVCONTAINER_DIR}/Dockerfile" \
        "${DEVCONTAINER_DIR}"
else
    echo "    已存在，跳过构建"
fi

echo ""
echo "==> [2/4] 准备临时构建上下文"
STAGE_DIR="$(mktemp -d -t freeze-XXXXXXXXXX)"
trap 'echo ""; echo "清理临时目录 ${STAGE_DIR}"; rm -rf "${STAGE_DIR}"' EXIT

mkdir -p \
    "${STAGE_DIR}/caches/vcpkg" \
    "${STAGE_DIR}/caches/ccache" \
    "${STAGE_DIR}/caches/uv" \
    "${STAGE_DIR}/caches/pip" \
    "${STAGE_DIR}/caches/npm" \
    "${STAGE_DIR}/caches/m2" \
    "${STAGE_DIR}/caches/gradle" \
    "${STAGE_DIR}/project"

_sync_cache() {
    local src="${CACHE_ROOT}/$1"
    local dst="${STAGE_DIR}/caches/$1"
    if [ -d "${src}" ] && [ -n "$(ls -A "${src}" 2>/dev/null)" ]; then
        echo "    同步缓存: $1 ($(du -sh "${src}" 2>/dev/null | cut -f1))"
        rsync -a --delete "${src}/" "${dst}/"
    else
        echo "    跳过空缓存: $1"
    fi
}

_sync_cache vcpkg
_sync_cache ccache
_sync_cache uv
_sync_cache pip
_sync_cache npm
_sync_cache m2
_sync_cache gradle

echo "    同步项目代码: ${PROJECT_SRC_DIR}"
rsync -a \
    --exclude='.git/' \
    --exclude='build/' \
    --exclude='out/' \
    --exclude='__pycache__/' \
    --exclude='*.pyc' \
    --exclude='.venv/' \
    --exclude='node_modules/' \
    "${PROJECT_SRC_DIR}/" "${STAGE_DIR}/project/"

cp "${DEVCONTAINER_DIR}/Dockerfile.freeze" "${STAGE_DIR}/Dockerfile"

echo "    构建上下文大小: $(du -sh "${STAGE_DIR}" | cut -f1)"

echo ""
echo "==> [3/4] 构建冻结镜像 ${FREEZE_TAG}"
DOCKER_BUILDKIT=1 docker build \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    --build-arg PROJECT_DIR_NAME="${PROJECT_NAME}" \
    -t "${FREEZE_TAG}" \
    "${STAGE_DIR}"

echo ""
echo "==> [4/4] 导出离线包: ${OUTPUT_NAME}.tar"
docker save "${FREEZE_TAG}" -o "${OUTPUT_NAME}.tar"
docker rmi "${FREEZE_TAG}" >/dev/null 2>&1 || true

TAR_SIZE=$(du -sh "${OUTPUT_NAME}.tar" | cut -f1)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_SCRIPT="${SCRIPT_DIR}/run_dev_with_code.sh"
if [ -f "${HELPER_SCRIPT}" ]; then
    TARGET_SCRIPT="${OUTPUT_NAME}.tar.sh"
    cp "${HELPER_SCRIPT}" "${TARGET_SCRIPT}"
    chmod +x "${TARGET_SCRIPT}" 2>/dev/null || true
    echo ""
    echo " 辅助脚本已生成：${TARGET_SCRIPT}"
else
    echo ""
    echo "警告：未找到辅助脚本 ${HELPER_SCRIPT}，跳过复制"
fi

echo ""
echo "========================================"
echo " 完成！"
echo " 文件：$(pwd)/${OUTPUT_NAME}.tar  (${TAR_SIZE})"
echo ""
echo " 传输到目标设备后："
echo "   docker load -i ${OUTPUT_NAME}.tar"
echo "   docker run -it --rm devenv:freeze-${OUTPUT_NAME} bash"
echo "========================================"
