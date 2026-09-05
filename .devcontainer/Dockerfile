# syntax=docker/dockerfile:1.7

# 所有用于 FROM 行的 ARG 必须声明在第一个 FROM 之前
ARG JDK_MAJOR_VERSION=21
ARG GCC_EXTRA_MAJOR_VERSION=16
ARG NODE_VARIANT=lts
ARG VARIANT=debian13

# 辅助阶段：Microsoft OpenJDK（distroless，实际路径 /usr/jdk）
FROM mcr.microsoft.com/openjdk/jdk:${JDK_MAJOR_VERSION}-distroless AS jdk-src

# 辅助阶段：Node.js LTS
# 务必用 Debian 系变体（默认即是），不要用 -alpine：musl 与基础镜像 glibc 不兼容
FROM node:${NODE_VARIANT} AS node-src

# 主阶段
# 基于 devcontainers/base 而非 devcontainers/cpp
FROM mcr.microsoft.com/devcontainers/base:${VARIANT}

# 重新声明 ARG，使其在当前 stage 的 RUN/COPY/ENV 中可用
ARG GCC_EXTRA_MAJOR_VERSION
ARG JDK_MAJOR_VERSION

# 架构防御：交叉编译工具链 / vcpkg triplet 均按 amd64 宿主机硬编码，
# 基础镜像解析为非 amd64（如 arm64 宿主机未加 --platform）时立即失败；
# 顺带让 vscode 对 /usr/local/bin 有写权限（uv tool install 的 BIN_DIR 指向此处）
RUN set -eux \
	&& [ "$(dpkg --print-architecture)" = "amd64" ] || { \
	        echo "FATAL: This Dockerfile only supports the construction of AMD64 basic images" >&2; \
	        exit 1; \
	    } \
	&& chown vscode:vscode /usr/local/bin

# 中文环境：locale / 字体 / 时区 / 中文 man
# 独立前置段：位于所有内容性安装之前，后续每一个构建步骤（GCC 探测、
# vcpkg、aqt、冒烟测试）都在 zh_CN.UTF-8 环境下执行，相当于整条构建链路
# 做过 locale 兼容性验证，问题在构建期暴露而非开发期
#
# 输出策略：成功时零确认回执——工具原生进度（apt/locale-gen）保留作为
# 操作证据；仅预期内异常向 stderr 写一行 NOTE，不阻断构建
#
# 设计要点：
#   - dpkg --add-architecture arm64 从"基础系统包"段前移至此：
#     本段 fonts-noto-cjk:arm64 的尝试安装需要 multiarch 已开启
#   - locales + locale-gen 是关键步骤：仅设 ENV 而无 locale 数据时，
#     zh_CN.UTF-8 是无效名字，glibc 静默回退 C 并刷警告
#   - fonts-noto-cjk 为 Multi-Arch: foreign（架构无关字体数据），
#     amd64 单实例即同时服务本机与 arm64 交叉程序；:arm64 副本在
#     co-install 场景通常被 dpkg 拒绝——if 取反：仅失败时 NOTE，成功静默
#   - man-db + manpages-zh：中文 man 页的查看器与内容，二者配套
#   - 时区三重一致：ENV TZ + /etc/localtime + /etc/timezone
#   - fc-cache 预生成缓存：Qt 字体发现走 fontconfig，免去首次 GUI 启动的全盘扫描
#   - 故意不设 LC_ALL：保留 "LC_ALL=C <cmd>" 的单命令逃生口
ARG DEBIAN_FRONTEND=noninteractive
RUN set -eux \
    && dpkg --add-architecture arm64 \
    && apt-get update \
    && apt-get -yq install --no-install-recommends \
        locales \
        tzdata \
        fontconfig \
        fonts-noto-cjk \
        man-db \
        manpages-zh \
        fonts-noto-cjk:arm64 \
    && rm -rf /var/lib/apt/lists/* \
    && grep -q '^zh_CN.UTF-8' /etc/locale.gen || echo 'zh_CN.UTF-8 UTF-8' >> /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh \
    && locale -a | grep -qi 'zh_CN.utf8' \
    && ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo 'Asia/Shanghai' > /etc/timezone \
    && fc-cache -f >/dev/null 2>&1 \
    && fc-list :lang=zh family | grep -qi 'noto sans cjk'

# 全局默认 locale 与时区：ENV 写入镜像元数据，容器内所有进程默认继承
ENV LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    TZ=Asia/Shanghai

# 中文环境冒烟验证：断言全部静默（-q / 重定向），失败即构建失败；
# 可选内容（中文 man 页）缺失仅 NOTE，不作为硬性失败
RUN set -eux \
    && locale | grep -q '^LANG=zh_CN' \
    && locale -a | grep -qi 'zh_CN.utf8' \
    && echo '中文字符流处理验证：简体 UTF-8' | grep -q '简体' \
    && test "$(date +%z)" = "+0800" \
    && readlink /etc/localtime | grep -q 'Asia/Shanghai' \
    && if command -v man >/dev/null 2>&1; then \
            man -w -L zh_CN.UTF-8 ls 2>/dev/null | grep -q '/zh_CN/'  || echo "NOTE: ls 中文 man 页缺失，man 将回退英文页" >&2; \
        fi

# 基础系统包
# 编译工具链
# build-essential/gdb/cppcheck/valgrind：base 镜像不含编译调试套件，
# 需显式补齐（cpp 变体隐式提供这些，改用 base 后必须自己声明）
ENV CCACHE_DIR=/home/vscode/.cache/ccache
ENV CCACHE_SLOPPINESS=file_macro,include_file_mtime,time_macros
ENV CCACHE_UMASK=002
RUN set -eux \
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
	    libgl1 \
	    libegl1 \
	    libgl1-mesa-dri \
	    libfontconfig1 \
        fonts-noto-cjk:arm64 \
	    libharfbuzz0b \
	    libxkbcommon0 \
	    libxkbcommon-x11-0 \
	    libx11-6 \
	    libx11-xcb1 \
	    libxcb1 \
	    libxcb-cursor0 \
	    libxcb-icccm4 \
	    libxcb-image0 \
	    libxcb-keysyms1 \
	    libxcb-randr0 \
	    libxcb-render0 \
	    libxcb-render-util0 \
	    libxcb-shape0 \
	    libxcb-shm0 \
	    libxcb-sync1 \
	    libxcb-xfixes0 \
	    libxcb-xinerama0 \
	    libxcb-xkb1 \
	    libxcb-util1 \
	    libxcomposite1 \
	    libxcursor1 \
	    libxdamage1 \
	    libxext6 \
	    libxi6 \
	    libxrandr2 \
	    libxrender1 \
	    libxtst6 \
	    libxshmfence1 \
	    libnss3 \
	    libnspr4 \
	    libdbus-1-3 \
	    libdrm2 \
	    libgbm1 \
	    libevent-2.1-7 \
	    libasound2 \
	    libpulse0 \
	    libopus0 \
	    libpng16-16 \
	    libjpeg62-turbo \
	    libgl-dev:arm64 \
	    libegl-dev:arm64 \
	    libgl1-mesa-dev:arm64 \
	    libgles2-mesa-dev:arm64 \
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
	&& apt-get autoremove -y \
	&& apt-get clean -y \
	&& ln -sf "$(command -v fdfind)" /usr/local/bin/fd \
	&& ln -sf "$(command -v batcat)" /usr/local/bin/bat \
	&& rm -rf /var/lib/apt/lists/* \
	&& mkdir -p "${CCACHE_DIR}" \
	&& chown -R vscode:vscode "${CCACHE_DIR}" \
	&& grep -q '^zh_CN.UTF-8' /etc/locale.gen \
        || echo 'zh_CN.UTF-8 UTF-8' >> /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh \
    && locale -a | grep -q 'zh_CN.utf8' \
    && fc-cache -f >/dev/null 2>&1 \
    && fc-list :lang=zh family | grep -i 'noto sans cjk' | head -n 3

# 全局默认 locale：简体中文 UTF-8
#   ENV 写入镜像元数据，容器内所有进程（构建、调试、终端）默认继承，
#   构建期后续 RUN 也在该环境下执行，相当于整条构建链路做过 locale 兼容验证
#   故意不设 LC_ALL：LANG/LANGUAGE 已足够让 glibc 走 UTF-8 + gettext 走简中翻译，
#   LC_ALL 留空可保留 "LC_ALL=C <cmd>" 的单命令逃生口（个别老式脚本对非 C locale 敏感）
ENV LANG=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh
RUN set -eux \
    && locale | grep -q '^LANG=zh_CN.UTF-8' \
    && echo '中文字符流处理验证：简体 UTF-8' | grep -q '中文字符流' \
    && echo "OK: locale=$(locale 2>/dev/null | grep '^LANG=' | tr -d '"')"

ENV TZ=Asia/Shanghai
RUN set -eux \
    && ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo 'Asia/Shanghai' > /etc/timezone \
    && date

# yq：mikefarah Go 版
RUN set -eux \
	&& curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
	&& chmod +x /usr/local/bin/yq \
	&& yq --version

# GCC 16：新增第二套 GCC 工具链（含 arm64 交叉），注册为系统默认
#
# 设计要点：
#   - 保留 build-essential 附带的系统默认 GCC（版本随基础镜像滚动，动态探测），
#     其配套 arm64 交叉工具已在"基础系统包"步骤安装（gcc/g++-aarch64-linux-gnu）
#   - GCC 16 从 Debian unstable 单独拉取：编译器本体（本机 + arm64 交叉）、
#     libgcc/libstdc++ dev 包、binutils-aarch64-linux-gnu 必须同源同事务安装，
#     保证汇编器认识新版编译器的输出（.aeabi_subsection 等新伪指令），
#     避免"本机编译通过、交叉编译失败"
#   - unstable 源配 APT Pinning（Pin-Priority 100），只影响显式 -t unstable
#     安装的包，装完立即移除；libc6-dev-arm64-cross（目标侧 sysroot）留在稳定源，
#     glibc 向后兼容，较旧目标头文件编译的产物可在更新的目标上运行
#   - 用 update-alternatives --slave 标准方式注册两套 GCC（Debian gcc-defaults 同款），
#     显式 --set 到 GCC 16 成为系统默认；旧版仍可用 gcc-14 版本化入口或
#     `update-alternatives --config gcc` 访问
#   - cpp 不经过 alternatives：Debian 的 cpp 替代组在此基础镜像中状态易损坏
#     （/etc/alternatives/cpp 会形成符号链接环，--install 报 Too many levels），
#     直接软链到 cpp-16 更稳；旧版 cpp-14 仍可用版本化入口调用
#   - 交叉编译器版本化入口 aarch64-linux-gnu-gcc-{14,16} 由各包自带，
#     无版本号入口软链指向默认版本（GCC 16）；cc/c++ 是 gcc-defaults 指向
#     gcc/g++ 主链接的 alternatives 组，随选择自动跟随
#   - 探测到的版本号落盘 /usr/local/share/gcc-{default,extra}-version，供冒烟测试读取
#   - LLVM/Clang 全系列工具链不受影响，仍走 /usr/local/bin 独立软链（见下文）
RUN set -eux \
	&& DEFAULT_GCC_VER="$(gcc -dumpversion | cut -d. -f1)" \
	&& echo "deb http://deb.debian.org/debian unstable main" > /etc/apt/sources.list.d/unstable.list \
	&& printf 'Package: *\nPin: release a=unstable\nPin-Priority: 100\n' > /etc/apt/preferences.d/unstable-pin \
	&& apt-get update \
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
	&& rm -f /etc/apt/sources.list.d/unstable.list /etc/apt/preferences.d/unstable-pin \
	&& apt-get update \
	&& apt-get autoremove -y \
	&& apt-get clean -y \
	&& rm -rf /var/lib/apt/lists/* \
	&& printf '%s\n' "${DEFAULT_GCC_VER}" > /usr/local/share/gcc-default-version \
	&& printf '%s\n' "${GCC_EXTRA_MAJOR_VERSION}" > /usr/local/share/gcc-extra-version \
	&& update-alternatives --install /usr/bin/gcc gcc "/usr/bin/gcc-${DEFAULT_GCC_VER}" "$((DEFAULT_GCC_VER * 10))" \
	    --slave /usr/bin/g++ g++ "/usr/bin/g++-${DEFAULT_GCC_VER}" \
	    --slave /usr/bin/gcc-ar gcc-ar "/usr/bin/gcc-ar-${DEFAULT_GCC_VER}" \
	    --slave /usr/bin/gcc-nm gcc-nm "/usr/bin/gcc-nm-${DEFAULT_GCC_VER}" \
	    --slave /usr/bin/gcc-ranlib gcc-ranlib "/usr/bin/gcc-ranlib-${DEFAULT_GCC_VER}" \
	    --slave /usr/bin/gcov gcov "/usr/bin/gcov-${DEFAULT_GCC_VER}" \
	    --slave /usr/bin/gcov-dump gcov-dump "/usr/bin/gcov-dump-${DEFAULT_GCC_VER}" \
	    --slave /usr/bin/gcov-tool gcov-tool "/usr/bin/gcov-tool-${DEFAULT_GCC_VER}" \
	&& update-alternatives --install /usr/bin/gcc gcc \
	    "/usr/bin/gcc-${GCC_EXTRA_MAJOR_VERSION}" "$((GCC_EXTRA_MAJOR_VERSION * 10))" \
	    --slave /usr/bin/g++ g++ "/usr/bin/g++-${GCC_EXTRA_MAJOR_VERSION}" \
	    --slave /usr/bin/gcc-ar gcc-ar "/usr/bin/gcc-ar-${GCC_EXTRA_MAJOR_VERSION}" \
	    --slave /usr/bin/gcc-nm gcc-nm "/usr/bin/gcc-nm-${GCC_EXTRA_MAJOR_VERSION}" \
	    --slave /usr/bin/gcc-ranlib gcc-ranlib "/usr/bin/gcc-ranlib-${GCC_EXTRA_MAJOR_VERSION}" \
	    --slave /usr/bin/gcov gcov "/usr/bin/gcov-${GCC_EXTRA_MAJOR_VERSION}" \
	    --slave /usr/bin/gcov-dump gcov-dump "/usr/bin/gcov-dump-${GCC_EXTRA_MAJOR_VERSION}" \
	    --slave /usr/bin/gcov-tool gcov-tool "/usr/bin/gcov-tool-${GCC_EXTRA_MAJOR_VERSION}" \
	&& update-alternatives --set gcc "/usr/bin/gcc-${GCC_EXTRA_MAJOR_VERSION}" \
	&& ln -sf "/usr/bin/cpp-${GCC_EXTRA_MAJOR_VERSION}" /usr/bin/cpp \
	&& ln -sf "/usr/bin/aarch64-linux-gnu-gcc-${GCC_EXTRA_MAJOR_VERSION}" /usr/bin/aarch64-linux-gnu-gcc \
	&& ln -sf "/usr/bin/aarch64-linux-gnu-g++-${GCC_EXTRA_MAJOR_VERSION}" /usr/bin/aarch64-linux-gnu-g++ \
	&& for c in gcc g++ cc c++ cpp aarch64-linux-gnu-gcc aarch64-linux-gnu-g++; do \
	        GOT="$("${c}" -dumpversion | cut -d. -f1)"; \
	        if [ "${GOT}" != "${GCC_EXTRA_MAJOR_VERSION}" ]; then \
	            echo "FATAL: ${c} 当前解析到 GCC ${GOT}，预期 ${GCC_EXTRA_MAJOR_VERSION}" >&2; \
	            exit 1; \
	        fi; \
	        echo "OK: ${c} -> GCC ${GOT}"; \
	    done

# .NET 10 LTS
RUN set -eux \
	&& wget https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb \
	    -O packages-microsoft-prod.deb \
	&& dpkg -i packages-microsoft-prod.deb \
	&& rm packages-microsoft-prod.deb \
	&& apt-get update \
	&& apt-get install -yq --no-install-recommends dotnet-sdk-10.0 \
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
	&& uv --version \
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
# uv 托管的 Python（python-build-standalone）bin/ 下必有 python3；
# python 一并软链跟随；pip 不做全局软链——本环境包管理统一走 uv（uv pip / uv tool）
RUN set -eux \
	&& PYTHON_BIN="$(uv python find --python-preference only-managed)" \
	&& [ -x "${PYTHON_BIN}" ] \
	&& ln -sf "${PYTHON_BIN}" /usr/local/bin/python3 \
	&& ln -sf "${PYTHON_BIN}" /usr/local/bin/python \
	&& python --version \
	&& python3 --version

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
	&& cmake --version \
	&& ninja --version \
	&& cmake-format --version \
	&& ruff --version \
	&& su vscode -c "\
	    set -eux \
	    && cmake --version \
	    && ruff --version \
	" \
	&& ln -sf /usr/local/bin/cmake /usr/bin/cmake \
	&& ln -sf /usr/local/bin/ninja /usr/bin/ninja

# LLVM/Clang 工具链：使用 apt.llvm.org 仓库，安装核心工具并避开 libclang-rt
RUN set -eux \
	&& LLVM_LATEST=$(curl -fsSL https://api.github.com/repos/llvm/llvm-project/releases/latest \
	    | grep -Po '"tag_name":\s*"llvmorg-\K[0-9]+') \
	&& curl -fsSL https://apt.llvm.org/llvm.sh -o /tmp/llvm.sh \
	&& chmod +x /tmp/llvm.sh \
	&& /tmp/llvm.sh "${LLVM_LATEST}" \
	&& apt-get install -y --no-install-recommends \
	    clang-format-${LLVM_LATEST} \
	    clang-tidy-${LLVM_LATEST} \
	    clang-tools-${LLVM_LATEST} \
	&& rm -f /tmp/llvm.sh \
	&& apt-get autoremove -y \
	&& apt-get clean -y \
	&& rm -rf /var/lib/apt/lists/* \
	&& for tool in clang clang++ clang-format clang-tidy clangd lldb lld ld.lld llvm-config; do \
	        src="/usr/bin/${tool}-${LLVM_LATEST}"; \
	        if [ -x "${src}" ]; then ln -sf "${src}" "/usr/local/bin/${tool}"; fi; \
	    done \
	&& clang --version \
	&& clang++ --version \
	&& clang-format --version \
	&& clang-tidy --version \
	&& clangd --version \
	&& lldb --version \
	&& llvm-config --version \
	&& command -v ld.lld

# 快速测试：以 vscode 用户验证三套工具链的本地与交叉编译能力（对应需求）：
#   1) 系统默认 GCC 系列（gcc-${DEF_VER}）：本地编译 + 运行 + file 检查，
#      arm64 交叉编译 + file 检查
#   2) 新增 GCC 16 系列（gcc-${NEW_VER}）：同上；并验证 gcc/g++/cc/c++/cpp
#      无版本号入口经 alternatives 解析后确实指向 16，以及 aarch64-linux-gnu-gcc
#      无版本号入口可交叉编译
#   3) LLVM Clang：本地编译 + 运行 + file 检查；arm64 交叉编译
#      （--target=aarch64-linux-gnu，经 --gcc-toolchain 复用 GCC 的 arm64 sysroot）
# 版本号从 GCC 配置阶段落盘的文件读取，不硬编码
RUN set -eux \
	&& su vscode -c '\
	    set -eux \
	    && DEF_VER="$(cat /usr/local/share/gcc-default-version)" \
	    && NEW_VER="$(cat /usr/local/share/gcc-extra-version)" \
	    && echo "smoke test: system gcc=${DEF_VER}, extra gcc=${NEW_VER}" \
	    && echo "int main() { return 0; }" > /tmp/test.c \
	    && echo "int main() { return 0; }" > /tmp/test.cpp \
	    && gcc-${DEF_VER} /tmp/test.c -o /tmp/test_def_c_local \
	    && g++-${DEF_VER} /tmp/test.cpp -o /tmp/test_def_cpp_local \
	    && file /tmp/test_def_c_local | grep -q "x86-64" \
	    && file /tmp/test_def_cpp_local | grep -q "x86-64" \
	    && /tmp/test_def_c_local && /tmp/test_def_cpp_local \
	    && aarch64-linux-gnu-gcc-${DEF_VER} /tmp/test.c -o /tmp/test_def_c_arm64 \
	    && aarch64-linux-gnu-g++-${DEF_VER} /tmp/test.cpp -o /tmp/test_def_cpp_arm64 \
	    && file /tmp/test_def_c_arm64 | grep -q "ARM aarch64" \
	    && file /tmp/test_def_cpp_arm64 | grep -q "ARM aarch64" \
	    && gcc-${NEW_VER} /tmp/test.c -o /tmp/test_new_c_local \
	    && g++-${NEW_VER} /tmp/test.cpp -o /tmp/test_new_cpp_local \
	    && file /tmp/test_new_c_local | grep -q "x86-64" \
	    && file /tmp/test_new_cpp_local | grep -q "x86-64" \
	    && /tmp/test_new_c_local && /tmp/test_new_cpp_local \
	    && aarch64-linux-gnu-gcc-${NEW_VER} /tmp/test.c -o /tmp/test_new_c_arm64 \
	    && aarch64-linux-gnu-g++-${NEW_VER} /tmp/test.cpp -o /tmp/test_new_cpp_arm64 \
	    && file /tmp/test_new_c_arm64 | grep -q "ARM aarch64" \
	    && file /tmp/test_new_cpp_arm64 | grep -q "ARM aarch64" \
	    && test "$(gcc -dumpversion | cut -d. -f1)" = "${NEW_VER}" \
	    && test "$(g++ -dumpversion | cut -d. -f1)" = "${NEW_VER}" \
	    && test "$(cpp -dumpversion | cut -d. -f1)" = "${NEW_VER}" \
	    && test "$(cc -dumpversion | cut -d. -f1)" = "${NEW_VER}" \
	    && test "$(c++ -dumpversion | cut -d. -f1)" = "${NEW_VER}" \
	    && aarch64-linux-gnu-gcc /tmp/test.c -o /tmp/test_entry_arm64 \
	    && file /tmp/test_entry_arm64 | grep -q "ARM aarch64" \
	    && clang /tmp/test.c -o /tmp/test_clang_c_local \
	    && clang++ /tmp/test.cpp -o /tmp/test_clang_cpp_local \
	    && file /tmp/test_clang_c_local | grep -q "x86-64" \
	    && file /tmp/test_clang_cpp_local | grep -q "x86-64" \
	    && /tmp/test_clang_c_local && /tmp/test_clang_cpp_local \
	    && clang --target=aarch64-linux-gnu \
	        --gcc-toolchain=/usr \
	        /tmp/test.c -o /tmp/test_clang_c_arm64 \
	        -fuse-ld=lld \
	    && clang++ --target=aarch64-linux-gnu \
	        --gcc-toolchain=/usr \
	        /tmp/test.cpp -o /tmp/test_clang_cpp_arm64 \
	        -fuse-ld=lld \
	    && file /tmp/test_clang_c_arm64 | grep -q "ARM aarch64" \
	    && file /tmp/test_clang_cpp_arm64 | grep -q "ARM aarch64" \
	    && rm -f /tmp/test_* \
	'

# Microsoft OpenJDK：从 distroless 镜像拷贝，
# 保留 JDK 是为了运行第三方 Java 工具链，不是本环境的开发核心
# 安装路径 / JAVA_HOME 由 JDK_MAJOR_VERSION 派生，与顶部全局 ARG 联动，改版本只动一处
ENV JAVA_HOME=/usr/lib/jvm/msopenjdk-${JDK_MAJOR_VERSION}
ENV PATH="${JAVA_HOME}/bin:${PATH}"
COPY --from=jdk-src /usr/jdk /usr/lib/jvm/msopenjdk-${JDK_MAJOR_VERSION}
RUN set -eux \
	&& java --version

# Node.js：多阶段拷贝，含 node-gyp 编译原生插件所需的头文件，顺带全局安装 codegraph
# corepack 已进入 Node 官方弃用流程（Node 25+ 移除），存在性判断保证届时构建仍可通过
COPY --from=node-src --chown=vscode:vscode /usr/local/include/node /usr/local/include/node
COPY --from=node-src --chown=vscode:vscode /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node-src /usr/local/bin/node /usr/local/bin/node
RUN set -eux \
	&& ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
	&& ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
	&& if [ -d /usr/local/lib/node_modules/corepack ]; then \
	        ln -sf /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack; \
	    fi \
	&& mkdir -p /home/vscode/.npm \
	&& chown -R vscode:vscode /home/vscode/.npm \
	&& su vscode -c "\
	    set -eux \
	    && if command -v corepack >/dev/null 2>&1; then corepack enable; fi \
	    && npm --version \
	    && node --version \
	    && npm i -g @colbymchenry/codegraph \
	    && codegraph --version \
	"

# 个人配置文件
# 母版统一放在 ~/.format/，作为唯一数据源：
#   - .vimrc          → ~/.vimrc（vim 固定读取此路径，单独软链）
#   - .clang-format   → ~/.clang-format（供开发者复制到项目目录）
#   - 其余文件通过 devcontainer.json 中各扩展的绝对路径直接引用
COPY --chown=vscode:vscode .format/ /home/vscode/.format/
# 预创建缓存目录并授权 vscode 用户，无论后续被具名卷覆盖还是 bind mount，权限保持一致
RUN set -eux \
	&& ln -sf /home/vscode/.format/.vimrc /home/vscode/.vimrc \
	&& chown -h vscode:vscode /home/vscode/.vimrc \
	&& ln -sf /home/vscode/.format/.clang-format /home/vscode/.clang-format \
	&& chown -h vscode:vscode /home/vscode/.clang-format \
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

# vcpkg：空架子或按 manifest 预编译依赖（WITH_VCPKG=1）
#
# 设计要点：
#   - 默认 WITH_VCPKG=0：只保留 vcpkg 本体——环境变量、官方仓库、vcpkg
#     可执行文件（clone 后 bootstrap），不编译任何库，构建快、体积小。
#   - WITH_VCPKG=1（build.sh --with-vcpkg）：按 vcpkg.json.in 预编译
#     x64 + arm64 两套依赖，耗时且占磁盘，仅在确实需要时开启。
#   VCPKG_DOWNLOADS 指向 /home/vscode/.cache/vcpkg/downloads，
#   与 --mount=type=cache 的挂载点及 import.sh 的具名卷路径保持一致，
#   是缓存持久化架构的组成部分，不可随意更改
#   VCPKG_BINARY_SOURCES 中 archives 路径故意不使用 cache mount，编译产物会提交进镜像层，
#   供 import.sh 同步至持久化具名卷（若也用 cache mount，archives 将只存在于 BuildKit
#   构建缓存，最终镜像中该路径为空，持久化卷无法从镜像获得初始内容）
ARG WITH_VCPKG=0
ENV VCPKG_ROOT=/usr/local/vcpkg
ENV VCPKG_DOWNLOADS=/home/vscode/.cache/vcpkg/downloads
ENV VCPKG_BINARY_SOURCES="clear;files,/home/vscode/.cache/vcpkg/archives,readwrite"
ENV VCPKG_FEATURE_FLAGS=manifests,versions,binarycaching
ENV VCPKG_FORCE_SYSTEM_BINARIES=1
ENV VCPKG_DEFAULT_TRIPLET=x64-linux
ENV PATH="${PATH}:${VCPKG_ROOT}"

# 显式 clone vcpkg（浅克隆即可，build-vcpkg-deps.sh 会自动 unshallow 补全历史）
RUN set -eux \
    && mkdir -p /home/vscode/.cache/vcpkg/downloads \
    && chown vscode:vscode /home/vscode/.cache/vcpkg/downloads \
    && git clone --depth 1 https://github.com/microsoft/vcpkg.git "${VCPKG_ROOT}" \
    && chown -R vscode:vscode "${VCPKG_ROOT}" \
    && su vscode -c "bash ${VCPKG_ROOT}/bootstrap-vcpkg.sh -disableMetrics" \
    && "${VCPKG_ROOT}/vcpkg" version

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
bash "${VCPKG_ROOT}/bootstrap-vcpkg.sh" -disableMetrics
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

# archives 里已经有二进制缓存，buildtrees 和 packages 删掉无损
rm -rf /home/vscode/.vcpkg-manifest/buildtrees \
       /home/vscode/.vcpkg-manifest/packages
EOF

# downloads 使用 BuildKit cache mount（只加速重复构建，不进最终镜像，符合预期）
# archives 不使用 cache mount（编译产物必须进镜像层，供 import.sh 同步至持久化卷）
# 只有 WITH_VCPKG=1（build.sh --with-vcpkg）才真正执行 manifest 依赖编译
RUN --mount=type=cache,target=/home/vscode/.cache/vcpkg/downloads,id=vcpkg-downloads-cache,uid=1000,gid=1000 \
	set -eux \
	&& chmod +x /tmp/build-vcpkg-deps.sh \
	&& mkdir -p /home/vscode/.cache/vcpkg/downloads /home/vscode/.cache/vcpkg/archives \
	&& chown -R vscode:vscode /home/vscode/.cache/vcpkg "${VCPKG_ROOT}" /home/vscode/.vcpkg-manifest \
	&& if [ "${WITH_VCPKG}" = "1" ]; then \
	        su vscode -c /tmp/build-vcpkg-deps.sh; \
	    fi \
	&& rm -f /tmp/build-vcpkg-deps.sh

# ccache：官方推荐的"驱动软链"接入方式（Debian 惯例路径 /usr/lib/ccache）
#   ccache 以 gcc/g++/cc/c++ 之名软链到 /usr/lib/ccache 并前置进 PATH，
#   所有经 PATH 解析的编译调用透明经过缓存，无需改动任何构建脚本
#   已知取舍：command -v gcc 将显示 /usr/lib/ccache/gcc（ccache 驱动），属标准代价；
#   版本化调用（gcc-16 等）不经缓存，需要时照样式补软链
#   注意：本段必须位于 vcpkg 构建之后——ENV 只对其后的 RUN 生效，
#   构建期 vcpkg 编译（仅 WITH_VCPKG=1 时）走自身 binary caching，
#   不应经 ccache 把缓存写进镜像层；运行期（开发时）才启用拦截
RUN set -eux \
	&& mkdir -p /usr/lib/ccache \
	&& for t in gcc g++ cc c++; do ln -sf /usr/bin/ccache "/usr/lib/ccache/${t}"; done \
	&& /usr/lib/ccache/gcc --version | head -n1 \
	&& ccache --version | head -n1

ENV PATH="/usr/lib/ccache:${PATH}"

# 创建工作目录、切换到非 root 用户
RUN set -eux \
	&& mkdir -p /home/vscode/workspace \
	&& chown vscode:vscode /home/vscode/workspace

USER vscode
WORKDIR /home/vscode

# 保持容器前台运行，避免启动后立即退出
CMD ["sleep", "infinity"]
