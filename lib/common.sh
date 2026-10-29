#!/bin/sh
# lib/common.sh — stage-0 公共函数（POSIX sh）

bs_log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
bs_warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
bs_die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

bs_have() { command -v "$1" >/dev/null 2>&1; }

# 以 root 执行：已是 root 直接执行，否则通过 sudo
bs_root() {
  if [ "$(id -u)" = 0 ]; then
    "$@"
  elif bs_have sudo; then
    sudo "$@"
  else
    bs_die "需要 root 权限执行：$*（当前用户不是 root，且没有 sudo）"
  fi
}

# 是否有可交互的终端（curl | sh 时 stdin 是脚本本身，只能从 /dev/tty 读取）
bs_has_tty() {
  [ "${BOOTSTRAP_NONINTERACTIVE:-0}" = 1 ] && return 1
  # 必须在子 shell 中尝试：`:` 是特殊内建命令，重定向失败会让整个 shell 退出（P-026）
  (exec </dev/tty) 2>/dev/null
}

# bs_ask <变量名> <提示> [secret]：从 /dev/tty 读取一行，secret 时不回显
bs_ask() {
  _var=$1
  _prompt=$2
  bs_has_tty || bs_die "需要交互输入「$_prompt」，但当前没有终端；请改用对应的环境变量"
  printf '%s' "$_prompt" >/dev/tty
  if [ "${3:-}" = secret ]; then
    _stty=$(stty -g </dev/tty)
    stty -echo </dev/tty
    IFS= read -r _val </dev/tty || _val=
    stty "$_stty" </dev/tty
    printf '\n' >/dev/tty
  else
    IFS= read -r _val </dev/tty || _val=
  fi
  eval "$_var=\$_val"
  unset _var _prompt _val _stty
}

# bs_confirm <提示>：返回 0 表示用户输入了 yes
bs_confirm() {
  bs_ask _ans "$1 [yes/no] "
  case "$_ans" in yes | YES | y | Y) unset _ans; return 0 ;; esac
  unset _ans
  return 1
}

# XDG 默认值：mise 的 hooks / postinstall 依赖这些变量（pitfalls P-006）
bs_export_xdg() {
  export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
  export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
  BS_STATE_DIR="$XDG_STATE_HOME/bootstrap"
}

# 把 KEY=VALUE 写入 shell 可 source 的文件（值用单引号包裹）
bs_env_line() {
  printf "export %s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"
}

# sha256（macOS 没有 sha256sum）：从 stdin 读取，输出十六进制摘要
bs_sha256() {
  if bs_have sha256sum; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}
