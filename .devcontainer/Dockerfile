# syntax=docker/dockerfile:1.7

# 所有用于 FROM 行的 ARG 必须声明在第一个 FROM 之前
ARG JDK_MAJOR_VERSION=21
ARG NODE_VARIANT=lts
ARG VARIANT=debian13
ARG GCC_EXTRA_MAJOR_VERSION=16

# 辅助阶段：Microsoft OpenJDK（distroless，实际路径 /usr/jdk）
FROM mcr.microsoft.com/openjdk/jdk:${JDK_MAJOR_VERSION}-distroless AS jdk-src

# 辅助阶段：Node.js LTS
# 务必用 Debian 系变体（默认即是），不要用 -alpine：musl 与基础镜像 glibc 不兼容
FROM node:${NODE_VARIANT} AS node-src

# 辅助阶段：架构防御检测
# 此镜像的交叉编译工具链 / vcpkg triplet 均按 amd64 宿主机硬编码
# 若基础镜像被解析为非 amd64（例如在 arm64 宿主机上未加 --platform 直接构建），
# 立即报错终止检测通过后生成标记文件 /arch-ok，主阶段通过 COPY --from 强制依赖此阶段，
# 确保检测必然执行
FROM mcr.microsoft.com/devcontainers/base:${VARIANT} AS arch-check
RUN set -eux \
    && ARCH="$(dpkg --print-architecture)" \
    && if [ "${ARCH}" != "amd64" ]; then \
        echo "FATAL: 此 Dockerfile 仅支持 amd64 基础镜像构建，检测到当前架构为 ${ARCH}" >&2; \
        echo "请在 x86_64 宿主机上构建，或使用 --platform linux/amd64 强制模拟" >&2; \
        exit 1; \
    fi \
    && touch /arch-ok

# 主阶段
# 基于 devcontainers/base 而非 devcontainers/cpp
FROM mcr.microsoft.com/devcontainers/base:${VARIANT}

# 重新声明 ARG，使其在当前 stage 的 RUN 中可用
ARG GCC_EXTRA_MAJOR_VERSION

# 强制依赖 arch-check 阶段：只有该阶段构建成功（架构检测通过）才会执行到这里
COPY --from=arch-check /arch-ok /arch-ok

# 让 vscode 对 /usr/local/bin 有写权限（uv tool install 的 BIN_DIR 指向此处）
# 同时清理架构检测的临时标记文件
RUN set -eux \
    && rm -f /arch-ok \
    && chown vscode:vscode /usr/local/bin

# 基础系统包
# 编译工具链
#   build-essential/gdb/cppcheck/valgrind：base 镜像不含编译调试套件，
#   需显式补齐（cpp 变体隐式提供这些，改用 base 后必须自己声明）
#   注意：cmake 不在此处安装，由后续 uv tool install cmake 提供，
#   避免 apt 版（版本较旧）与 uv 版（构建时最新）重复安装造成歧义
ENV DEBIAN_FRONTEND=noninteractive
ENV CCACHE_DIR=/home/vscode/.cache/ccache
ENV USE_CCACHE=1
ENV CCACHE_SLOPPINESS=file_macro,include_file_mtime,time_macros
ENV CCACHE_UMASK=002
RUN set -eux \
    && dpkg --add-architecture arm64 \
    && apt-get update \
    && apt-get -yq upgrade \
    && apt-get -yq install --no-install-recommends \
        build-essential \
        cppcheck \
        valgrind \
        gdb \
        libboost-all-dev \
        libssl-dev \
        libgl-dev \
        sudo \
        curl \
        wget \
        zip \
        unzip \
        tar \
        net-tools \
        tcpdump \
        iperf3 \
        pkg-config \
        ccache \
        libudev-dev \
        libudev-dev:arm64 \
        libbz2-dev \
        libzstd-dev \
        zlib1g-dev \
        liblzma-dev \
        rsync \
        file \
        autoconf \
        automake \
        libtool \
        m4 \
        autoconf-archive \
        jq \
        tree \
        htop \
        tmux \
        vim \
        ripgrep \
        fd-find \
        openssh-client \
        iproute2 \
        dnsutils \
        iputils-ping \
        openssl \
        gcc-aarch64-linux-gnu \
        g++-aarch64-linux-gnu \
        binutils-aarch64-linux-gnu \
        libc6-dev-arm64-cross \
        libusb-1.0-0-dev \
        lsb-release \
        gnupg \
        strace \
        ltrace \
        sysstat \
        iotop \
        iftop \
        telnet \
        netcat-openbsd \
        mtr \
        sqlite3 \
        fzf \
        bat \
        eza \
        yq \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && ln -sf "$(command -v fdfind)" /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "${CCACHE_DIR}" \
    && chown -R vscode:vscode "${CCACHE_DIR}"

# GCC 16：手动新增第二套 GCC 工具链，注册为系统默认 c/c++ 编译器
#
# 设计要点：
#   - 保留 build-essential 附带的"系统默认 gcc/g++"（版本不固定，随基础镜像滚动），
#     动态探测其版本号与真实二进制路径，以较低优先级注册进 update-alternatives，
#     不卸载、不覆盖，任何时候都能用 `update-alternatives --config gcc` 手动切回去
#   - trixie 稳定源通常还没有 gcc-16，需从 Debian unstable 单独拉取：
#     新增 unstable 源并用 APT Pinning 钉在低优先级（100），只对本次
#     `-t unstable` 显式安装的包生效，不会污染系统其余软件包版本；
#     装完立即移除该源，避免后续任何 apt 操作误从 unstable 升级其它包
#   - 同时安装 libgcc-16-dev / libstdc++-16-dev，确保头文件和运行时库完整，
#     避免 vcpkg 交叉编译 arm64 triplet 时找不到对应版本的 libgcc/libstdc++
#   - 同时安装 GCC 16 的 ARM64 交叉编译工具链和新版 binutils-aarch64-linux-gnu，
#     与 x86_64 版本保持一致，避免"本机用 GCC 16 编译通过，交叉编译用 GCC 14 失败"
#     的版本不匹配问题；新版 binutils 解决 GCC 16 生成的新伪指令
#     （.aeabi_subsection / .aeabi_attribute）不被旧版汇编器识别的问题
#   - cpp 不使用 alternatives 管理（状态容易损坏），直接软链到 cpp-16
#   - cc/c++ 直接软链到 /usr/bin/gcc、/usr/bin/g++（alternatives 的总入口），
#     会自动跟随当前 gcc/g++ 的选择，无需单独维护一套 alternatives
#   - LLVM/Clang 全系列工具链完全不受影响，仍走 /usr/local/bin 的独立软链
RUN set -eux \
    && DEFAULT_GCC_VER="$(gcc -dumpversion | cut -d. -f1)" \
    && DEFAULT_GCC_BIN="$(readlink -f "$(command -v gcc)")" \
    && DEFAULT_GXX_BIN="$(readlink -f "$(command -v g++)")" \
    # 添加 unstable 源 + APT Pinning（低优先级，防止污染其他包）
    && echo "deb http://deb.debian.org/debian unstable main" > /etc/apt/sources.list.d/unstable.list \
    && printf 'Package: *\nPin: release a=unstable\nPin-Priority: 100\n' > /etc/apt/preferences.d/unstable-pin \
    && apt-get update \
    # 从 unstable 安装 GCC 16 及其开发库（x86_64 原生 + arm64 交叉编译 + 新版 binutils）
    && apt-get -yq install --no-install-recommends -t unstable \
        "gcc-${GCC_EXTRA_MAJOR_VERSION}" \
        "g++-${GCC_EXTRA_MAJOR_VERSION}" \
        "cpp-${GCC_EXTRA_MAJOR_VERSION}" \
        "libgcc-${GCC_EXTRA_MAJOR_VERSION}-dev" \
        "libstdc++-${GCC_EXTRA_MAJOR_VERSION}-dev" \
        "gcc-${GCC_EXTRA_MAJOR_VERSION}-aarch64-linux-gnu" \
        "g++-${GCC_EXTRA_MAJOR_VERSION}-aarch64-linux-gnu" \
        "cpp-${GCC_EXTRA_MAJOR_VERSION}-aarch64-linux-gnu" \
        "binutils-aarch64-linux-gnu" \
    # 立即移除 unstable 源和 pinning 配置，避免影响后续 apt 操作
    && rm -f /etc/apt/sources.list.d/unstable.list /etc/apt/preferences.d/unstable-pin \
    && apt-get update \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    # 检查所有 slave 二进制存在性（两个版本都检查），确保 alternatives 注册不会半途失败
    && for slave_bin in \
       "/usr/bin/gcc-ar-${DEFAULT_GCC_VER}" \
       "/usr/bin/gcc-nm-${DEFAULT_GCC_VER}" \
       "/usr/bin/gcc-ranlib-${DEFAULT_GCC_VER}" \
       "/usr/bin/gcov-${DEFAULT_GCC_VER}" \
       "/usr/bin/gcov-dump-${DEFAULT_GCC_VER}" \
       "/usr/bin/gcov-tool-${DEFAULT_GCC_VER}" \
       "/usr/bin/gcc-ar-${GCC_EXTRA_MAJOR_VERSION}" \
       "/usr/bin/gcc-nm-${GCC_EXTRA_MAJOR_VERSION}" \
       "/usr/bin/gcc-ranlib-${GCC_EXTRA_MAJOR_VERSION}" \
       "/usr/bin/gcov-${GCC_EXTRA_MAJOR_VERSION}" \
       "/usr/bin/gcov-dump-${GCC_EXTRA_MAJOR_VERSION}" \
       "/usr/bin/gcov-tool-${GCC_EXTRA_MAJOR_VERSION}" \
       "/usr/bin/cpp-${DEFAULT_GCC_VER}" \
       "/usr/bin/cpp-${GCC_EXTRA_MAJOR_VERSION}" \
       "/usr/bin/aarch64-linux-gnu-gcc-${DEFAULT_GCC_VER}" \
       "/usr/bin/aarch64-linux-gnu-g++-${DEFAULT_GCC_VER}" \
       "/usr/bin/aarch64-linux-gnu-gcc-${GCC_EXTRA_MAJOR_VERSION}" \
       "/usr/bin/aarch64-linux-gnu-g++-${GCC_EXTRA_MAJOR_VERSION}"; do \
       if [ ! -x "${slave_bin}" ]; then \
           echo "FATAL: 预期的二进制 ${slave_bin} 不存在" >&2; \
           exit 1; \
       fi; \
       echo "    OK: ${slave_bin}"; \
    done \
    # 注册系统默认 GCC（较低优先级，如 gcc-14 → 140）
    && update-alternatives --install /usr/bin/gcc gcc "${DEFAULT_GCC_BIN}" "$((DEFAULT_GCC_VER * 10))" \
        --slave /usr/bin/g++        g++         "${DEFAULT_GXX_BIN}" \
        --slave /usr/bin/gcc-ar     gcc-ar      "/usr/bin/gcc-ar-${DEFAULT_GCC_VER}" \
        --slave /usr/bin/gcc-nm     gcc-nm      "/usr/bin/gcc-nm-${DEFAULT_GCC_VER}" \
        --slave /usr/bin/gcc-ranlib gcc-ranlib  "/usr/bin/gcc-ranlib-${DEFAULT_GCC_VER}" \
        --slave /usr/bin/gcov       gcov        "/usr/bin/gcov-${DEFAULT_GCC_VER}" \
        --slave /usr/bin/gcov-dump  gcov-dump   "/usr/bin/gcov-dump-${DEFAULT_GCC_VER}" \
        --slave /usr/bin/gcov-tool  gcov-tool   "/usr/bin/gcov-tool-${DEFAULT_GCC_VER}" \
    # 注册 GCC 16（较高优先级，160 > 140，自动成为 auto 模式下的默认）
    && update-alternatives --install /usr/bin/gcc gcc "/usr/bin/gcc-${GCC_EXTRA_MAJOR_VERSION}" "$((GCC_EXTRA_MAJOR_VERSION * 10))" \
        --slave /usr/bin/g++        g++         "/usr/bin/g++-${GCC_EXTRA_MAJOR_VERSION}" \
        --slave /usr/bin/gcc-ar     gcc-ar      "/usr/bin/gcc-ar-${GCC_EXTRA_MAJOR_VERSION}" \
        --slave /usr/bin/gcc-nm     gcc-nm      "/usr/bin/gcc-nm-${GCC_EXTRA_MAJOR_VERSION}" \
        --slave /usr/bin/gcc-ranlib gcc-ranlib  "/usr/bin/gcc-ranlib-${GCC_EXTRA_MAJOR_VERSION}" \
        --slave /usr/bin/gcov       gcov        "/usr/bin/gcov-${GCC_EXTRA_MAJOR_VERSION}" \
        --slave /usr/bin/gcov-dump  gcov-dump   "/usr/bin/gcov-dump-${GCC_EXTRA_MAJOR_VERSION}" \
        --slave /usr/bin/gcov-tool  gcov-tool   "/usr/bin/gcov-tool-${GCC_EXTRA_MAJOR_VERSION}" \
    # 显式 --set 确保非交互式构建结果确定
    && update-alternatives --set gcc "/usr/bin/gcc-${GCC_EXTRA_MAJOR_VERSION}" \
    # cpp：不使用 alternatives（状态容易损坏），直接软链到 cpp-16
    && ln -sf "/usr/bin/cpp-${GCC_EXTRA_MAJOR_VERSION}" /usr/bin/cpp \
    # cc/c++ 软链到 alternatives 总入口，自动跟随 gcc/g++ 切换
    && ln -sf /usr/bin/gcc /usr/bin/cc \
    && ln -sf /usr/bin/g++ /usr/bin/c++ \
    # ARM64 交叉编译器：更新软链指向 GCC 16 版本
    && ln -sf "/usr/bin/aarch64-linux-gnu-gcc-${GCC_EXTRA_MAJOR_VERSION}" "/usr/bin/aarch64-linux-gnu-gcc" \
    && ln -sf "/usr/bin/aarch64-linux-gnu-g++-${GCC_EXTRA_MAJOR_VERSION}" "/usr/bin/aarch64-linux-gnu-g++" \
    # 最终验证
    && update-alternatives --display gcc \
    && gcc --version \
    && g++ --version \
    && cc  --version \
    && c++ --version \
    && cpp --version \
    && aarch64-linux-gnu-gcc --version \
    && aarch64-linux-gnu-g++ --version \
    && aarch64-linux-gnu-as --version \
    && "gcc-${DEFAULT_GCC_VER}" --version \
    && "g++-${DEFAULT_GCC_VER}" --version \
    && "aarch64-linux-gnu-gcc-${DEFAULT_GCC_VER}" --version \
    && "aarch64-linux-gnu-g++-${DEFAULT_GCC_VER}" --version \
    && "gcc-${GCC_EXTRA_MAJOR_VERSION}" --version \
    && "g++-${GCC_EXTRA_MAJOR_VERSION}" --version \
    && "aarch64-linux-gnu-gcc-${GCC_EXTRA_MAJOR_VERSION}" --version \
    && "aarch64-linux-gnu-g++-${GCC_EXTRA_MAJOR_VERSION}" --version \
    # 编译测试
    && echo 'int main() { return 0; }' > /tmp/test.c \
    && echo 'int main() { return 0; }' > /tmp/test.cpp \
    # x86_64 编译测试
    && gcc /tmp/test.c -o /tmp/test_gcc_default \
    && g++ /tmp/test.cpp -o /tmp/test_gpp_default \
    && "gcc-${DEFAULT_GCC_VER}" /tmp/test.c -o /tmp/test_gcc14 \
    && "g++-${DEFAULT_GCC_VER}" /tmp/test.cpp -o /tmp/test_gpp14 \
    && "gcc-${GCC_EXTRA_MAJOR_VERSION}" /tmp/test.c -o /tmp/test_gcc16 \
    && "g++-${GCC_EXTRA_MAJOR_VERSION}" /tmp/test.cpp -o /tmp/test_gpp16 \
    # ARM64 交叉编译测试
    && aarch64-linux-gnu-gcc /tmp/test.c -o /tmp/test_arm64_gcc_default \
    && aarch64-linux-gnu-g++ /tmp/test.cpp -o /tmp/test_arm64_gpp_default \
    && "aarch64-linux-gnu-gcc-${DEFAULT_GCC_VER}" /tmp/test.c -o /tmp/test_arm64_gcc14 \
    && "aarch64-linux-gnu-g++-${DEFAULT_GCC_VER}" /tmp/test.cpp -o /tmp/test_arm64_gpp14 \
    && "aarch64-linux-gnu-gcc-${GCC_EXTRA_MAJOR_VERSION}" /tmp/test.c -o /tmp/test_arm64_gcc16 \
    && "aarch64-linux-gnu-g++-${GCC_EXTRA_MAJOR_VERSION}" /tmp/test.cpp -o /tmp/test_arm64_gpp16 \
    # 验证编译产物架构
    && file /tmp/test_gcc_default | grep -q "x86-64" \
    && file /tmp/test_gpp_default | grep -q "x86-64" \
    && file /tmp/test_gcc14 | grep -q "x86-64" \
    && file /tmp/test_gpp14 | grep -q "x86-64" \
    && file /tmp/test_gcc16 | grep -q "x86-64" \
    && file /tmp/test_gpp16 | grep -q "x86-64" \
    && file /tmp/test_arm64_gcc_default | grep -q "ARM aarch64" \
    && file /tmp/test_arm64_gpp_default | grep -q "ARM aarch64" \
    && file /tmp/test_arm64_gcc14 | grep -q "ARM aarch64" \
    && file /tmp/test_arm64_gpp14 | grep -q "ARM aarch64" \
    && file /tmp/test_arm64_gcc16 | grep -q "ARM aarch64" \
    && file /tmp/test_arm64_gpp16 | grep -q "ARM aarch64" \
    && rm -f /tmp/test.c /tmp/test.cpp /tmp/test_gcc_* /tmp/test_gpp_* /tmp/test_arm64_*

# .NET 10 LTS
RUN set -eux \
    && wget https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb \
        -O packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -yq dotnet-sdk-10.0 \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && dotnet --version

# uv：官方多架构镜像，直接 COPY 二进制，无需 curl/sh 安装脚本
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python
ENV UV_TOOL_DIR=/opt/uv/tools
ENV UV_TOOL_BIN_DIR=/usr/local/bin
ENV UV_CACHE_DIR=/home/vscode/.cache/uv
ENV PIP_CACHE_DIR=/home/vscode/.cache/pip
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
RUN set -eux \
    && uv --version

RUN set -eux \
    && mkdir -p \
        "${UV_PYTHON_INSTALL_DIR}" \
        "${UV_TOOL_DIR}" \
        "${UV_CACHE_DIR}" \
        "${PIP_CACHE_DIR}" \
    && chown -R vscode:vscode \
        /opt/uv \
        "${UV_CACHE_DIR}" \
        "${PIP_CACHE_DIR}"

# Python：通过 uv 安装最新受管理版本，并建立全局软链，
# 全程只有一套 Python，工具链和临时脚本都能找到，不产生版本歧义
RUN set -eux \
    && su vscode -c "\
        set -eux \
        && uv python install --python-preference only-managed \
    "
RUN set -eux \
    && PYTHON_DIR=$(dirname "$(uv python find --python-preference only-managed)") \
    && echo "Resolved Python dir: ${PYTHON_DIR}" \
    && ln -sf "${PYTHON_DIR}/python"  /usr/local/bin/python  \
    && ln -sf "${PYTHON_DIR}/python3" /usr/local/bin/python3 \
    && ln -sf "${PYTHON_DIR}/pip"     /usr/local/bin/pip     \
    && ln -sf "${PYTHON_DIR}/pip3"    /usr/local/bin/pip3

# CMake / Ninja / cmake-format / ruff / autoenv
# 通过 uv tool install 安装到隔离虚拟环境，bin 软链到 /usr/local/bin
# cmake 在此处安装，不从 apt 装，保证始终是构建时最新版本
RUN set -eux \
    && su vscode -c "\
        set -eux \
        && uv tool install cmake \
        && uv tool install ninja \
        && uv tool install cmakelang \
        && uv tool install autoenv \
        && uv tool install ruff \
    "
RUN set -eux \
    && python        --version \
    && pip           --version \
    && cmake         --version \
    && ninja         --version \
    && cmake-format  --version \
    && ruff          --version \
    && su vscode -c "\
        set -eux \
        && cmake --version \
        && ruff  --version \
    " \
    && ln -sf /usr/local/bin/ninja /usr/bin/ninja

# LLVM/Clang 工具链：直接从 GitHub 下载最新预编译二进制包
#
# 设计要点：
#   - 完全绕过 apt 依赖管理，避免与 GCC 16 交叉编译工具链的 libc6 版本冲突
#   - LLVM 20+ 官方 Linux x86_64 包名固定为 LLVM-{VERSION}-Linux-X64.tar.xz
#   - 包含 SHA256 校验和验证，确保下载完整性
#   - 解压到 /usr/local，与系统 GCC 的 /usr/bin 完全隔离
#   - 交叉编译验证：不使用 --sysroot（Debian 多架构布局不兼容 clang 的 sysroot 约定），
#     让 clang 通过 --target 和 --gcc-toolchain 自动查找正确的头文件和库路径
RUN set -eux \
    && curl -fsSL https://api.github.com/repos/llvm/llvm-project/releases/latest \
        -o /tmp/llvm_release.json \
    && VERSION=$(jq -r '.tag_name' /tmp/llvm_release.json | sed 's/^llvmorg-//') \
    && if [ -z "${VERSION}" ]; then \
        echo "FATAL: 未能解析 LLVM 版本号" >&2; \
        echo "API 响应内容：" >&2; \
        head -20 /tmp/llvm_release.json >&2; \
        exit 1; \
    fi \
    && TARBALL_NAME="LLVM-${VERSION}-Linux-X64.tar.xz" \
    && TARBALL_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${VERSION}/${TARBALL_NAME}" \
    && EXPECTED_SHA256=$(jq -r \
        --arg name "${TARBALL_NAME}" \
        '.assets[] | select(.name == $name) | .digest // empty' /tmp/llvm_release.json \
        | sed 's/^sha256://') \
    && wget -q "${TARBALL_URL}" -O /tmp/llvm.tar.xz \
    && if [ -n "${EXPECTED_SHA256}" ]; then \
        ACTUAL_SHA256=$(sha256sum /tmp/llvm.tar.xz | awk '{print $1}'); \
        if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then \
            echo "FATAL: SHA256 校验失败" >&2; \
            echo "  期望: ${EXPECTED_SHA256}" >&2; \
            echo "  实际: ${ACTUAL_SHA256}" >&2; \
            exit 1; \
        fi; \
    fi \
    && FILE_SIZE=$(stat -c%s /tmp/llvm.tar.xz) \
    && echo "==> Downloaded: $(du -h /tmp/llvm.tar.xz | cut -f1)" \
    && if [ "${FILE_SIZE}" -lt 100000000 ]; then \
        echo "FATAL: 文件太小 (${FILE_SIZE} bytes)" >&2; \
        exit 1; \
    fi \
    && tar -xf /tmp/llvm.tar.xz -C /usr/local --strip-components=1 \
    && rm -f /tmp/llvm.tar.xz /tmp/llvm_release.json \
    && clang --version \
    && clang++ --version \
    && clang-format --version \
    && clang-tidy --version \
    && clangd --version \
    && lldb --version \
    && llvm-config --version \
    && command -v ld.lld \
    && command -v llvm-ar \
    && command -v llvm-nm \
    && echo 'int main() { return 0; }' > /tmp/test.c \
    && echo 'int main() { return 0; }' > /tmp/test.cpp \
    && clang /tmp/test.c -o /tmp/test_x86 \
    && clang++ /tmp/test.cpp -o /tmp/test_x86_cpp \
    && file /tmp/test_x86 | grep -q "x86-64" \
    && file /tmp/test_x86_cpp | grep -q "x86-64" \
    && /tmp/test_x86 \
    && /tmp/test_x86_cpp \
    && clang --target=aarch64-linux-gnu \
             --gcc-toolchain=/usr \
             /tmp/test.c -o /tmp/test_arm64 \
             -fuse-ld=lld \
    && file /tmp/test_arm64 | grep -q "ARM aarch64" \
    && clang++ --target=aarch64-linux-gnu \
               --gcc-toolchain=/usr \
               /tmp/test.cpp -o /tmp/test_arm64_cpp \
               -fuse-ld=lld \
    && file /tmp/test_arm64_cpp | grep -q "ARM aarch64" \
    && rm -f /tmp/test.c /tmp/test.cpp \
              /tmp/test_x86 /tmp/test_x86_cpp \
              /tmp/test_arm64 /tmp/test_arm64_cpp \
    && gcc --version \
    && g++ --version \
    && aarch64-linux-gnu-gcc --version \
    && aarch64-linux-gnu-g++ --version \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Microsoft OpenJDK 21：从 distroless 镜像拷贝，
# 保留 JDK 是为了运行第三方 Java 工具链，不是本环境的开发核心
ENV JAVA_HOME=/usr/lib/jvm/msopenjdk-21
ENV PATH="${JAVA_HOME}/bin:${PATH}"
COPY --from=jdk-src /usr/jdk /usr/lib/jvm/msopenjdk-21
RUN set -eux \
    && java --version

# Node.js：多阶段拷贝，含 node-gyp 编译原生插件所需的头文件，顺带全局安装 codegraph
COPY --from=node-src --chown=vscode:vscode /usr/local/include/node        /usr/local/include/node
COPY --from=node-src --chown=vscode:vscode /usr/local/lib/node_modules    /usr/local/lib/node_modules
COPY --from=node-src                       /usr/local/bin/node            /usr/local/bin/node
RUN set -eux \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && if [ -d /usr/local/lib/node_modules/corepack ]; then \
        ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack; \
    fi \
    && mkdir -p /home/vscode/.npm \
    && chown -R vscode:vscode /home/vscode/.npm
RUN set -eux \
    && su vscode -c "\
        set -eux \
        && corepack enable \
        && npm      --version \
        && node     --version \
        && npm i -g @colbymchenry/codegraph \
        && codegraph --version \
    "

# 个人配置文件
# 母版统一放在 ~/.format/，作为唯一数据源：
#   - .vimrc          → ~/.vimrc（vim 固定读取此路径，单独软链）
#   - .clang-format   → ~/.clang-format（供开发者复制到项目目录）
#   - 其余文件通过 devcontainer.json 中各扩展的绝对路径直接引用
COPY --chown=vscode:vscode .format/ /home/vscode/.format/
RUN set -eux \
    && ln -sf /home/vscode/.format/.vimrc        /home/vscode/.vimrc \
    && chown -h vscode:vscode                    /home/vscode/.vimrc \
    && ln -sf /home/vscode/.format/.clang-format /home/vscode/.clang-format \
    && chown -h vscode:vscode                    /home/vscode/.clang-format

# 预创建缓存目录并授权 vscode 用户，无论后续被具名卷覆盖还是 bind mount，权限保持一致
RUN set -eux \
    && mkdir -p \
        /home/vscode/.local/share/pnpm/store \
        /home/vscode/.cache/yarn \
        /home/vscode/.m2 \
        /home/vscode/.gradle \
        /home/vscode/.vscode-server \
    && chown -R vscode:vscode \
        /home/vscode/.local \
        /home/vscode/.cache/yarn \
        /home/vscode/.m2 \
        /home/vscode/.gradle \
        /home/vscode/.vscode-server

# vcpkg：manifest 模式，builtin-baseline 每次构建动态生成
#
# 设计要点：
#   VCPKG_DOWNLOADS 指向 /home/vscode/.cache/vcpkg/downloads，
#   与 --mount=type=cache 的挂载点及 import.sh 的具名卷路径保持一致，
#   是缓存持久化架构的组成部分，不可随意更改
#   VCPKG_BINARY_SOURCES 中 archives 路径故意不使用 cache mount，编译产物会提交进镜像层，
#   供 import.sh 同步至持久化具名卷（若也用 cache mount，archives 将只存在于 BuildKit 
#   构建缓存，最终镜像中该路径为空，持久化卷无法从镜像获得初始内容）
ENV VCPKG_ROOT=/usr/local/vcpkg
ENV VCPKG_DOWNLOADS=/home/vscode/.cache/vcpkg/downloads
ENV VCPKG_BINARY_SOURCES="clear;files,/home/vscode/.cache/vcpkg/archives,readwrite"
ENV VCPKG_FEATURE_FLAGS=manifests,versions,binarycaching
ENV VCPKG_FORCE_SYSTEM_BINARIES=1
ENV VCPKG_DEFAULT_TRIPLET=x64-linux
ENV PATH="${PATH}:${VCPKG_ROOT}"

# 显式 clone vcpkg（浅克隆即可，build-vcpkg-deps.sh 会自动 unshallow 补全历史）
RUN set -eux \
    && git clone --depth 1 https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}" \
    && chown -R vscode:vscode "${VCPKG_ROOT}"

COPY vcpkg.json.in /home/vscode/.vcpkg-manifest/vcpkg.json.in

COPY <<'EOF' /tmp/build-vcpkg-deps.sh
#!/usr/bin/env bash
set -eux

# 刷新 vcpkg 本体到当前默认分支最新 commit
#    基础镜像自带（或上面显式 clone）的 vcpkg 通常是浅克隆（--depth 1），
#    只有普通 fetch 不会补全历史；manifest 模式解析历史版本 port 时需要完整
#    git 历史（通过 git read-tree 访问历史 tree object），必须显式 unshallow
DEFAULT_BRANCH=$(git -C "${VCPKG_ROOT}" remote show origin | awk '/HEAD branch/ {print $NF}')

if git -C "${VCPKG_ROOT}" rev-parse --is-shallow-repository | grep -q true; then
    git -C "${VCPKG_ROOT}" fetch --quiet --unshallow origin "${DEFAULT_BRANCH}"
else
    git -C "${VCPKG_ROOT}" fetch --quiet origin "${DEFAULT_BRANCH}"
fi

git -C "${VCPKG_ROOT}" checkout --quiet "${DEFAULT_BRANCH}"
git -C "${VCPKG_ROOT}" reset --quiet --hard "origin/${DEFAULT_BRANCH}"
"${VCPKG_ROOT}/bootstrap-vcpkg.sh" -disableMetrics
vcpkg --version

# 用当前 HEAD commit sha 作为 builtin-baseline，动态生成 vcpkg.json
#    不写死版本号，每次构建都对应当时 vcpkg registry 的最新状态
BASELINE=$(git -C "${VCPKG_ROOT}" rev-parse HEAD)
jq --arg baseline "${BASELINE}" '.["builtin-baseline"] = $baseline' \
    /home/vscode/.vcpkg-manifest/vcpkg.json.in > /home/vscode/.vcpkg-manifest/vcpkg.json
cat /home/vscode/.vcpkg-manifest/vcpkg.json

# 按 manifest 安装依赖（两个 triplet 各跑一次）
#    x64-linux：在 amd64 宿主机上原生编译
#    arm64-linux：在 amd64 宿主机上交叉编译，产物供 arm64 目标设备使用
cd /home/vscode/.vcpkg-manifest
vcpkg install --triplet x64-linux   --x-install-root=/home/vscode/.vcpkg-manifest/vcpkg_installed
vcpkg install --triplet arm64-linux --x-install-root=/home/vscode/.vcpkg-manifest/vcpkg_installed
EOF

# downloads 使用 BuildKit cache mount（只加速重复构建，不进最终镜像，符合预期）
# archives 不使用 cache mount（编译产物必须进镜像层，供 import.sh 同步至持久化卷）
RUN --mount=type=cache,target=/home/vscode/.cache/vcpkg/downloads,id=vcpkg-downloads-cache,uid=1000,gid=1000 \
    set -eux \
    && chmod +x /tmp/build-vcpkg-deps.sh \
    && mkdir -p /home/vscode/.cache/vcpkg/downloads /home/vscode/.cache/vcpkg/archives \
    && chown -R vscode:vscode \
        /home/vscode/.cache/vcpkg \
        "${VCPKG_ROOT}" \
        /home/vscode/.vcpkg-manifest \
    && su vscode -c /tmp/build-vcpkg-deps.sh \
    && rm -f /tmp/build-vcpkg-deps.sh

# 收尾：验证环境变量、创建工作目录、切换到非 root 用户
RUN su vscode -c '\
        set -eux \
        && echo "PATH=$PATH" \
        && echo "VCPKG_ROOT=$VCPKG_ROOT" \
        && gcc --version \
        && g++ --version \
        && cpp --version \
        && gcc-14 --version || true \
        && g++-14 --version || true \
        && gcc-16 --version || true \
        && g++-16 --version || true \
        && clang --version \
        && clang++ --version \
    '
RUN set -eux \
    && mkdir -p /home/vscode/workspace \
    && chown vscode:vscode /home/vscode/workspace

USER vscode

# 保持容器前台运行，避免启动后立即退出
CMD ["sleep", "infinity"]
