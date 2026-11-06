#!/bin/sh
# scripts/macos-brew-packages.sh — macOS 的 Homebrew 软件包（D-036，lib/stage.sh 在 mise bootstrap 之后调用）
#
# aqua 中没有可用的 macOS 版本的工具改由 Homebrew 安装：
#   eza：没有 macOS 的二进制发布，aqua 注册表要求 cargo 编译；delta：aqua 注册表不支持 Intel Mac。
# 不用 mise 的 [bootstrap.packages] "brew:…"：它只支持 Apple 芯片，Intel Mac 上会直接跳过（P-053）。
# Homebrew 的镜像变量（HOMEBREW_BOTTLE_DOMAIN 等）由调用方导出（lib/macos.sh 的 bs_brew_env）。
set -eu
pkgs=${BOOTSTRAP_BREW_PACKAGES:-eza git-delta}
command -v brew >/dev/null 2>&1 || {
  echo "macos-brew-packages: 没有 brew，跳过（${pkgs}）" >&2
  exit 0
}
rc=0
for p in $pkgs; do
  brew list --formula --versions "$p" >/dev/null 2>&1 && continue
  printf '\033[1;34m==>\033[0m brew install %s\n' "$p" >&2
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --quiet "$p" || {
    echo "WARNING: brew install $p 失败" >&2
    rc=1
  }
done
exit "$rc"
