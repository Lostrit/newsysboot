#!/bin/sh
# tests/zsh-startup-check.sh <用户>：以该用户在伪终端中启动交互式 zsh，输出（去掉终端控制序列后）应为空
# 用 script 提供伪终端：没有终端时 fzf / atuin 的 init 会报 can't change option: zle，真实登录不会（P-030）
set -eu
out=$(su - "$1" -c 'script -qc "zsh -i -c exit" /dev/null' </dev/null |
  sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g' | tr -d '\r')
[ -z "$out" ] || { printf '%s\n' "$out" >&2; exit 1; }
