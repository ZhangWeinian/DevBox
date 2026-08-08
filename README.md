# 通用 `C++`/`Python` 多架构开发容器

一个自用的、包含最新工具链、支持 `x86-64`/`arm64` 离线使用的 `Docker` 开发环境模板。

## 特性

- **多架构支持**：镜像可在 `amd64`  和 `arm64` 主机上分别构建，导出后直接用于同架构离线设备
- **工具链完整**：`C++` (`CMake`/`Ninja`/`Boost`/`GCC`)、`Python` (`uv`/`pip`)、`Java 21`、`Node.js LTS`、`vcpkg`、`clang‑format`、`cmake‑format` 等
- **编译加速**：集成 `ccache` 和 `ninja`，并支持 `vcpkg` 二进制缓存（通过挂载宿主机目录）
- **离线友好**：构建时一次拉齐所有工具链，`docker save` 导出静态镜像，离线设备无需网络即可编译
- **缓存共享**：所有项目共享同一套宿主机缓存目录（`~/.devcontainer-caches/`），避免重复下载

## 快速开始

### 前置要求

- `Docker 29.0+` 或更新版本
- `Linux`/`WSL2` 环境（`macOS` 用户需确保 `Docker Desktop` 的 `BuildKit` 支持）
- 可选：`docker-buildx` 插件用于多平台验证

```bash
# Ubuntu/Debian
sudo apt update
sudo apt-get install -y docker-buildx
```

### 基础镜像构建

```bash
git clone <此仓库>
cd DevBox
chmod +x build.sh export.sh import.sh
./build.sh
```

### 导出静态镜像包

```bash
./export.sh
```

> 这会在当前目录生成 `devenv-YYYYMMDD_HHMMSS.tar` 文件，包含了完整的工具链和预安装的库（需在 `Dockerfile` 中提前添加）

### 在离线设备上导入并启动

将 `.tar` 包拷贝到目标设备，然后：

```bash
# 加载镜像并启动容器（无挂载）
./import.sh devenv-YYYYMMDD_HHMMSS.tar

# 或者加载后挂载本地代码目录
./import.sh devenv-YYYYMMDD_HHMMSS.tar /path/to/your/project
```

### 日常开发（用 `VS Code`）

1. 启动容器后，打开 `VS Code`，按 `F1` → “开发容器: 附加到正在运行的容器”
2. 选择容器 `dev-container`，即可开始开发
3. 本地目录后所有修改保存在宿主机挂载的目录中，容器重建不会丢失

### 工具链清单

| 工具         | 版本            | 来源                           |
| :----------- | :-------------- | :----------------------------- |
| GCC/G++      | Debian 13 stock | apt                            |
| CMake        | 构建时最新      | uv tool install cmake          |
| Ninja        | 构建时最新      | uv tool install ninja          |
| Boost        | Debian 13 stock | apt                            |
| Java         | 21 LTS          | Microsoft OpenJDK (distroless) |
| Python       | uv 最新         | uv python install              |
| uv           | 构建时最新      | GitHub Container Registry      |
| Node.js      | 构建时最新 LTS  | docker.io/library/node         |
| npm/corepack | 构建时最新      | Node.js 标准库                 |
| vcpkg        | 构建时最新      | Microsoft 官方（git pull）     |
| ccache       | Debian 13 stock | apt                            |
| git          | 构建时最新      | Features                       |
| clang-format | 构建时最新      | LLVM 官方 apt.llvm.org         |
| cmake-format | 构建时最新      | uv tool install cmakelang      |

### 缓存目录映射

所有缓存以 `bind mount` 形式挂载到  `$HOME/.devcontainer-caches/` ，项目共享：

```text
~/.devcontainer-caches/
├── vcpkg/
│   ├── downloads/       # vcpkg 源码包
│   └── archives/        # vcpkg 二进制缓存
├── ccache/              # C/C++ 编译缓存
├── uv/                  # uv 包缓存
├── pip/                 # pip 缓存（备用）
├── npm/                 # npm 模块
├── pnpm-store/          # pnpm 全局存储
├── yarn/                # yarn 缓存
├── m2/                  # Maven 仓库
├── gradle/              # Gradle 缓存
└── vscode-server/       # VS Code Server 离线部署
```

> 这些目录在首次使用容器时由 `initializeCommand` 自动创建并赋予 `vscode` 用户写权限

### 脚本说明

| 脚本        | 功能                                            |
| :---------- | :---------------------------------------------- |
| `build.sh`  | 使用 `Dockerfile` 构建 `devenv:latest` 镜像     |
| `export.sh` | 将 `devenv:latest` 导出为带时间戳的 `.tar` 包   |
| `import.sh` | 加载 `.tar` 并启动容器（支持无挂载 / 挂载目录） |

`import.sh` 详细用法：

```bash
./import.sh                           # 本地镜像存在 → 启动无挂载容器；否则报错
./import.sh /path/to/code             # 本地镜像存在 → 启动容器并挂载目录；否则报错
./import.sh myimage.tar               # 加载 tar → 启动无挂载容器
./import.sh myimage.tar /path/to/code # 加载 tar → 启动容器并挂载目录
```

> 若指定了 `tar`，则强制覆盖本地同名镜像，并删除旧容器重新创建

### 设计原则

1. **多架构天然兼容**：全部通过官方多阶段 `COPY --from=<image>` 或官方 `wheel`，不写任何手动架构判断脚本
2. **离线第一**：所有工具链在构建时一次拉取，镜像本身完全冻结，导出后不再依赖网络
3. **缓存共享全局**：所有项目共享同一套缓存目录，节省磁盘和时间
4. **权限干净**：非 `root` 用户（`vscode`）拥有全部缓存目录的读写权限，无需 `sudo`
5. **幂等可重复**：脚本可多次执行，不会因路径已存在/权限冲突而失败

### 故障排查

#### 构建时 `ghcr.io` 拉取超时

国内网络可能需要配置 `Docker registry mirror` 。编辑 `/etc/docker/daemon.json` ：

```bash
{
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://registry.docker-cn.com"
    ]
}
```

然后 

```bash
sudo systemctl restart docker 
```

#### 离线设备 `docker load` 后容器内仍报网络错误

- 检查镜像内是否已包含需要的 `Python` 包：`docker run --rm devenv:latest pip list`
- 如果为空，说明导出时该缓存还没积累内容，需要在源设备上提前跑一次 `uv sync` 或 `pip install` 来填充缓存。
- 如使用 `vcpkg`，确保项目 `vcpkg.json` 中的 `builtin-baseline` 锁定到某个固定 `commit`，避免离线时 `vcpkg` 尝试更新注册表。

#### 容器启动后 `python` 或 `cmake` 找不到

- 确认你以 `vscode` 用户进入容器，且镜像中的软链接指向正确路径
- 在 `Dockerfile` 中所有工具安装后，务必执行 `USER vscode` 切换用户，并确保 `/usr/local/bin` 在 `PATH` 中（已默认设置）

#### 挂载目录后权限报错（`Permission denied`）

- 在宿主机上调整目录权限：

```bash
sudo chown -R 1000:1000 /path/to/your/code #容器内 vscode 用户 UID=1000
```

- 或在启动时使用 `docker run -u $(id -u):$(id -g)` 以宿主机当前用户运行容器（需镜像支持）。

### 许可与致谢

基于 [`Microsoft devcontainers`/`cpp`](https://github.com/devcontainers/images/tree/main/src/cpp) 官方模板，针对离线+多架构场景优化。
