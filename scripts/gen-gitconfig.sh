#!/bin/sh
# scripts/gen-gitconfig.sh —— 按本机 git 版本生成 ~/.local/state/bootstrap/gitconfig（由 mise.toml 的 [tasks.bootstrap] 调用，P-045）
# dotfiles 的 git/config include 这个文件；放的是只有新版 git 才支持的设置
set -eu
out=${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap/gitconfig
v=$(git --version | awk '{print $3}')
# git ≥ 2.35 才支持 zdiff3
if [ "$(printf '%s\n%s\n' 2.35 "$v" | sort -t. -k1,1n -k2,2n | head -n 1)" = 2.35 ]; then style=zdiff3; else style=diff3; fi
mkdir -p "$(dirname "$out")"
printf '# 由 bootstrap 生成（scripts/gen-gitconfig.sh），git %s\n[merge]\n\tconflictstyle = %s\n' "$v" "$style" >"$out"
