#!/bin/bash

# 用法：./[this].sh <tar文件名> <镜像名> <宿主机存放代码的目录>

TAR_FILE="${1:-devenv.tar}"
IMAGE_NAME="${2:-devenv:latest}"
# 默认提取到当前目录下的 ./extracted_code
HOST_CODE_DIR="${3:-./extracted_code}"

# 1. 导入镜像
echo "==> 加载镜像..."
docker load -i "${TAR_FILE}"

# 2. 确定容器内的项目路径（镜像内部的 WORKDIR）
# 注意：freeze-export 打包时 WORKDIR 为 /workspaces/<项目名>
# 这里我们可以通过镜像的 WORKDIR 或直接硬编码，更稳健的方法是用 docker inspect
CONTAINER_WORKDIR=$(docker inspect "${IMAGE_NAME}" --format '{{.Config.WorkDir}}')
if [ -z "${CONTAINER_WORKDIR}" ] || [ "${CONTAINER_WORKDIR}" == "/" ]; then
    echo "警告：无法检测 WORKDIR，请手动指定或使用默认 /workspaces/project"
    CONTAINER_WORKDIR="/workspaces/project"
fi
PROJECT_NAME=$(basename "${CONTAINER_WORKDIR}")

echo "==> 容器内项目路径: ${CONTAINER_WORKDIR}"

# 3. 提取代码到宿主机（仅当宿主机目录不存在时）
if [ ! -d "${HOST_CODE_DIR}" ]; then
    echo "==> 从镜像中提取代码到宿主机: ${HOST_CODE_DIR}"
    
    # 创建临时容器（不启动）
    docker create --name temp-extract "${IMAGE_NAME}" > /dev/null 2>&1
    
    # 复制整个项目目录到宿主机
    docker cp "temp-extract:${CONTAINER_WORKDIR}/." "${HOST_CODE_DIR}/"
    
    # 修正权限（让当前宿主机用户拥有这些文件，避免 VSCode 保存时权限报错）
    if [ -d "${HOST_CODE_DIR}" ]; then
        sudo chown -R $(id -u):$(id -g) "${HOST_CODE_DIR}" 2>/dev/null || chown -R $(id -u):$(id -g) "${HOST_CODE_DIR}"
    fi
    
    # 删除临时容器
    docker rm temp-extract > /dev/null 2>&1
    echo "==> 代码已提取到: $(realpath ${HOST_CODE_DIR})"
else
    echo "==> 宿主机目录已存在，跳过提取（保留上次修改）: ${HOST_CODE_DIR}"
fi

# 4. 挂载宿主机目录启动开发容器（后台保活，供 VSCode 附加）
echo "==> 启动开发容器（挂载模式）..."
docker run -d \
  --name dev-container \
  -v "$(realpath ${HOST_CODE_DIR}):${CONTAINER_WORKDIR}" \
  "${IMAGE_NAME}" \
  tail -f /dev/null

echo "========================================"
echo " 容器已启动！"
echo " 宿主机代码目录: $(realpath ${HOST_CODE_DIR})"
echo " 容器内映射路径: ${CONTAINER_WORKDIR}"
echo ""
echo " 接下来请打开 VSCode，按 F1 选择："
echo "   '开发容器：附加到正在运行的容器... (Dev Containers: Attach to Running Container...)'"
echo "   选择容器: dev-container"
echo "========================================"
