#!/bin/sh
# lib/macos.sh — macOS 的 stage-0 准备（⚠️ 未在真机测试）
#
#   1. Xcode Command Line Tools（提供 git）：管道模式已在拉取仓库前等待安装完成（bootstrap.sh，P-038）；
#      在已有的检出中直接运行时，缺失则触发安装并退出，装完后重新运行
#   2. Homebrew：经清华大学镜像安装（国内无法稳定访问 GitHub），镜像变量同时写入 env.sh 供以后使用

BS_BREW_MIRROR=${BS_BREW_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn}

bs_brew_env() {
  export HOMEBREW_INSTALL_FROM_API=1
  export HOMEBREW_API_DOMAIN="$BS_BREW_MIRROR/homebrew-bottles/api"
  export HOMEBREW_BOTTLE_DOMAIN="$BS_BREW_MIRROR/homebrew-bottles"
  export HOMEBREW_BREW_GIT_REMOTE="$BS_BREW_MIRROR/git/homebrew/brew.git"
  export HOMEBREW_CORE_GIT_REMOTE="$BS_BREW_MIRROR/git/homebrew/homebrew-core.git"
}

bs_brew_prefix() {
  [ "$(uname -m)" = arm64 ] && echo /opt/homebrew || echo /usr/local
}

bs_macos_prepare() {
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install >/dev/null 2>&1 || true
    bs_die "正在安装 Xcode Command Line Tools（提供 git），安装完成后请重新运行本脚本"
  fi
  bs_brew_env
  _bp=$(bs_brew_prefix)
  if [ ! -x "$_bp/bin/brew" ]; then
    bs_log "安装 Homebrew（镜像：${BS_BREW_MIRROR}）"
    _t=$(mktemp -d)
    git clone -q --depth 1 "$BS_BREW_MIRROR/git/homebrew/install.git" "$_t/install"
    /bin/bash "$_t/install/install.sh"
    rm -rf "$_t"
  fi
  eval "$("$_bp/bin/brew" shellenv)"
}

# 写入 env.sh 的 Homebrew 变量
bs_macos_env_lines() {
  bs_brew_env
  for _v in HOMEBREW_INSTALL_FROM_API HOMEBREW_API_DOMAIN HOMEBREW_BOTTLE_DOMAIN HOMEBREW_BREW_GIT_REMOTE HOMEBREW_CORE_GIT_REMOTE; do
    eval "bs_env_line $_v \"\$$_v\""
  done
  echo "eval \"\$($(bs_brew_prefix)/bin/brew shellenv)\""
}
