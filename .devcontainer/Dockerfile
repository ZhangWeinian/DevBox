# syntax=docker/dockerfile:1.7

# 需要用于 FROM 行的 ARG 必须全部声明在第一个 FROM 之前
ARG JDK_MAJOR_VERSION=21
ARG NODE_VARIANT=lts

# 阶段一：Microsoft OpenJDK（实际路径 /usr/jdk）
FROM mcr.microsoft.com/openjdk/jdk:${JDK_MAJOR_VERSION}-distroless AS jdk-src

# 阶段二：Node.js LTS
# 务必用 Debian 系变体（默认即是），不要用 -alpine（musl 与基础镜像 glibc 不兼容）
FROM node:${NODE_VARIANT} AS node-src

# 主阶段
FROM mcr.microsoft.com/devcontainers/cpp:3-debian13

# 基础系统包
# 含 python3（确保 uv pip install --system 不依赖 Feature 执行顺序）
# 含 ccache（C/C++ 编译加速）
# 含 fd-find（Debian 包名，实际二进制为 fdfind，下方补 fd 软链）
RUN set -eux \
    && apt-get update \
    && apt-get -yq upgrade \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -yq install --no-install-recommends \
        libboost-all-dev \
        libssl-dev \
        libgl-dev \
        sudo \
        curl \
        zip \
        unzip \
        tar \
        net-tools \
        tcpdump \
        iperf3 \
        pkg-config \
        gdb \
        ccache \
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

# uv：官方多架构镜像
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Python：通过 uv 安装最新版本，并全局软链，这样全程只有一套 Python，工具链和临时脚本都能找到
RUN set -eux \
    && uv python install --python-preference only-managed \
    && PYTHON_DIR=$(dirname "$(uv python find --python-preference only-managed)") \
    && echo "Resolved Python dir: ${PYTHON_DIR}" \
    && ln -sf "${PYTHON_DIR}/python" /usr/local/bin/python \
    && ln -sf "${PYTHON_DIR}/python3" /usr/local/bin/python3 \
    && ln -sf "${PYTHON_DIR}/pip" /usr/local/bin/pip \
    && ln -sf "${PYTHON_DIR}/pip3" /usr/local/bin/pip3

# CMake / Ninja / cmake-format：通过 uv tool install（隔离虚拟环境）
ENV UV_TOOL_BIN_DIR=/usr/local/bin
RUN set -eux \
    && uv tool install cmake \
    && uv tool install ninja \
    && uv tool install cmakelang \
    && uv tool install autoenv \
    && uv tool install ruff
RUN set -eux \
    && python --version \
    && pip --version \
    && cmake --version \
    && ninja --version \
    && cmake-format --version \
    && ruff --version

# clang-format：用 LLVM 官方 apt 仓库（apt.llvm.org），版本号动态查询 GitHub 最新 release
RUN set -eux \
    && apt-get update \
    && apt-get install -yq --no-install-recommends lsb-release gnupg wget \
    && LLVM_LATEST=$(curl -fsSL https://api.github.com/repos/llvm/llvm-project/releases/latest \
         | grep -Po '"tag_name":\s*"llvmorg-\K[0-9]+') \
    && echo "Resolved latest LLVM major version: ${LLVM_LATEST}" \
    && curl -fsSL https://apt.llvm.org/llvm.sh -o /tmp/llvm.sh \
    && chmod +x /tmp/llvm.sh \
    && /tmp/llvm.sh "${LLVM_LATEST}" \
    && apt-get install -y --no-install-recommends "clang-format-${LLVM_LATEST}" \
    && ln -sf "/usr/bin/clang-format-${LLVM_LATEST}" /usr/local/bin/clang-format \
    && rm -f /tmp/llvm.sh \
    && rm -rf /var/lib/apt/lists/* \
    && clang-format --version

# Microsoft OpenJDK：从 distroless 镜像拷贝，实际路径为 /usr/jdk
# 保留 JDK 是为了运行第三方 Java 工具链（非本环境的格式化/开发核心）
COPY --from=jdk-src /usr/jdk /usr/lib/jvm/msopenjdk-21

ENV JAVA_HOME=/usr/lib/jvm/msopenjdk-21
ENV PATH="${JAVA_HOME}/bin:${PATH}"
RUN set -eux \
    && java --version

# Node.js：多阶段拷贝，含 node-gyp 编译原生插件所需的头文件
# 这里顺带使用 npm 安装 codegraph
COPY --from=node-src /usr/local/include/node /usr/local/include/node
COPY --from=node-src /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node-src /usr/local/bin/node /usr/local/bin/node
RUN set -eux \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && if [ -d /usr/local/lib/node_modules/corepack ]; then \
        ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack; \
    fi \
    && corepack enable \
    && npm i -g @colbymchenry/codegraph \
    && codegraph --version

# vcpkg：刷新注册表到最新
# 用 fetch + checkout + reset 代替直接 git pull，兼容 detached HEAD 状态（官方基础镜像有时固定在某个 commit 而非分支）
RUN set -eux \
    && DEFAULT_BRANCH=$(git -C "${VCPKG_ROOT}" remote show origin | awk '/HEAD branch/ {print $NF}') \
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

#-----------------------------------------------------
# 个人配置文件：母版统一放在 ~/.format/，作为唯一数据源
# - .vimrc：vim 固定读取 ~/.vimrc，单独软链
# - 其余五个文件：均通过 devcontainer.json 中各扩展的绝对路径设置直接引用，本身不需要出现在任何项目目录中
# - 仅 .clang-format 例外：clang-format 采用"从文件所在目录向上查找"的机制，因此需要 link-default-configs.sh 在每个项目根目录下补一个软链接
#-----------------------------------------------------
COPY --chown=vscode:vscode .format/ /home/vscode/.format/

RUN set -eux \
    && ln -sf /home/vscode/.format/.vimrc /home/vscode/.vimrc \
    && chown -h vscode:vscode /home/vscode/.vimrc

COPY scripts/link-default-configs.sh /usr/local/bin/link-default-configs.sh
RUN set -eux \
    && chmod +x /usr/local/bin/link-default-configs.sh

# 预创建全部缓存目录并授权 vscode 用户
# 无论后续被 bind mount 覆盖，还是在冻结导出时被 COPY 填充，权限保持一致
RUN set -eux \
    && mkdir -p \
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
# RUN set -eux \
#     && su vscode -c "${VCPKG_ROOT}/vcpkg install <your-port-name-here>"
