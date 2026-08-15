# syntax=docker/dockerfile:1.7

# 所有用于 FROM 行的 ARG 必须声明在第一个 FROM 之前
ARG JDK_MAJOR_VERSION=21
ARG NODE_VARIANT=lts
ARG VARIANT=debian13

# 辅助阶段：Microsoft OpenJDK（distroless，实际路径 /usr/jdk）
FROM mcr.microsoft.com/openjdk/jdk:${JDK_MAJOR_VERSION}-distroless AS jdk-src

# 辅助阶段：Node.js LTS
# 务必用 Debian 系变体（默认即是），不要用 -alpine：musl 与基础镜像 glibc 不兼容
FROM node:${NODE_VARIANT} AS node-src

# 辅助阶段：架构防御检测
# 此镜像的交叉编译工具链 / vcpkg triplet 均按 amd64 宿主机硬编码
# 若基础镜像被解析为非 amd64（例如在 arm64 宿主机上未加 --platform 直接构建），立即报错终止，避免后续在 vcpkg 阶段才出现难以定位的失败
# 使用独立 stage 检测，不依赖主阶段基础镜像是否自带 dpkg
FROM mcr.microsoft.com/devcontainers/base:${VARIANT} AS arch-check
RUN set -eux \
    && ARCH="$(dpkg --print-architecture)" \
    && if [ "${ARCH}" != "amd64" ]; then \
        echo "FATAL: 此 Dockerfile 仅支持 amd64 基础镜像构建，检测到当前架构为 ${ARCH}" >&2; \
        echo "请在 x86_64 宿主机上构建，或使用 --platform linux/amd64 强制模拟" >&2; \
        exit 1; \
    fi

# 主阶段
# 基于 devcontainers/base 而非 devcontainers/cpp
FROM mcr.microsoft.com/devcontainers/base:${VARIANT}

# 让 vscode 对 /usr/local/bin 有写权限（uv tool install 的 BIN_DIR 指向此处）
RUN chown vscode:vscode /usr/local/bin

# 基础系统包
# 编译工具链
#   build-essential/gdb/cppcheck/valgrind：base 镜像不含编译调试套件，需显式补齐（cpp 变体隐式提供这些，改用 base 后必须自己声明）
#   注意：cmake 不在此处安装，由后续 uv tool install cmake 提供，避免 apt 版（版本较旧）与 uv 版（构建时最新）重复安装造成歧义
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

# Python：通过 uv 安装最新受管理版本，并建立全局软链，全程只有一套 Python，工具链和临时脚本都能找到，不产生版本歧义
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

# clang-format：LLVM 官方 apt 仓库（apt.llvm.org），版本号动态查询 GitHub 最新 release，不写死版本号
RUN set -eux \
    && apt-get update \
    && LLVM_LATEST=$(curl -fsSL https://api.github.com/repos/llvm/llvm-project/releases/latest \
         | grep -Po '"tag_name":\s*"llvmorg-\K[0-9]+') \
    && echo "Resolved latest LLVM major version: ${LLVM_LATEST}" \
    && curl -fsSL https://apt.llvm.org/llvm.sh -o /tmp/llvm.sh \
    && chmod +x /tmp/llvm.sh \
    && /tmp/llvm.sh "${LLVM_LATEST}" \
    && apt-get install -y --no-install-recommends "clang-format-${LLVM_LATEST}" \
    && ln -sf "/usr/bin/clang-format-${LLVM_LATEST}" /usr/local/bin/clang-format \
    && rm -f /tmp/llvm.sh \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && clang-format --version

# Microsoft OpenJDK 21：从 distroless 镜像拷贝，保留 JDK 是为了运行第三方 Java 工具链，不是本环境的开发核心
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
#   - .clang-format   → ~/default.clang-format（供开发者复制到项目目录）
#   - 其余文件通过 devcontainer.json 中各扩展的绝对路径直接引用
COPY --chown=vscode:vscode .format/ /home/vscode/.format/
RUN set -eux \
    && ln -sf /home/vscode/.format/.vimrc        /home/vscode/.vimrc \
    && chown -h vscode:vscode                    /home/vscode/.vimrc \
    && ln -sf /home/vscode/.format/.clang-format /home/vscode/default.clang-format \
    && chown -h vscode:vscode                    /home/vscode/default.clang-format

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
#   VCPKG_DOWNLOADS 指向 /home/vscode/.cache/vcpkg/downloads，与 --mount=type=cache 的挂载点及 import.sh 的具名卷路径保持一致，是缓存持久化架构的组成部分，不可随意更改
#   VCPKG_BINARY_SOURCES 中 archives 路径故意不使用 cache mount，编译产物会提交进镜像层，供 import.sh 同步至持久化具名卷（若也用 cache mount，archives 将只存在于 BuildKit 构建缓存，最终镜像中该路径为空，持久化卷无法从镜像获得初始内容）
ENV VCPKG_ROOT=/usr/local/vcpkg
ENV VCPKG_DOWNLOADS=/home/vscode/.cache/vcpkg/downloads
ENV VCPKG_BINARY_SOURCES="clear;files,/home/vscode/.cache/vcpkg/archives,readwrite"
ENV VCPKG_FEATURE_FLAGS=manifests,versions,binarycaching
ENV VCPKG_FORCE_SYSTEM_BINARIES=1
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
    echo "==> Detected shallow vcpkg clone, unshallowing..."
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
echo "==> Resolved latest vcpkg builtin-baseline: ${BASELINE}"
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
    '
RUN set -eux \
    && mkdir -p /home/vscode/workspace \
    && chown vscode:vscode /home/vscode/workspace

USER vscode

# 保持容器前台运行，避免启动后立即退出
CMD ["sleep", "infinity"]
