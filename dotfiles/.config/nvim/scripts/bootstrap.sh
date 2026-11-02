#!/bin/sh
# scripts/bootstrap.sh —— 预先安装 nvim 的插件、treesitter 语法解析器、Mason 工具与 blink.cmp 模糊匹配库（按固定版本）
#
# 用法：sh ~/.config/nvim/scripts/bootstrap.sh
#   - 适合写进 Dockerfile 或新机器初始化：一次性同步完成，之后打开 nvim 不再需要联网
#   - 每一步都会校验（scripts/bootstrap.lua）；不齐时只补装缺少的部分，最多尝试 3 次，仍失败则以非零状态码退出
#   - 需要：nvim、git、tree-sitter CLI、C 编译器、node（npm 类工具），以及能访问 GitHub 的网络（代理或 https_proxy）
#
# NVIM_BOOTSTRAP=1 会关闭 LazyVim / Mason 的后台自动安装（lua/plugins/bootstrap.lua、lua/plugins/mason.lua），
# 避免与这里的固定版本安装同时进行。
set -eu

cfg=$(cd "$(dirname "$0")/.." && pwd)
for cmd in nvim git tree-sitter cc; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "bootstrap.sh: 缺少 $cmd" >&2
    exit 1
  }
done

export NVIM_BOOTSTRAP=1
i=1
while :; do
  echo "bootstrap.sh: 第 $i 次"
  if nvim --headless -c "luafile $cfg/scripts/bootstrap.lua"; then
    echo "bootstrap.sh: 完成"
    exit 0
  fi
  [ "$i" -lt 3 ] || break
  i=$((i + 1))
  sleep 5
done
echo "bootstrap.sh: 3 次尝试后仍有未完成的项目" >&2
exit 1
