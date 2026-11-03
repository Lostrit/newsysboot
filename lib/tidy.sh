#!/bin/sh
# lib/tidy.sh — 保持 HOME 整洁（D-030）：清理系统 / 云镜像预置、已由 bootstrap 接管的文件，把可以放进 XDG 目录的移过去
#
# 原则：不误删。
#   - 云镜像预置的镜像源配置：只有内容与已知默认值完全一致时才删除（镜像源改由 env.sh 的环境变量提供）；内容不同则保留并提示
#   - bash 默认文件：登录 shell 已是 zsh；只有与 /etc/skel 中的文件完全相同时才删除
#   - 历史记录、terminfo、docker 配置：移动到 XDG 目录，不删除
# user 阶段以当前用户执行（--dotfiles 模式也会执行）；BOOTSTRAP_NO_TIDY=1 跳过。

# 去掉行尾空白与空行后比较（云镜像中的文件常带行尾空格）
bs_tidy_norm() {
  sed -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# bs_tidy_known <文件> <已知内容…>：内容与任意一个已知内容一致时删除；不一致时提示保留
bs_tidy_known() {
  _f=$1
  shift
  [ -f "$_f" ] && [ ! -L "$_f" ] || return 0
  _cur=$(bs_tidy_norm "$_f")
  for _want in "$@"; do
    if [ "$_cur" = "$_want" ]; then
      rm -f "$_f"
      bs_log "已删除 ${_f#"$HOME"/}（云镜像预置的镜像源配置，改由 env.sh 提供）"
      return 0
    fi
  done
  bs_warn "保留 ${_f#"$HOME"/}：内容与云镜像默认值不同（可能是你自己的配置）"
}

# bs_tidy_move <旧路径> <新路径>：新路径不存在时移动；都存在时保留旧的并提示
bs_tidy_move() {
  [ -e "$1" ] && [ ! -L "$1" ] || return 0
  if [ -e "$2" ]; then
    bs_warn "${1#"$HOME"/} 与 ${2#"$HOME"/} 同时存在，保留前者，请手动合并"
    return 0
  fi
  mkdir -p "$(dirname "$2")"
  mv "$1" "$2"
  bs_log "已移动 ${1#"$HOME"/} → ${2#"$HOME"/}"
}

bs_tidy_home() {
  [ "${BOOTSTRAP_NO_TIDY:-}" = 1 ] && return 0
  [ "$BOOTSTRAP_OS" = linux ] || return 0

  # 1. 云镜像预置的镜像源配置（目前收录腾讯云；其他云的默认内容核实后再加入）
  bs_tidy_known "$HOME/.pip/pip.conf" \
    "$(printf '[global]\nindex-url = http://mirrors.tencentyun.com/pypi/simple\ntrusted-host = mirrors.tencentyun.com')"
  rmdir "$HOME/.pip" 2>/dev/null || true
  bs_tidy_known "$HOME/.pydistutils.cfg" \
    "$(printf '[easy_install]\nindex-url = http://mirrors.tencentyun.com/pypi/simple')"
  bs_tidy_known "$HOME/.npmrc" "registry=https://mirrors.tencentyun.com/npm"

  # 2. bash 默认文件：与 /etc/skel 完全相同时删除（没有它们时 bash 使用系统的 /etc/bash.bashrc）
  for _b in .bashrc .bash_logout .profile; do
    if [ -f "$HOME/$_b" ] && [ ! -L "$HOME/$_b" ] && [ -f "/etc/skel/$_b" ]; then
      if cmp -s "$HOME/$_b" "/etc/skel/$_b"; then
        rm -f "$HOME/$_b"
        bs_log "已删除 $_b（与 /etc/skel 相同；登录 shell 为 zsh）"
      else
        bs_warn "保留 $_b：与 /etc/skel 不同（可能有你自己的修改）"
      fi
    fi
  done

  # 3. 移到 XDG 目录（.zshenv 中设置了对应的环境变量 / zsh 的 bash 别名）
  bs_tidy_move "$HOME/.bash_history" "$XDG_STATE_HOME/bash/history"
  bs_tidy_move "$HOME/.lesshst" "$XDG_STATE_HOME/less/history"
  bs_tidy_move "$HOME/.python_history" "$XDG_STATE_HOME/python/history"
  bs_tidy_move "$HOME/.docker" "$XDG_CONFIG_HOME/docker"
  # Ghostty 等终端经 SSH 安装的 terminfo：TERMINFO_DIRS 包含新位置，之后终端检查时能找到，不会再写 ~/.terminfo
  bs_tidy_move "$HOME/.terminfo" "$XDG_DATA_HOME/terminfo"

  # 4. Ubuntu 的 sudo 第一次使用时创建的提示标记（root 阶段已在 sudoers 中关闭 admin_flag）
  if [ -f "$HOME/.sudo_as_admin_successful" ] && [ ! -s "$HOME/.sudo_as_admin_successful" ]; then
    rm -f "$HOME/.sudo_as_admin_successful"
    bs_log "已删除 .sudo_as_admin_successful"
  fi
}

# root 权限：关闭 Ubuntu sudo 的 admin_flag，不再在用户 HOME 中创建 .sudo_as_admin_successful
bs_sudo_no_admin_flag() {
  [ "$BOOTSTRAP_OS" = linux ] && bs_have sudo && [ -d /etc/sudoers.d ] || return 0
  _sf=/etc/sudoers.d/00-bootstrap-no-admin-flag
  [ -f "$_sf" ] && return 0
  _t=$(mktemp)
  printf '# 由 bootstrap 生成（lib/tidy.sh，D-030）：不在用户 HOME 中创建 .sudo_as_admin_successful\nDefaults !admin_flag\n' >"$_t"
  # 不认识该选项的 sudo 会校验失败，此时跳过
  if bs_root visudo -cqf "$_t" >/dev/null 2>&1; then
    bs_root install -m 0440 -o root -g root "$_t" "$_sf"
  fi
  rm -f "$_t"
}
