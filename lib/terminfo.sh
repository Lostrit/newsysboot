#!/bin/sh
# lib/terminfo.sh — 终端类型数据库补充（D-034）
#
# Ghostty 默认 TERM=xterm-ghostty，各发行版的 ncurses 都没有这个名字（ncurses 6.5 起只有 ghostty），
# 经 SSH 登录后 tput / zsh 行编辑 / nvim / tmux 都不认识终端（P-047）。
# 仓库自带 terminfo 源（files/terminfo/*.ti），root 阶段用 tic 编译到 /etc/terminfo：
#   /etc/terminfo 是本机自定义条目的位置，搜索顺序在 /lib/terminfo、/usr/share/terminfo（ncurses 软件包管理）之前。
# 每次运行都重新编译（很快），保证与仓库一致；没有 tic（ncurses-bin）时跳过并给出 WARNING。

bs_terminfo_install() {
  [ "$BOOTSTRAP_OS" = linux ] || return 0
  if ! bs_have tic; then
    bs_warn "WARNING: 没有 tic（ncurses-bin），跳过安装 Ghostty 等终端的 terminfo"
    return 0
  fi
  for _ti in "$BS_SRC"/files/terminfo/*.ti; do
    [ -f "$_ti" ] || continue
    bs_root mkdir -p /etc/terminfo
    if bs_root tic -x -o /etc/terminfo "$_ti" 2>/dev/null; then
      bs_log "terminfo：$(sed -n 's/^\([^#[:space:]][^,]*\),$/\1/p' "$_ti" | head -n 1 | cut -d'|' -f1) → /etc/terminfo"
    else
      bs_warn "WARNING: 编译 terminfo 失败：$_ti"
    fi
  done
}
