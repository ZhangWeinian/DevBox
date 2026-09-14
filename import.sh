#!/bin/bash

# 导入镜像 tar 包（支持 .tar 或 .tar.gz）并启动开发容器
# 用法：
#   ./import.sh                              # 若本地镜像存在，启动容器并自动挂载 ~/workspace（目录不存在则创建）；否则报错
#   ./import.sh /path/to/code                # 若本地镜像存在，启动容器并挂载指定目录；否则报错
#   ./import.sh myimage.tar                  # 加载 tar（或 tar.gz），删除旧容器/镜像，启动新容器并自动挂载 ~/workspace
#   ./import.sh myimage.tar.gz /path/to/code # 加载压缩包，删除旧容器/镜像，启动新容器并挂载指定目录
#   ./import.sh --allow-arch-mismatch ...    # 跳过架构一致性检查（允许 QEMU 模拟运行，会明显变慢）
#   ./import.sh --reset-cache ...            # 清空所有持久化缓存卷后再启动（谨慎使用）
#   ./import.sh --restricted ...             # 退回保守权限模式
#   ./import.sh -h|--help                    # 显示帮助

set -euo pipefail

IMAGE_NAME="devenv"
TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"
CONTAINER_NAME="dev-container"

# 持久化缓存卷清单
# 格式："<卷名后缀>:<容器内绝对路径>"
CACHE_VOLUME_SPECS=(
    "vcpkg:/home/vscode/.cache/vcpkg"
    "uv:/home/vscode/.cache/uv"
    "pip:/home/vscode/.cache/pip"
    "ccache:/home/vscode/.cache/ccache"
    "npm:/home/vscode/.npm"
    "yarn:/home/vscode/.cache/yarn"
    "pnpm-store:/home/vscode/.local/share/pnpm/store"
    "pydeps:/home/vscode/.local/lib/python-global-packages"
    "m2:/home/vscode/.m2"
    "gradle:/home/vscode/.gradle"
    "vscode-server:/home/vscode/.vscode-server"
    "vcpkg-manifest:/home/vscode/.vcpkg-manifest"
)

show_help() {
    cat <<EOF
用法:
  $0                              # 若本地镜像存在，启动容器并自动挂载 ~/workspace（目录不存在则创建）；否则报错
  $0 /path/to/code                # 若本地镜像存在，启动容器并挂载指定目录；否则报错
  $0 myimage.tar                  # 加载 tar（或 tar.gz），删除旧容器/镜像，启动新容器并自动挂载 ~/workspace
  $0 myimage.tar /path/to/code    # 加载 tar（或 tar.gz），删除旧容器/镜像，启动新容器并挂载指定目录
  $0 --allow-arch-mismatch [...]  # 跳过镜像架构与宿主机架构的一致性检查
  $0 --reset-cache [...]          # 启动前清空所有持久化缓存卷（vcpkg/uv/npm/.vscode-server 等）
  $0 --restricted [...]           # 退回保守权限模式（关闭 privileged / host 命名空间共享）
  $0 -h|--help                    # 显示帮助

说明:
  镜像名称固定为 ${FULL_IMAGE}
  容器名称固定为 ${CONTAINER_NAME}
  如果指定了 tar 包（支持 .tar 或 .tar.gz），则强制从 tar 加载，覆盖本地同名镜像
  如果未指定 tar，则使用本地镜像，若不存在则报错
  默认挂载目录为 ~/workspace（不存在则自动创建）
  此时直接对应容器内 ~/workspace（不嵌套子目录）
  若指定自定义目录，则以子目录形式挂载到容器内 ~/workspace/<目录名> 下

  权限模式（默认：最大权限模式，仅原生 Linux 宿主机生效；macOS/Windows 上的
  Docker Desktop 因运行在虚拟机内，部分能力会自动降级并打印原因）：
    --privileged            打开全部内核 capability，供 gdb/rr/valgrind/strace/
                             ltrace/heaptrack/bpftrace/linux-perf 等调试与性能
                             分析工具正常 attach、ptrace、加载 eBPF 探针
    --network host           与宿主机共享网络栈，供 tcpdump/iftop/mtr/iperf3
                             抓取/测试真实网卡流量（而非仅容器内 veth）
    --pid=host                与宿主机共享 PID 命名空间，供 perf/bpftrace/htop
                             等系统级性能工具观测宿主机全局进程
    --ipc=host                与宿主机共享 IPC 命名空间，便于 MPI/共享内存调试
    --cgroupns=host           与宿主机共享 cgroup 命名空间，供 iotop/sysstat 等
                             资源监控工具看到真实的系统级资源数据
    --ulimit core/nofile/     核心转储不限制、fd 上限拉高、内存锁定不限制
      memlock 拉满                （bpftrace/eBPF 加载探针、iperf3 高并发连接需要）
    --shm-size=2g              放大 /dev/shm（openmpi 共享内存传输、部分构建工具需要）
    条件挂载（宿主机存在才挂载，不存在则自动跳过并打印原因）：
      /tmp/.X11-unix、DISPLAY   供 X11 GUI 程序测试
      /dev/dri                   供 OpenGL/EGL 硬件加速渲染
      /dev/kvm                   供 QEMU 加速（若可用）
      /sys/kernel/debug          供 bpftrace/ftrace 挂载探针
      /lib/modules、/usr/src     供 bpftrace 解析内核符号

  --restricted 会关闭以上全部内容，回退为：仅 seccomp=unconfined（供 lldb/TSan
  关闭 ASLR 用）+ 精简 capability 列表（SYS_PTRACE/NET_ADMIN/NET_RAW/SYS_NICE/
  IPC_LOCK）+ 默认 bridge 网络，适合对宿主机权限比较谨慎的场合

  持久化缓存卷（跨镜像重建保留，不受 docker build / docker rmi 影响）:
EOF
    for spec in "${CACHE_VOLUME_SPECS[@]}"; do
        suffix="${spec%%:*}"
        path="${spec#*:}"
        printf "    %-20s -> %s\n" "${IMAGE_NAME}-cache-${suffix}" "${path}"
    done
    cat <<EOF

  如需彻底清空某个缓存（例如怀疑缓存损坏或工具版本发生不兼容的重大变更）
  可手动执行: docker volume rm ${IMAGE_NAME}-cache-<后缀>
  或使用 --reset-cache 一次性清空全部
EOF
}

ALLOW_ARCH_MISMATCH=0
RESET_CACHE=0
RESTRICTED_MODE=0
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
        --restricted)
            RESTRICTED_MODE=1
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

TAR_FILE=""
MOUNT_DIR=""

# 解析剩余的位置参数（支持 .tar 或 .tar.gz）
if [ $# -eq 0 ]; then
    :
elif [ $# -eq 1 ]; then
    if [[ "$1" == *.tar ]] || [[ "$1" == *.tar.gz ]]; then
        TAR_FILE="$1"
    else
        MOUNT_DIR="$1"
    fi
elif [ $# -eq 2 ]; then
    if [[ "$1" == *.tar ]] || [[ "$1" == *.tar.gz ]]; then
        TAR_FILE="$1"
        MOUNT_DIR="$2"
    else
        echo "错误: 第一个参数必须是 .tar 或 .tar.gz 文件"
        show_help
        exit 1
    fi
else
    echo "错误: 参数数量不正确"
    show_help
    exit 1
fi

# 处理挂载目录
USED_DEFAULT_MOUNT_DIR=0
if [ -z "${MOUNT_DIR}" ]; then
    MOUNT_DIR="${HOME}/workspace"
    mkdir -p "${MOUNT_DIR}"
    echo "==> 未指定挂载目录，使用默认目录: ${MOUNT_DIR}"
    USED_DEFAULT_MOUNT_DIR=1
fi

# 将挂载目录转为绝对路径（如果失败则退出）
if ! MOUNT_DIR="$(cd "${MOUNT_DIR}" 2>/dev/null && pwd)"; then
    echo "错误: 无法解析目录 '${MOUNT_DIR}'"
    exit 1
fi

# 计算容器内挂载目标
if [ "${USED_DEFAULT_MOUNT_DIR}" -eq 1 ]; then
    CONTAINER_TARGET="/home/vscode/workspace"
else
    MOUNT_BASENAME=$(basename "${MOUNT_DIR}")
    CONTAINER_TARGET="/home/vscode/workspace/${MOUNT_BASENAME}"
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
    if [[ "${TAR_FILE}" == *.tar.gz ]]; then
        gunzip -c "${TAR_FILE}" | docker load
    else
        docker load -i "${TAR_FILE}"
    fi
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
    echo "" >&2
    echo "  该镜像目前只支持在 ${IMAGE_ARCH} 宿主机上原生运行" >&2
    echo "  如果确认已启用 QEMU 跨架构模拟（Docker Desktop 默认启用" >&2
    echo "  纯 Linux 需自行安装 qemu-user-static 并注册 binfmt handler）" >&2
    echo "  可加 --allow-arch-mismatch 参数跳过此检查强制运行（速度会明显变慢）" >&2
    echo "==============================================" >&2
    exit 1
elif [ "${IMAGE_ARCH}" != "${HOST_ARCH}" ] && [ "${ALLOW_ARCH_MISMATCH}" -eq 1 ]; then
    echo "==> 警告: 镜像架构(${IMAGE_ARCH}) 与宿主机架构(${HOST_ARCH}) 不一致" >&2
    echo "    已通过 --allow-arch-mismatch 跳过检查，将依赖 QEMU 模拟运行，性能会明显下降" >&2
fi

# 删除可能遗留的旧容器
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "==> 停止并删除旧容器: ${CONTAINER_NAME}"
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

# --reset-cache：显式清空所有持久化缓存卷
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

# ------------------------------------------------------------------------
# 权限模式判定
#
# --privileged / --network host / --pid=host 等仅在"原生 Linux 宿主机 + 原生
# Linux dockerd"下语义完整；Docker Desktop（macOS / Windows）实际把容器跑在一层
# 隐藏的 Linux 虚拟机里，这些参数要么无效要么行为异常（例如 --network host 在
# 部分 Docker Desktop 版本上完全不生效），因此这里显式探测宿主机操作系统
# 非原生 Linux 时自动降级为保守模式并打印原因，避免出现难以诊断的“看起来加了
# 参数但工具依然不工作”的情况
# ------------------------------------------------------------------------
HOST_OS="$(uname -s)"
NATIVE_LINUX_HOST=0
if [ "${HOST_OS}" = "Linux" ]; then
    NATIVE_LINUX_HOST=1
fi

MAX_PRIVILEGE=1
if [ "${RESTRICTED_MODE}" -eq 1 ]; then
    MAX_PRIVILEGE=0
    echo "==> 已指定 --restricted，使用保守权限模式"
elif [ "${NATIVE_LINUX_HOST}" -eq 0 ]; then
    MAX_PRIVILEGE=0
    echo "==> 检测到宿主机操作系统为 ${HOST_OS}（非原生 Linux），" >&2
    echo "    --privileged / --network host / --pid=host 等在 Docker Desktop 下" >&2
    echo "    语义不完整，已自动降级为保守权限模式" >&2
fi

# 组装 docker run 参数：工作区 bind mount + 全部持久化缓存卷 + --init
DOCKER_RUN_ARGS=(
    -d
    --name "${CONTAINER_NAME}"
    --restart unless-stopped
    --init
    -v "${MOUNT_DIR}:${CONTAINER_TARGET}"
)

if [ "${MAX_PRIVILEGE}" -eq 1 ]; then
    echo "==> 权限模式: 最大权限（--privileged + host 命名空间共享）"
    DOCKER_RUN_ARGS+=(
        --privileged
        --network host
        --pid=host
        --ipc=host
        --cgroupns=host
        --ulimit core=-1
        --ulimit nofile=1048576:1048576
        --ulimit memlock=-1:-1
        --shm-size=2g
    )

    # 条件挂载：宿主机存在对应路径才挂载，避免误创建空目录 / 报错
    if [ -n "${DISPLAY:-}" ] && [ -d /tmp/.X11-unix ]; then
        DOCKER_RUN_ARGS+=(-v /tmp/.X11-unix:/tmp/.X11-unix:rw -e "DISPLAY=${DISPLAY}")
        echo "    已挂载 X11 socket，DISPLAY=${DISPLAY}"
    else
        echo "    未检测到 DISPLAY / X11 socket，跳过 GUI 透传（如需请在宿主机 X 会话内运行本脚本）"
    fi

    if [ -e /dev/dri ]; then
        DOCKER_RUN_ARGS+=(--device=/dev/dri)
        echo "    已挂载 /dev/dri"
    fi

    if [ -e /dev/kvm ]; then
        DOCKER_RUN_ARGS+=(--device=/dev/kvm)
        echo "    已挂载 /dev/kvm"
    fi

    if [ -d /sys/kernel/debug ]; then
        DOCKER_RUN_ARGS+=(-v /sys/kernel/debug:/sys/kernel/debug:rw)
        echo "    已挂载 /sys/kernel/debug"
    fi

    if [ -d /lib/modules ]; then
        DOCKER_RUN_ARGS+=(-v /lib/modules:/lib/modules:ro)
    fi

    if [ -d /usr/src ]; then
        DOCKER_RUN_ARGS+=(-v /usr/src:/usr/src:ro)
    fi
else
    echo "==> 权限模式: 保守（seccomp=unconfined + 精简 capability 列表 + bridge 网络）"
    # seccomp: 放行 personality(ADDR_NO_RANDOMIZE) —— lldb 调试启动 / TSan 关闭 ASLR 依赖它;
    # Docker 默认 profile 会以 EPERM 拒绝该参数 (表现为 "personality set failed" /
    # "unable to disable ASLR")。如需最小权限, 可改为自定义 profile:
    #   --security-opt seccomp=<custom.json>  (默认 profile + 放行 personality 的 0x40000)
    DOCKER_RUN_ARGS+=(
        --security-opt seccomp=unconfined
        --cap-add=SYS_PTRACE
        --cap-add=NET_ADMIN
        --cap-add=NET_RAW
        --cap-add=SYS_NICE
        --cap-add=IPC_LOCK
        --ulimit core=-1
        --ulimit nofile=65536:65536
    )
fi

echo "==> 挂载持久化缓存卷："
for spec in "${CACHE_VOLUME_SPECS[@]}"; do
    suffix="${spec%%:*}"
    path="${spec#*:}"
    vol_name="${IMAGE_NAME}-cache-${suffix}"
    DOCKER_RUN_ARGS+=(-v "${vol_name}:${path}")
    printf "    %-20s -> %s\n" "${vol_name}" "${path}"
done

echo "==> 同步镜像内置的 vcpkg 二进制缓存到持久化卷"
docker run --rm --user root \
    -v "${IMAGE_NAME}-cache-vcpkg:/mnt/vcpkg-cache-volume" \
    "${FULL_IMAGE}" \
    bash -c '
        set -eux
        mkdir -p /mnt/vcpkg-cache-volume/archives /mnt/vcpkg-cache-volume/downloads
        if [ -d /home/vscode/.cache/vcpkg/archives ]; then
            cp -an /home/vscode/.cache/vcpkg/archives/. /mnt/vcpkg-cache-volume/archives/ 2>/dev/null || true
        fi
        chown -R 1000:1000 /mnt/vcpkg-cache-volume
    '

echo "==> 同步镜像内置的 vcpkg manifest（baseline 信息）"
docker run --rm --user root \
    -v "${IMAGE_NAME}-cache-vcpkg-manifest:/mnt/vcpkg-manifest-volume" \
    "${FULL_IMAGE}" \
    bash -c '
        set -eux
        mkdir -p /mnt/vcpkg-manifest-volume
        if [ -f /home/vscode/.vcpkg-manifest/vcpkg.json ]; then
            rm -rf /mnt/vcpkg-manifest-volume/*
            cp -a /home/vscode/.vcpkg-manifest/. /mnt/vcpkg-manifest-volume/
            chown -R 1000:1000 /mnt/vcpkg-manifest-volume
        fi
    '
echo "==> vcpkg manifest 同步完成"

echo "==> 同步镜像内置的 Python 全局依赖包到持久化卷"
docker run --rm --user root \
    -v "${IMAGE_NAME}-cache-pydeps:/mnt/pydeps-volume" \
    "${FULL_IMAGE}" \
    bash -c '
        set -eux
        mkdir -p /mnt/pydeps-volume
        if [ -d /home/vscode/.local/lib/python-global-packages ]; then
            cp -an /home/vscode/.local/lib/python-global-packages/. /mnt/pydeps-volume/ 2>/dev/null || true
        fi
        if [ -f /home/vscode/.pydeps-manifest/requirements.txt ]; then
            cp -a /home/vscode/.pydeps-manifest/requirements.txt /mnt/pydeps-volume/.manifest-requirements.txt
        fi
        chown -R 1000:1000 /mnt/pydeps-volume
    '
echo "==> Python 全局依赖包同步完成"

echo "==> 启动容器: ${CONTAINER_NAME}"
echo "    挂载宿主机目录: ${MOUNT_DIR} -> ${CONTAINER_TARGET}"
docker run "${DOCKER_RUN_ARGS[@]}" "${FULL_IMAGE}"

# 等待容器就绪（避免 exec 失败）
echo "==> 等待容器启动..."
until docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q true; do
    sleep 1
done

# 修复权限
echo "==> 校正缓存目录权限"
CACHE_PATHS=()
for spec in "${CACHE_VOLUME_SPECS[@]}"; do
    CACHE_PATHS+=("${spec#*:}")
done
docker exec --user root "${CONTAINER_NAME}" bash -c \
    "chown -R vscode:vscode ${CACHE_PATHS[*]}"

# 最大权限模式下，尝试放开 perf_event_paranoid（供 rr / linux-perf 使用）
# 该 sysctl 不受 Linux namespace 隔离，写入会影响宿主机全局设置，仅在原生 Linux
# 宿主机的最大权限模式下尝试；失败（例如只读文件系统、内核不支持）不影响容器启动
if [ "${MAX_PRIVILEGE}" -eq 1 ]; then
    echo "==> 尝试放开 perf_event_paranoid（供 rr / linux-perf 使用，失败不影响启动）"
    docker exec --user root "${CONTAINER_NAME}" bash -c \
        'echo -1 > /proc/sys/kernel/perf_event_paranoid 2>/dev/null || true'
    docker exec --user root "${CONTAINER_NAME}" bash -c \
        'echo 0 > /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || true'
fi

echo "==> 容器已启动，名称: ${CONTAINER_NAME}"
if [ "${MAX_PRIVILEGE}" -eq 1 ]; then
    echo "    权限模式: 最大权限（--privileged，与宿主机共享 network/pid/ipc/cgroup 命名空间）"
    echo "    如需收紧权限，重新执行本脚本并加上 --restricted"
else
    echo "    权限模式: 保守（如需完整调试/抓包能力，在原生 Linux 宿主机上去掉 --restricted 重新执行）"
fi
echo "    进入容器: docker exec -it ${CONTAINER_NAME} bash"
echo "    容器内代码位于: ${CONTAINER_TARGET}"
echo "    使用 VSCode 附加: 打开命令面板 -> '开发容器: 附加到正在运行的容器'"
