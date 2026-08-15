# 通用 C++/Python 多架构开发容器

一个自用的、包含最新工具链、可离线部署的 Docker 开发环境模板。

基于`mcr.microsoft.com/devcontainers/base:debian13` 官方镜像扩展，单次构建同时产出针对`x64-linux` 和 `arm64-linux` 两个目标平台的预编译库，供后续项目直接链接使用。

## 特性

- **构建时刻即最新**：系统包、编译器工具链（CMake/Ninja/ruff 等）、vcpkg 依赖版本，默认每次构建都重新拉取当前最新版本，不锁定历史版本号（详见「设计原则」）
- **交叉编译双目标**：单次构建在 `amd64` 宿主机上，同时产出 `x64-linux` 与 `arm64-linux` 两套 vcpkg 预编译库，供不同目标架构的项目复用
- **工具链完整**：`C++`（CMake/Ninja/Boost/GCC）、`Python`（uv）、`.NET 10`、`Java 21`、`Node.js LTS`、`vcpkg`、`clang-format`、`cmake-format` 等
- **编译加速**：集成 `ccache` 与 `ninja`，并通过 vcpkg 二进制缓存（具名卷持久化）避免重复编译第三方库
- **离线友好**：构建时一次拉齐所有工具链，`docker save` 导出静态镜像，离线设备无需网络即可编译
- **缓存独立于镜像生命周期**：所有下载/编译缓存以 Docker 具名卷形式持久化，重新构建镜像不会导致缓存清零
- **基座可维护性强**：主阶段基于 `devcontainers/base:${VARIANT}` 而非 `devcontainers/cpp`，升级 Debian 版本时只需修改一个 `ARG`，无需追踪 Microsoft cpp 变体内部策展逻辑的变化

## 快速开始

### 前置要求

- **仅支持在 `x86_64`（amd64）宿主机上构建镜像**（见下方「架构支持范围」说明），需要 Docker 具备 BuildKit 能力（现代 Docker 版本默认已启用）
- `Linux`/`WSL2` 环境；`Windows` 用户强烈建议在 `WSL2` 文件系统内操作（而非 Windows 原生路径），否则容器内文件 I/O 性能会明显下降
- `macOS`（Apple Silicon）用户注意：本机是 `arm64` 架构，无法直接构建，仅能作为**离线运行方使用他人构建好的 amd64 镜像**（需 Docker Desktop 内置 QEMU 支持，性能会有明显损失）

```bash
git clone <此仓库>
cd DevBox/.devcontainer
chmod +x build.sh export.sh import.sh
```

### 构建镜像

```bash
# 默认：完全重新构建（--no-cache --pull），保证一切都是构建这一刻的最新版本
./build.sh

# 调试 Dockerfile 时：吃 Docker 层缓存，加速迭代，但不保证最新
./build.sh --use-cache
```

> `build.sh` 会在开头检测宿主机架构，非 `x86_64/amd64` 会直接拒绝构建并报错退出，避免绕了一大圈才在 vcpkg 阶段失败。

### 导出静态镜像包

```bash
# 导出到当前目录
./export.sh

# 导出到指定目录（不存在则自动创建）
./export.sh /path/to/output
```

生成 `devenv-<架构>-<日期_时间>.tar`（例如 `devenv-amd64-20260810_223000.tar`）。
架构标签取自镜像自身元数据（`docker image inspect --format '{{.Architecture}}'`），保证标签始终真实准确。

### 在目标设备上导入并启动

```bash
# 使用本地已有镜像，挂载默认目录 ~/workspace
./import.sh

# 使用本地已有镜像，挂载指定目录
./import.sh /path/to/your/project

# 加载 tar，挂载默认目录 ~/workspace
./import.sh devenv-amd64-xxx.tar

# 加载 tar，挂载指定目录
./import.sh devenv-amd64-xxx.tar /path/to/proj
```

`import.sh` 会自动：

1. 校验镜像架构与当前宿主机架构是否一致（不一致默认拒绝启动）
2. 挂载全部持久化缓存卷（vcpkg / uv / npm / .vscode-server 等，见「缓存卷」）
3. 把镜像内构建期烘焙好的 vcpkg 二进制缓存增量同步进持久化卷
4. 启动容器并修正缓存目录权限

### 日常开发（VS Code）

1. 启动容器后，打开 VS Code，按 `F1` → "开发容器: 附加到正在运行的容器"
2. 选择容器 `dev-container`，即可开始开发
3. 项目代码通过 bind mount 挂载，保存在宿主机目录中，容器重建不会丢失代码

## 架构支持范围

本模板**当前只支持在 `amd64`（x86_64）宿主机上构建**，产出的镜像本身也是 `amd64` 架构。

Dockerfile 里的交叉编译工具链（`gcc-aarch64-linux-gnu` 等）和 vcpkg triplet 配置，均按"amd64 宿主机 → 交叉编译出 arm64 目标库"这个单向假设硬编码：

| 维度 | 说明 |
|:---|:---|
| **构建** | 只能在 `amd64` 机器上跑 `./build.sh`，非 `amd64` 机器会被脚本提前拦截报错 |
| **vcpkg 产出** | 一次构建同时生成 `x64-linux`（原生）和 `arm64-linux`（交叉）两套预编译库的二进制缓存 |
| **容器运行** | 镜像本身只能原生运行在 `amd64` 宿主机；`import.sh` 会检测架构，不一致时默认拒绝启动 |
| **强制模拟** | 可加 `--allow-arch-mismatch` 通过 QEMU 模拟运行，速度明显变慢，仅建议临时应急 |

如需"在 arm64 宿主机上原生构建"，需额外补一套反方向的交叉编译工具链配置，当前版本尚未支持。

## 基座镜像选型说明

主阶段基于 `mcr.microsoft.com/devcontainers/base:${VARIANT}` 而非`mcr.microsoft.com/devcontainers/cpp:3-debian13`。

| 维度 | `cpp:3-debian13` | `base:${VARIANT}`（当前方案） |
|:---|:---|:---|
| 绑定的版本轴 | OS 发行版 + Microsoft C++ 工具链策展版本（两条独立轴） | 仅 OS 发行版（一条轴） |
| 升级 Debian 版本 | 需追踪 cpp 变体策展逻辑是否同步变动，隐式依赖可能静默失效 | 只改 `ARG VARIANT`，影响范围完全在自己的代码里 |
| 工具链来源 | cmake/clang/lldb/llvm 等由 Microsoft 隐式捆绑 | 全部在本 Dockerfile 显式声明，依赖关系一目了然 |
| 冗余内容 | 捆绑了我们不用的 cmake（被 uv 版覆盖）、clang/lldb/llvm（不需要）| 无冗余，只装用到的 |
| vcpkg 初始状态 | 隐式依赖 Microsoft 脚本在某个时间点 clone 的结果 | 显式 `git clone --depth 1`，初始状态完全可控 |

`cpp` 变体原本隐式提供的内容（`build-essential`、`gdb`、`cppcheck`、`valgrind`、vcpkg 本体），现在全部在本 Dockerfile 中显式声明，行为完全等价，但依赖关系透明可见。

## 工具链清单

| 工具 | 版本策略 | 来源 |
|:---|:---|:---|
| GCC / G++ | Debian 13 stock（约 14.x） | apt（`build-essential`） |
| GDB | Debian 13 stock（约 15.x） | apt |
| cppcheck | Debian 13 stock | apt |
| valgrind | Debian 13 stock | apt |
| CMake | 构建时最新 | `uv tool install cmake` |
| Ninja | 构建时最新 | `uv tool install ninja` |
| cmake-format | 构建时最新 | `uv tool install cmakelang` |
| ruff | 构建时最新 | `uv tool install ruff` |
| autoenv | 构建时最新 | `uv tool install autoenv` |
| Python | uv 托管的最新稳定版 | `uv python install` |
| uv / uvx | 构建时最新 | `ghcr.io/astral-sh/uv:latest` |
| .NET SDK | 10.0 LTS | `packages.microsoft.com` apt 源 |
| Java | 21 LTS | Microsoft OpenJDK distroless 镜像 |
| Node.js | 构建时最新 LTS | `docker.io/library/node:lts` |
| npm / corepack | 随 Node.js 附带 | Node.js 官方发行 |
| codegraph | 构建时最新 | npm 全局安装 |
| vcpkg | 构建时最新（动态 fetch 到 registry HEAD） | Microsoft 官方仓库（显式 clone） |
| ccache | Debian 13 stock | apt |
| clang-format | 构建时最新 major 版本 | LLVM 官方 `apt.llvm.org`（动态查询） |
| Boost | Debian 13 stock（系统级）+ vcpkg 最新（manifest） | apt / vcpkg |

> **关于 GCC/GDB 版本**：曾评估通过源码编译追新到 GCC 15 / GDB 17，但编译耗时与镜像体积代价过高，性价比不足，维持 Debian 13 stock 版本。

> 如需更新的编译器特性，可另行通过 LLVM apt 源安装最新 Clang 作为备选工具链。

## vcpkg 依赖清单

依赖声明维护在 `vcpkg.json.in`（不含 `builtin-baseline` 字段，由构建脚本动态注入）：

```json
{
  "name": "devbox-prebuilt-deps",
  "version": "1.0.0",
  "dependencies": [
    "boost", 
    "openssl", 
    "pugixml", 
    "yaml-cpp", 
    "fmt", 
    "spdlog",
    "libzip", 
    "opus", 
    "libusb", 
    "libhv", 
    "paho-mqtt", 
    "paho-mqttpp3",
    "abseil", 
    "asio", 
    "cli11", 
    "eventpp", 
    "cpp-httplib", 
    "range-v3",
    "cereal", 
    "gsl", 
    "tl-expected", 
    "nlohmann-json", 
    "gtest", 
    "benchmark",
    "yalantinglibs", 
    "re2", 
    "gflags", 
    "sqlite3", 
    "slick-net",
    "drogon", 
    "neko-network", 
    "oatpp-curl"
  ]
}
```

构建时，`build-vcpkg-deps.sh` 脚本会自动完成以下步骤：

1. 把 `$VCPKG_ROOT` 刷新到当前默认分支最新 commit，并自动检测/修复浅克隆（`--unshallow`），避免解析历史版本 port 时因缺少完整 git 历史而失败
2. 用刷新后的 `HEAD` commit sha 作为 `builtin-baseline`，动态拼装出最终的 `vcpkg.json`
3. 分别针对 `x64-linux` 与 `arm64-linux` 两个 triplet 执行 `vcpkg install`，产出的二进制缓存写入 `/home/vscode/.cache/vcpkg/archives`（提交进镜像层）

如需增删依赖，直接编辑 `vcpkg.json.in` 的 `dependencies` 数组即可，`builtin-baseline` 每次构建都会重新生成，无需手动维护。

## 缓存卷与持久化

运行时缓存以 Docker **具名卷**（named volume）形式持久化，由 `import.sh` 统一管理挂载。

| 卷名 | 容器内路径 | 用途 |
|:---|:---|:---|
| `devenv-cache-vcpkg` | `/home/vscode/.cache/vcpkg` | vcpkg 源码下载 + 二进制缓存 |
| `devenv-cache-uv` | `/home/vscode/.cache/uv` | uv 包缓存 |
| `devenv-cache-pip` | `/home/vscode/.cache/pip` | pip 缓存（备用） |
| `devenv-cache-ccache` | `/home/vscode/.cache/ccache` | C/C++ 编译缓存 |
| `devenv-cache-npm` | `/home/vscode/.npm` | npm 缓存 |
| `devenv-cache-yarn` | `/home/vscode/.cache/yarn` | yarn 缓存 |
| `devenv-cache-pnpm-store` | `/home/vscode/.local/share/pnpm/store` | pnpm 全局存储 |
| `devenv-cache-m2` | `/home/vscode/.m2` | Maven 仓库 |
| `devenv-cache-gradle` | `/home/vscode/.gradle` | Gradle 缓存 |
| `devenv-cache-vscode-server` | `/home/vscode/.vscode-server` | VS Code Server 及扩展 |

**具名卷的核心优势**：独立于 image tag 存在，重新 `build` 出新镜像、`import` 启动新容器时，
只要卷名不变就会自动复用旧卷内容——实现"镜像随便重新构建，开发缓存持续累积、无缝续用"。

**注意**：具名卷内容不会被 `export.sh` 打包进 `.tar`，只存在于当前宿主机的 Docker Engine 里。跨机器分发时，只有镜像本身携带的初始 vcpkg 缓存内容会被带过去，容器运行后累积的缓存不随`.tar` 迁移。

如需清空某个/全部缓存卷：

```bash
# 精确清空某一个
docker volume rm devenv-cache-<后缀>

# 清空全部后重新启动
./import.sh --reset-cache
```

## 脚本说明

| 脚本 | 功能 |
|:---|:---|
| `build.sh` | 构建 `devenv:latest` 镜像。默认 `--no-cache --pull` 全新构建；`--use-cache` 供调试用 |
| `export.sh` | 将 `devenv:latest` 导出为带真实架构标签和时间戳的 `.tar` 包 |
| `import.sh` | 加载 `.tar`（可选）→ 同步 vcpkg 缓存 → 挂载持久化卷 → 启动容器 |

`import.sh` 完整用法：

```bash
# 本地镜像存在 → 挂载默认 ~/workspace 启动；否则报错
./import.sh

# 本地镜像存在 → 挂载指定目录启动；否则报错
./import.sh /path/to/code

# 加载 tar → 挂载默认 ~/workspace 启动
./import.sh myimage.tar

# 加载 tar → 挂载指定目录启动
./import.sh myimage.tar /path/to/code

# 跳过架构一致性检查（QEMU 模拟，明显变慢）
./import.sh --allow-arch-mismatch [...]

# 启动前清空全部持久化缓存卷
./import.sh --reset-cache [...]
```

> **默认挂载行为**：宿主机 `~/workspace` 直接对应容器内 `~/workspace`（一一对应，不嵌套子目录）；
> 若指定自定义目录，则以子目录形式挂载到容器内 `~/workspace/<目录名>` 下。
> 若指定了 `.tar`，会强制删除旧容器与本地同名镜像后重新加载，缓存卷不受影响。

## 升级 Debian 版本

将来 Debian 14（forky）发布并被 devcontainers 官方支持后，只需修改一处：

```dockerfile
# Dockerfile 顶部从 debian13 改为 debian14
ARG VARIANT=debian14
```

或者在构建时通过参数临时指定，不修改文件：

```bash
DOCKER_BUILDKIT=1 docker build --build-arg VARIANT=debian14 ...
```

随后重新跑一次 `./build.sh`，验证 apt 包名是否有变化即可。无需追踪 Microsoft cpp 变体的策展逻辑是否同步更新——这是选用 `base` 而非 `cpp` 作为主阶段基座的核心收益。

## 设计原则

1. **默认拿构建那一刻的最新版本，不做隐式版本锁定**
   系统包依赖 `--no-cache --pull` 强制刷新；vcpkg baseline 每次构建动态生成；`uv tool install`/`npm i -g` 均不锁定版本号。
   调试时可用 `--use-cache` 临时走缓存，但正式使用前应重新跑一次默认构建校准版本。

2. **架构假设显式化、快速失败**
   `build.sh`、Dockerfile 内独立的 `arch-check` stage、`import.sh` 三处均做了架构检测，遇到不支持的场景会在最早的环节报错并给出清晰提示，不会绕一大圈才在深处失败。

3. **所有依赖显式声明，无隐式继承**
   主阶段基于 `devcontainers/base` 而非 `devcontainers/cpp`，原本由 cpp 变体隐式提供的编译工具链（`build-essential`/`gdb`/`cppcheck`/`valgrind`）和 vcpkg 本体，全部在 Dockerfile 中显式声明，依赖关系一目了然，不受上游策展决策变动影响。

4. **BuildKit cache mount 与镜像层严格区分**
   只有"加速重复构建"的内容（vcpkg 源码下载缓存 `downloads/`）才使用`--mount=type=cache`；真正需要交付给运行时容器的内容（vcpkg 编译产物 `archives/`）必须写进普通镜像层，否则会出现"构建期成功，最终容器里什么都没有"的隐蔽问题。

5. **缓存独立于镜像生命周期**
   运行时缓存全部使用 Docker 具名卷持久化，与 `docker build`/`docker rmi` 解耦，配合镜像内构建期缓存的增量同步逻辑，实现"镜像随便重建，开发环境无缝续用"。

6. **权限干净，幂等可重复**
   非 root 用户（`vscode`，UID 1000）拥有全部缓存目录与工作区的读写权限；`import.sh` 在容器启动后统一校正一次权限，规避具名卷首次挂载时可能出现的归属问题；所有脚本可多次执行，不因路径已存在或资源已创建而失败。

## 故障排查

#### `libudev-dev:arm64` 找不到包

需要在 `apt-get update` 之前启用 arm64 multiarch：`dpkg --add-architecture arm64` 已包含在当前 Dockerfile 中，若自行修改过基础包安装逻辑，需确保这行出现在对应 `apt-get update` 之前。

#### 构建 `libusb:arm64-linux` 时 `configure` 阶段报找不到 `libudev`

交叉编译时找不到 arm64 架构的 `libudev.so`，需同时安装 `libudev-dev` 与`libudev-dev:arm64`，两者均已包含在当前 Dockerfile 包列表中。

#### 构建 vcpkg 依赖时报 `vcpkg was cloned as a shallow repository`

当前 Dockerfile 显式使用 `git clone --depth 1`（浅克隆），`build-vcpkg-deps.sh`脚本包含自动检测并 `fetch --unshallow` 的逻辑，会自动处理。若自行修改了刷新逻辑，需确认这一步没有被去掉。

#### `vcpkg list` 在容器里查不到任何已安装的包

manifest 模式下，`vcpkg list` 需要在存在 `vcpkg.json` 的目录下执行：

```bash
cd /home/vscode/.vcpkg-manifest && vcpkg list

# 或者直接查看产物目录
ls /home/vscode/.vcpkg-manifest/vcpkg_installed/arm64-linux/lib/
ls /home/vscode/.vcpkg-manifest/vcpkg_installed/x64-linux/lib/
```

#### 容器内 `/home/vscode/.cache/vcpkg/archives` 为空或不存在

检查 Dockerfile 里 `--mount=type=cache` 的 `target` 是否**只**指向`/home/vscode/.cache/vcpkg/downloads`，而不是整个`/home/vscode/.cache/vcpkg`。
若后者被 cache mount 覆盖，`archives/` 的内容只存在于 BuildKit 构建缓存，不会出现在最终镜像里。

#### `import.sh` 报错"镜像架构与宿主机架构不一致"

确认这是预期场景后可加 `--allow-arch-mismatch` 强制通过 QEMU 模拟运行，但性能损失明显，长期使用建议在与镜像架构一致的 `amd64` 机器上运行。

#### 构建时外网资源（`ghcr.io`/`apt.llvm.org` 等）拉取超时

配置 Docker registry mirror，编辑 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://registry.docker-cn.com"
  ]
}
```

然后 `sudo systemctl restart docker`。

#### 挂载工作区目录后 `Permission denied`

```bash
sudo chown -R 1000:1000 /path/to/your/code
```

容器内 `vscode` 用户的 UID/GID 均为 1000。

## 已知限制

- 无法在 `arm64` 宿主机上原生构建镜像；如需支持，需补充反方向的交叉编译工具链配置
- 默认策略是每次构建都追新，vcpkg 全量编译耗时较长（Boost/Abseil/Drogon 等重量级依赖），不适合频繁触发正式构建；调试阶段用 `--use-cache`，正式发布用默认无缓存构建
- 具名卷内容不随 `.tar` 导出/导入迁移，跨机器分发时只有镜像携带的初始缓存会被带过去
- GCC/GDB 维持 Debian 13 stock 版本（约 GCC 14 / GDB 15），未追新到 GCC 15 / GDB 17（源码编译耗时与体积代价过高，详见「工具链清单」注释）

## 文件结构

```text
DevBox/
├── build.sh                    # 构建镜像
├── export.sh                   # 导出镜像为 .tar 包
├── import.sh                   # 加载镜像并启动容器
└── .devcontainer/
    ├── Dockerfile              # 镜像构建定义
    ├── vcpkg.json.in           # vcpkg 依赖声明模板（不含 builtin-baseline）
    ├── devcontainer.json       # VS Code Dev Containers 配置
    └── .format/                # 个人工具格式化配置文件
        ├── .vimrc
        ├── .clang-format
        └── ...
```

## 许可与致谢

基于 [Microsoft devcontainers/base-debian](https://github.com/devcontainers/images/tree/main/src/base-debian)官方模板，针对"多架构预编译 + 离线部署 + 缓存持久化"场景做了扩展与改造。