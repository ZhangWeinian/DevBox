# 通用 C++/Python 多架构开发容器

一个自用的、包含最新工具链、支持 x86-64/arm64 离线使用的 Docker 开发环境模板。

## 特性

- **多架构支持**：自动适配 amd64/arm64，无需手动架构判断
- **工具链完整**：C++ (CMake/Ninja/Boost/GCC)、Python (uv/pip)、Java 21、Node.js LTS、vcpkg
- **编译加速**：集成 ccache 和 ninja，可选 vcpkg 二进制缓存
- **离线友好**：在有网设备构建一次，全部工具链缓存被持久化到宿主机，可导出静态镜像到离线设备运行
- **缓存共享**：所有项目共享全局工具缓存目录，节省空间和重复下载

## 快速开始

### 前置要求

- Docker 29.0+ 或更新版本
- Linux/WSL2 环境（macOS 用户需确保 Docker Desktop 的 BuildKit 支持）
- 可选：`docker-buildx` 插件用于多平台验证

```bash
sudo apt-get install -y docker-buildx  # Ubuntu/Debian
```

### 基础镜像构建（一次性）

```bash
mkdir -p .devcontainer
# 将下方 Dockerfile 内容保存到 .devcontainer/Dockerfile

DOCKER_BUILDKIT=1 docker build -t devenv:latest -f .devcontainer/Dockerfile .devcontainer
```

### 日常开发：用  VS Code Remote Containers

1. 在项目根目录创建 .devcontainer/devcontainer.json（见下方文件清单）
2. VS Code 打开项目，安装 "Dev Containers" 扩展
3. Ctrl+Shift+P → Dev Containers: Reopen in Container
4. 首次会执行 initializeCommand 创建缓存目录，后续直接进容器开发

```bash
# 或者纯命令行进容器
docker run -it --rm \
  --mount type=bind,source=$HOME/.devcontainer-caches/vcpkg,target=/home/vscode/.cache/vcpkg \
  devenv:latest bash
```

### 打包导出到离线设备

在有网的对应架构设备上，先正常使用容器一段时间，让缓存自然积累：

```bash
# 工作流：日常 devcontainer 开发，逐步下载库
# 某次想导出时，运行：

chmod +x scripts/freeze-export.sh
bash scripts/freeze-export.sh ~/path/to/your/project [optional-output-name]
```

生成的 tar 包拷到离线设备：

```bash
# 离线设备上
docker load -i my-project-amd64-20250722.tar
docker run -it --rm devenv:freeze-my-project-amd64-20250722 bash

# 代码在 /workspaces/my-project，所有工具和依赖都在镜像内，完全离线可用
```

### 工具链清单

| 工具         | 版本            | 来源                           |
| :----------- | :-------------- | :----------------------------- |
| GCC/G++      | Debian 13 stock | apt                            |
| CMake        | 最新            | PyPI wheel (Kitware)           |
| Ninja        | 最新            | PyPI wheel (Ninja)             |
| Boost        | Debian 13 stock | apt                            |
| Java         | 21 LTS          | Microsoft OpenJDK (distroless) |
| Python       | 3.13            | Debian 13 + Features           |
| uv           | 最新            | GitHub Container Registry      |
| Node.js      | LTS             | docker.io/library/node         |
| npm/corepack | 最新            | Node.js 标准库                 |
| vcpkg        | 最新            | Microsoft 官方（git pull）     |
| ccache       | Debian 13 stock | apt                            |
| git          | 最新            | Features                       |

### 缓存目录映射

所有缓存以 bind mount 形式挂载到  $HOME/.devcontainer-caches/ ，项目共享：

```bash
~/.devcontainer-caches/
├── vcpkg/
│   ├── downloads/  ← 源码包缓存
│   └── archives/   ← 编译二进制缓存
├── ccache/         ← C/C++ 编译缓存
├── uv/             ← Python 包缓存
├── pip/            ← pip 包缓存（备用）
├── npm             ← npm 模块缓存
├── pnpm-store/     ← pnpm global store
├── yarn/           ← yarn 缓存
├── m2/             ← Maven 仓库
├── gradle          ← Gradle 缓存
└── vscode-server/  ← VS Code Server 离线部署
```

### 设计原则

1. **多架构天然兼容**：全部通过官方多阶段 COPY --from=<image> 或官方 wheel，不写任何手动架构判断脚本
2. **离线第一**：所有工具链在构建时一次拉取，镜像本身完全冻结，导出后不再依赖网络
3. **缓存共享全局**：所有项目共享同一套缓存目录，节省磁盘和时间
4. **权限干净**：非 root 用户（vscode）拥有全部缓存目录的读写权限，无需 sudo
5. **幂等可重复**：脚本可多次执行，不会因路径已存在/权限冲突而失败

### 故障排查

#### 构建时 ghcr.io 拉取超时

国内网络可能需要配置 Docker registry mirror 。编辑 /etc/docker/daemon.json ：

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

#### 离线设备 docker load 后容器内仍报网络错误

常是 Python/Node 包的运行时依赖问题。检查缓存是否真的被烘焙进去：

```bash
docker run --rm devenv:freeze-xxx ls -lah /home/vscode/.cache/uv/
```

如果为空，说明导出时该缓存还没积累内容，需要在源设备上提前跑一次 uv sync 或 pip install 来填充缓存。

#### vcpkg 在离线设备失效

确保项目 vcpkg.json 或 CMakePresets.json 中的 builtin-baseline 被锁定为某个固定 commit（而非滚动）。离线模式下 ports 注册表版本和缓存版本必须匹配。

### 许可与致谢

基于 Microsoft devcontainers/cpp 官方模板，针对离线+多架构场景优化。