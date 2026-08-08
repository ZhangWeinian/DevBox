# syntax=docker/dockerfile:1.7

# 需要用于 FROM 行的 ARG 必须全部声明在第一个 FROM 之前
ARG JDK_MAJOR_VERSION=21
ARG NODE_VARIANT=lts

FROM mcr.microsoft.com/openjdk/jdk:${JDK_MAJOR_VERSION}-distroless AS jdk-src

# 务必用 Debian 系变体（默认即是），不要用 -alpine（musl 与基础镜像 glibc 不兼容）
FROM node:${NODE_VARIANT} AS node-src

FROM mcr.microsoft.com/devcontainers/cpp:3-debian13

# 基础系统包
# 含 python3（确保 uv pip install --system 不依赖 Feature 执行顺序）
# 含 ccache（C/C++ 编译加速）
# 含 fd-find（Debian 包名，实际二进制为 fdfind，下方补 fd 软链）
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        libboost-all-dev \
        libssl-dev \
        curl \
        zip \
        unzip \
        tar \
        pkg-config \
        gdb \
        ccache \
        python3 \
        libudev-dev \
        libbz2-dev \
        libzstd-dev \
        zlib1g-dev \
        liblzma-dev \
        rsync \
        file \
        autoconf \
        automake \
        libtool \
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
    && ln -sf "$(command -v fdfind)" /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

# uv：官方多架构镜像，BuildKit 按目标平台自动选取
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# CMake / Ninja：Kitware/Ninja 官方 PyPI 预编译 wheel
# 注意：不含 ccmake / cmake-gui，如需要请额外 apt install cmake-curses-gui
RUN uv pip install --system --break-system-packages --no-cache cmake ninja \
    && cmake --version && ninja --version

# Microsoft OpenJDK：从 distroless 镜像拷贝
COPY --from=jdk-src /usr/jdk /usr/lib/jvm/msopenjdk-21

ENV JAVA_HOME=/usr/lib/jvm/msopenjdk-21
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Node.js：多阶段拷贝，含 node-gyp 编译原生插件所需的头文件
COPY --from=node-src /usr/local/include/node /usr/local/include/node
COPY --from=node-src /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node-src /usr/local/bin/node /usr/local/bin/node
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && if [ -d /usr/local/lib/node_modules/corepack ]; then \
        ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack; \
    fi \
    && corepack enable

# vcpkg：刷新注册表到最新
# 用 fetch + checkout + reset 代替直接 git pull，兼容 detached HEAD 状态（官方基础镜像有时固定在某个 commit 而非分支）
RUN DEFAULT_BRANCH=$(git -C "${VCPKG_ROOT}" remote show origin | awk '/HEAD branch/ {print $NF}') \
    && git -C "${VCPKG_ROOT}" fetch --quiet origin "${DEFAULT_BRANCH}" \
    && git -C "${VCPKG_ROOT}" checkout --quiet "${DEFAULT_BRANCH}" \
    && git -C "${VCPKG_ROOT}" reset --quiet --hard "origin/${DEFAULT_BRANCH}" \
    && "${VCPKG_ROOT}/bootstrap-vcpkg.sh" -disableMetrics

# 工具链缓存目录环境变量（与 devcontainer.json 的 bind mount 路径对应）
ENV VCPKG_DOWNLOADS=/home/vscode/.cache/vcpkg/downloads
ENV VCPKG_BINARY_SOURCES="clear;files,/home/vscode/.cache/vcpkg/archives,readwrite"
ENV VCPKG_FEATURE_FLAGS=manifests,versions,binarycaching
ENV UV_CACHE_DIR=/home/vscode/.cache/uv
ENV PIP_CACHE_DIR=/home/vscode/.cache/pip
ENV CCACHE_DIR=/home/vscode/.cache/ccache

# 预创建全部缓存目录并授权 vscode 用户
# 无论后续被 bind mount 覆盖，还是在冻结导出时被 COPY 填充，权限保持一致
RUN mkdir -p \
        /home/vscode/.cache/vcpkg/downloads \
        /home/vscode/.cache/vcpkg/archives \
        /home/vscode/.cache/ccache \
        /home/vscode/.cache/uv \
        /home/vscode/.cache/pip \
        /home/vscode/.npm \
        /home/vscode/.local/share/pnpm/store \
        /home/vscode/.cache/yarn \
        /home/vscode/.m2 \
        /home/vscode/.gradle \
        /home/vscode/.vscode-server \
    && chown -R vscode:vscode \
        /home/vscode/.cache \
        /home/vscode/.npm \
        /home/vscode/.local \
        /home/vscode/.m2 \
        /home/vscode/.gradle \
        /home/vscode/.vscode-server

# [Optional] 预装 vcpkg 端口（manifest 模式项目一般不需要这里预装）
# RUN su vscode -c "${VCPKG_ROOT}/vcpkg install <your-port-name-here>"
