#!/bin/sh
# lib/roles.sh — 部署环境（角色）与按环境排除的全局工具（D-036）
#
# 角色：macos | steamos（本地系统）、host | container（远程系统）；Windows 由 bootstrap.ps1 处理（windows）。
# 排除的工具在 lib/tool-roles.txt，写入 env.sh 的 MISE_DISABLE_TOOLS（mise 的 disable_tools）。

bs_role() {
  case "$BOOTSTRAP_DISTRO" in
    macos) echo macos ;;
    steamos) echo steamos ;;
    *) if [ "$BOOTSTRAP_CONTAINER" = 1 ]; then echo container; else echo host; fi ;;
  esac
}

# bs_disabled_tools [角色] [文件]：逗号分隔的工具名
bs_disabled_tools() {
  _r=${1:-$(bs_role)}
  _f=${2:-$BS_SRC/lib/tool-roles.txt}
  [ -r "$_f" ] || return 0
  sed -n "s/#.*//; s/^$_r:[[:space:]]*//p" "$_f" | tr -s ' \t' '\n\n' | sed '/^$/d' | paste -sd, -
}

# 本地系统（物理接触、图形界面）：安装 Nerd Font 等
bs_is_local_role() {
  case "$(bs_role)" in macos | steamos) return 0 ;; esac
  return 1
}
