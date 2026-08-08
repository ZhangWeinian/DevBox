#!/usr/bin/env bash

# 用途：为当前工作区补齐【只能通过目录树向上查找生效】的配置文件
# 目前仅 .clang-format 需要如此处理 —— clang-format 的 "file" 查找模式只支持从被格式化文件所在目录开始向上逐级查找，不支持指定绝对路径
# 其余配置文件（prettier/ruff/cmake-format）均已在 VS Code 设置中直接指向 ~/.format/xxx 的绝对路径，无需在此处理

set -euo pipefail

SRC_DIR="/home/vscode/.format"
TARGET_DIR="${1:-$PWD}"

NEED_LINK_IN_PROJECT=(
    ".clang-format"
)

echo "==> 检查必须存在于项目目录中的配置文件（目标: ${TARGET_DIR}）"
for f in "${NEED_LINK_IN_PROJECT[@]}"; do
    if [ -e "${TARGET_DIR}/${f}" ]; then
        echo "    已存在，跳过: ${f}"
    elif [ -e "${SRC_DIR}/${f}" ]; then
        ln -s "${SRC_DIR}/${f}" "${TARGET_DIR}/${f}"
        echo "    已链接: ${f}"
    fi
done
