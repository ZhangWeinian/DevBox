# 通用 C++/Python 多架构开发容器

一个自用的、包含最新工具链、可离线部署的 Docker 开发环境模板。基于 `mcr.microsoft.com/devcontainers/cpp:3-debian13` 官方镜像扩展，单次构建同时产出针对 `x64-linux` 和 `arm64-linux` 两个目标平台的预编译库，供后续项目直接链接使用。

## 特性

- **构建时刻即最新**：系统包、编译器工具链（CMake/Ninja/ruff 等）、vcpkg 依赖版本，默认每次构建都重新拉取当前最新版本，不锁定历史版本号（详见「设计原则」）
- **交叉编译双目标**：单次构建在 `amd64` 宿主机上，同时产出 `x64-linux` 与 `arm64-linux` 两套 vcpkg 预编译库，供不同目标架构的项目复用
- **工具链完整**：`C++`（CMake/Ninja/Boost/GCC）、`Python`（uv）、`.NET 10`、`Java 21`、`Node.js LTS`、`vcpkg`、`clang-format`、`cmake-format` 等
- **编译加速**：集成 `ccache` 与 `ninja`，并通过 vcpkg 二进制缓存（具名卷持久化）避免重复编译第三方库
- **离线友好**：构建时一次拉齐所有工具链，`docker save` 导出静态镜像，离线设备无需网络即可编译
- **缓存独立于镜像生命周期**：所有下载/编译缓存以 Docker 具名卷形式持久化，重新构建镜像不会导致缓存清零

## 快速开始

### 前置要求

- **仅支持在 `x86_64`（amd64）宿主机上构建镜像**（见下方「架构支持范围」说明），需要 Docker 具备 BuildKit 能力（现代 Docker 版本默认已启用）
- `Linux`/`WSL2` 环境；`Windows` 用户强烈建议在 `WSL2` 文件系统内操作（而非 Windows 原生路径挂载），否则容器内文件 I/O 性能会明显下降
- `macOS`（Apple Silicon）用户注意：本机是 `arm64` 架构，无法直接构建，仅能作为**离线运行方使用他人构建好的 amd64 镜像**（需 Docker Desktop 内置 QEMU 支持，性能会有明显损失）

```bash
git clone <此仓库>
cd DevBox/.devcontainer
chmod +x build.sh export.sh import.sh
```

### 基础镜像构建

```bash
# 默认：完全重新构建（--no-cache --pull），保证一切都是构建这一刻的最新版本
./build.sh

# 调试 Dockerfile 时使用：吃 Docker 层缓存，加速迭代，但不保证最新
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

会生成 `devenv-<架构>-<日期_时间>.tar`（例如 `devenv-amd64-20260810_223000.tar`），架构标签取自镜像自身元数据（`docker image inspect --format '{{.Architecture}}'`），而非导出这台机器的宿主机架构，保证标签始终真实。

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
1. 校验镜像架构与当前宿主机架构是否一致（不一致默认拒绝启动，见下方说明）；
2. 挂载全部持久化缓存卷（vcpkg/uv/npm/.vscode-server 等，见「缓存卷与持久化」）；
3. 把镜像内构建期烘焙好的 vcpkg 二进制缓存增量同步进持久化卷；
4. 启动容器并修正缓存目录权限。

### 日常开发（用 VS Code）

1. 启动容器后，打开 VS Code，按 `F1` → "开发容器: 附加到正在运行的容器"
2. 选择容器 `dev-container`，即可开始开发
3. 项目代码通过 bind mount 挂载，保存在宿主机目录中，容器重建（`import.sh` 重新拉起）不会丢失代码

## 架构支持范围（重要，与早期版本说明不同）

这个模板**目前只支持在 `amd64`（x86_64）宿主机上构建**，产出的镜像本身也是 `amd64` 架构。原因是 Dockerfile 里的交叉编译工具链（`gcc-aarch64-linux-gnu` 等）和 vcpkg triplet 配置，都是按"amd64 宿主机 → 交叉编译出 arm64 目标库"这个单向假设硬编码的：

- **构建**：只能在 `amd64` 机器上跑 `./build.sh`，非 `amd64` 机器会被脚本提前拦截报错；
- **产出**：一次构建会在容器内同时生成 `vcpkg_installed/x64-linux/`（原生编译）和 `vcpkg_installed/arm64-linux/`（交叉编译）两套预编译库的二进制缓存，方便你自己的项目无论目标是哪个平台，都能命中缓存直接复用，不需要重新从源码编译；
- **运行**：容器镜像本身只能原生运行在 `amd64` 宿主机上。`import.sh` 会检测宿主机架构，若与镜像架构不一致会拒绝启动，可加 `--allow-arch-mismatch` 强制通过 QEMU 模拟运行（速度会明显变慢，仅建议临时应急使用）。

如果需要"在 arm64 宿主机上原生构建"这个能力，需要额外补一套反方向的交叉编译工具链配置，当前版本尚未支持。

## 工具链清单

| 工具 | 版本 | 来源 |
| :--- | :--- | :--- |
| GCC/G++ | Debian 13 stock（约 14.x） | apt |
| GDB | Debian 13 stock（约 15.x） | apt |
| CMake | 构建时最新 | `uv tool install cmake` |
| Ninja | 构建时最新 | `uv tool install ninja` |
| cmake-format（cmakelang） | 构建时最新 | `uv tool install cmakelang` |
| ruff | 构建时最新 | `uv tool install ruff` |
| Python | uv 托管的最新版本 | `uv python install` |
| uv / uvx | 构建时最新 | `ghcr.io/astral-sh/uv:latest` |
| .NET SDK | 10.0 LTS | `packages.microsoft.com` apt 源 |
| Java | 21 LTS（仅用于运行第三方 Java 工具链，非本环境核心） | Microsoft OpenJDK（distroless） |
| Node.js | 构建时最新 LTS | `docker.io/library/node:lts` |
| npm / corepack | 随 Node.js 附带 | Node.js 官方发行 |
| codegraph | 构建时最新 | npm 全局安装 |
| vcpkg | 构建时最新（每次构建动态 `git fetch` 到默认分支 HEAD） | Microsoft 官方仓库 |
| ccache | Debian 13 stock | apt |
| clang-format | 构建时最新 major 版本（动态查询 GitHub Release） | LLVM 官方 `apt.llvm.org` |
| Boost | Debian 13 stock（系统级） + vcpkg 最新（manifest，见下文） | apt / vcpkg |
| git | 基础镜像自带 | `mcr.microsoft.com/devcontainers/cpp` |

> GCC/GDB 目前维持 Debian 13 官方仓库自带版本，未采用源码编译追新（曾评估过，编译耗时与镜像体积代价过高，性价比不足，详见项目讨论记录）。如需更新的编译器特性，可考虑另行通过 LLVM apt 源安装最新 Clang 作为备选工具链。

## vcpkg 依赖清单

依赖声明维护在 `vcpkg.json.in`（**不含** `builtin-baseline` 字段）：

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
    "oatpp-curl",
  ]
}
```

构建时，Dockerfile 内的脚本会：
1. 把 `$VCPKG_ROOT` 刷新（`fetch + reset --hard`）到当前默认分支最新 commit，并自动检测/修复浅克隆（`--unshallow`），避免解析历史版本 port 时因缺少完整 git 历史而失败；
2. 用刷新后的 `HEAD` commit sha 作为 `builtin-baseline`，动态拼装出最终的 `vcpkg.json`（写入 `/home/vscode/.vcpkg-manifest/vcpkg.json`）；
3. 分别针对 `x64-linux` 与 `arm64-linux` 两个 triplet 执行 `vcpkg install`，产出的二进制缓存写入 `/home/vscode/.cache/vcpkg/archives`（**会**提交进镜像层，与 `downloads/` 不同，后者仅作为 BuildKit 构建期缓存，不进最终镜像）。

如需增删依赖，直接编辑 `vcpkg.json.in` 的 `dependencies` 数组，无需手动处理 `builtin-baseline`（每次构建都会重新生成）。

## 缓存卷与持久化

**与早期版本不同**，当前实现**不再使用 bind mount 到 `~/.devcontainer-caches/`**，而是改用 Docker **具名卷**（named volume），由 `import.sh` 统一管理挂载：

| 卷名 | 容器内路径 | 用途 |
| :--- | :--- | :--- |
| `devenv-cache-vcpkg` | `/home/vscode/.cache/vcpkg` | vcpkg 源码下载 + 二进制缓存 |
| `devenv-cache-uv` | `/home/vscode/.cache/uv` | uv 包缓存 |
| `devenv-cache-pip` | `/home/vscode/.cache/pip` | pip 缓存（备用） |
| `devenv-cache-ccache` | `/home/vscode/.cache/ccache` | C/C++ 编译缓存 |
| `devenv-cache-npm` | `/home/vscode/.npm` | npm 缓存 |
| `devenv-cache-yarn` | `/home/vscode/.cache/yarn` | yarn 缓存 |
| `devenv-cache-pnpm-store` | `/home/vscode/.local/share/pnpm/store` | pnpm 全局存储 |
| `devenv-cache-m2` | `/home/vscode/.m2` | Maven 仓库 |
| `devenv-cache-gradle` | `/home/vscode/.gradle` | Gradle 缓存 |
| `devenv-cache-vscode-server` | `/home/vscode/.vscode-server` | VS Code Server（避免每次重连重新下载/安装扩展） |

**选用具名卷而非 bind mount 的原因**：具名卷独立于 image tag 存在，重新 `build` 出新镜像、`import` 启动新容器时，只要卷名不变就会自动复用旧卷内容——实现"镜像随便重新构建，开发缓存持续累积、无缝续用"的效果，同时规避 bind mount 在 Windows 非 WSL2 路径下常见的性能与权限问题。

**注意**：具名卷的内容不会被 `docker save`/`export.sh` 打包进 `.tar`，只存在于当前宿主机的 Docker Engine 里。跨机器分发的是镜像本身（工具链 + 构建期烘焙好的 vcpkg 缓存初始内容），持久化卷里后续累积的内容（比如你在容器里手动装的新依赖）不会跟着 `.tar` 走。

如需清空某个/全部缓存卷（例如怀疑缓存损坏，或某工具版本发生不兼容的重大升级）：

```bash
# 精确清空某一个
docker volume rm devenv-cache-<后缀>

# 清空全部后重新启动
./import.sh --reset-cache
```

## 脚本说明

| 脚本 | 功能 |
| :--- | :--- |
| `build.sh` | 构建 `devenv:latest` 镜像。默认 `--no-cache --pull` 全新构建；`--use-cache` 调试用，走 Docker 层缓存 |
| `export.sh` | 将 `devenv:latest` 导出为带真实架构标签、带时间戳的 `.tar` 包 |
| `import.sh` | 加载 `.tar`（可选）→ 挂载持久化缓存卷 → 同步镜像内 vcpkg 缓存 → 启动容器 |

`import.sh` 详细用法：

```bash
# 本地镜像存在 → 挂载默认目录 ~/workspace 启动；否则报错
./import.sh

# 本地镜像存在 → 挂载指定目录启动；否则报错
./import.sh /path/to/code

# 加载 tar → 挂载默认目录启动
./import.sh myimage.tar

# 加载 tar → 挂载指定目录启动
./import.sh myimage.tar /path/to/code

# 跳过镜像/宿主机架构一致性检查（依赖 QEMU 模拟，明显变慢）
./import.sh --allow-arch-mismatch [...]

# 启动前清空全部持久化缓存卷
./import.sh --reset-cache [...]
```

> 默认挂载目录为宿主机 `~/workspace`，对应容器内 `~/workspace`（一一对应，不嵌套子目录）；若指定自定义目录，则以子目录形式挂载到容器内 `~/workspace/<目录名>` 下。
> 若指定了 `.tar`，会强制删除旧容器与本地同名镜像后重新加载，缓存卷不受影响。

## 设计原则

1. **默认拿构建那一刻的最新版本，不做隐式版本锁定**：系统包依赖 `--no-cache --pull` 强制刷新；vcpkg baseline 每次构建动态生成而非写死提交；`uv tool install`/`npm i -g` 均不锁定版本号。调试 Dockerfile 时可用 `--use-cache` 临时走缓存加速迭代，但正式使用前应重新跑一次不带参数的默认构建校准版本。
2. **架构假设显式化、快速失败**：`build.sh`/Dockerfile 顶部/`import.sh` 三处都做了架构一致性检测，遇到不支持的场景会在最早的环节报错并给出清晰提示，而不是绕一大圈之后在 vcpkg 编译或容器启动阶段才失败。
3. **BuildKit 缓存 mount 与镜像层严格区分**：只有确实只服务于"加速重复构建"的内容（如 vcpkg 源码下载缓存）才使用 `--mount=type=cache`；真正需要交付给运行时容器使用的内容（如 vcpkg 编译产物/二进制缓存）必须写进普通的、会被提交的镜像层，否则会出现"构建期看起来成功，但最终镜像/容器里什么都没有"的隐蔽问题。
4. **缓存独立于镜像生命周期**：运行时缓存全部使用 Docker 具名卷持久化，与 `docker build`/`docker rmi` 解耦，配合镜像内构建期缓存的增量同步逻辑，实现"镜像随便重建，开发环境无缝续用"。
5. **权限干净**：非 root 用户（`vscode`，UID 1000）拥有全部缓存目录与工作区的读写权限；`import.sh` 会在容器启动后统一校正一次缓存目录权限，规避具名卷首次挂载时可能出现的权限归属问题。
6. **幂等可重复**：脚本可多次执行，不会因路径已存在/资源已创建而失败。

## 故障排查

#### 构建时提示 `libudev-dev:arm64` 找不到包

需要先启用 arm64 multiarch 支持才能安装对应架构的开发库：

```dockerfile
RUN dpkg --add-architecture arm64 && apt-get update && ...
```

（当前 Dockerfile 已包含此修复，若自行修改过基础包安装逻辑需注意保留这一行，且必须出现在对应 `apt-get update` 之前。）

#### 构建 `libusb:arm64-linux` 时 `configure` 阶段报错，提示缺少 `libudev`

同上，本质是交叉编译时找不到 arm64 架构的 `libudev.so`，需要同时安装 `libudev-dev` 与 `libudev-dev:arm64`。

#### 构建 vcpkg 依赖时报错 `vcpkg was cloned as a shallow repository`

基础镜像自带的 `$VCPKG_ROOT` 通常是浅克隆，只有普通 `git fetch` 不会补全历史。当前脚本已包含自动检测并 `fetch --unshallow` 的逻辑；若自行修改过刷新逻辑，需确认这一步没有被去掉。

#### `vcpkg list` 在容器里查不到任何已安装的包

`vcpkg list` 只在当前目录存在 `vcpkg.json`（manifest 上下文）或使用默认 `$VCPKG_ROOT/installed` 时才能查到内容。本项目构建时用了 `--x-install-root` 指定了自定义安装目录，需要 `cd /home/vscode/.vcpkg-manifest && vcpkg list`，或者直接 `ls /home/vscode/.vcpkg-manifest/vcpkg_installed/<triplet>/lib/` 查看实际产物。

#### 容器内 `/home/vscode/.cache/vcpkg/archives` 是空的或不存在

检查 Dockerfile 里 `--mount=type=cache` 的 `target` 是否精确指向了 `.../vcpkg/downloads`（只覆盖下载缓存），而不是整个 `.../vcpkg` 目录——后者会导致 `archives/`（真正需要交付的二进制缓存）也被 cache mount 吞掉，永远不会出现在最终镜像里。

#### `import.sh` 报错"镜像架构与宿主机架构不一致"

说明当前宿主机架构和镜像架构不匹配（例如尝试在 arm64 Mac 上运行 amd64 镜像）。确认这是预期场景后可加 `--allow-arch-mismatch` 强制通过 QEMU 模拟运行，但会有明显的性能损失，仅建议临时应急使用，长期使用建议在与镜像架构一致的机器上运行。

#### 构建时 `ghcr.io`/`apt.llvm.org` 等外网资源拉取超时

国内网络可能需要配置 Docker registry mirror。编辑 `/etc/docker/daemon.json`：

```json
{
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://registry.docker-cn.com"
    ]
}
```

然后 `sudo systemctl restart docker`。

#### 挂载工作区目录后权限报错（Permission denied）

调整宿主机目录属主为容器内 `vscode` 用户对应的 UID/GID（默认均为 1000）：

```bash
sudo chown -R 1000:1000 /path/to/your/code
```

## 已知限制

- 无法在 `arm64` 宿主机上原生构建镜像（见「架构支持范围」）；如需支持，需额外补充反方向的交叉编译工具链配置
- 默认策略是"每次构建都追新"，代价是构建耗时较长（尤其 Boost/Abseil/Drogon 等重量级依赖全量编译），不适合频繁触发正式构建的场景，建议仅在需要时手动触发，调试阶段用 `--use-cache`
- 具名卷内容不随 `.tar` 导出/导入迁移，仅在同一宿主机上"镜像重建、缓存续用"的场景下生效；跨机器分发时只有镜像本身携带的初始缓存内容会被带过去
- GCC/GDB 未追新到最新大版本，维持 Debian 13 stock 版本（详见「工具链清单」注释）

## 许可与致谢

基于 [Microsoft devcontainers/cpp](https://github.com/devcontainers/images/tree/main/src/cpp) 官方模板，针对"多架构预编译 + 离线部署 + 缓存持久化"场景做了扩展与改造。