#!/bin/sh
# lib/user.sh — root → 普通用户（D-004）
#
# 环境变量（无人值守时使用）：
#   BOOTSTRAP_USER            用户名
#   BOOTSTRAP_PASSWORD        明文密码（经 chpasswd 哈希，不落盘）
#   BOOTSTRAP_PASSWORD_HASH   已哈希的密码（chpasswd -e）；两者都没有且无终端时锁定密码，仅允许 SSH 公钥 + 免密 sudo
#   BOOTSTRAP_HARDEN_SSH=1    无人值守时也执行 SSH 加固（删除 root 公钥、禁止 root 与密码登录）

bs_valid_username() {
  printf '%s' "$1" | grep -Eq '^[a-z_][a-z0-9_-]{0,31}$'
}

bs_create_user() {
  _u=${BOOTSTRAP_USER:-}
  while [ -z "$_u" ]; do
    bs_ask _u "请输入要创建的普通用户名: "
    bs_valid_username "$_u" || {
      bs_warn "用户名只能包含小写字母、数字、- 和 _，且以字母或 _ 开头"
      _u=
    }
  done
  bs_valid_username "$_u" || bs_die "非法用户名：$_u"
  BOOTSTRAP_USER=$_u
  export BOOTSTRAP_USER

  if id "$_u" >/dev/null 2>&1; then
    bs_log "用户 $_u 已存在，跳过创建"
  else
    _sh=/bin/bash
    [ -x /usr/bin/zsh ] && _sh=/usr/bin/zsh
    useradd -m -s "$_sh" "$_u"
    bs_log "已创建用户 $_u"
    bs_set_password "$_u"
  fi

  # sudo 组（Debian / Ubuntu 为 sudo）
  getent group sudo >/dev/null && usermod -aG sudo "$_u"

  # 免密 sudo：先写临时文件并用 visudo 检查，再原子替换
  _sf="/etc/sudoers.d/90-bootstrap-$_u"
  _tmp=$(mktemp)
  printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$_u" >"$_tmp"
  if bs_have visudo; then
    visudo -cqf "$_tmp" || bs_die "sudoers 校验失败"
  fi
  install -m 0440 -o root -g root "$_tmp" "$_sf"
  rm -f "$_tmp"

  bs_copy_root_keys "$_u"
}

bs_set_password() {
  if [ -n "${BOOTSTRAP_PASSWORD_HASH:-}" ]; then
    printf '%s:%s\n' "$1" "$BOOTSTRAP_PASSWORD_HASH" | chpasswd -e
  elif [ -n "${BOOTSTRAP_PASSWORD:-}" ]; then
    printf '%s:%s\n' "$1" "$BOOTSTRAP_PASSWORD" | chpasswd
  elif bs_has_tty; then
    while :; do
      bs_ask _p1 "请为 $1 设置密码: " secret
      bs_ask _p2 "请再次输入密码: " secret
      if [ -n "$_p1" ] && [ "$_p1" = "$_p2" ]; then break; fi
      bs_warn "两次输入不一致或为空，请重试"
    done
    printf '%s:%s\n' "$1" "$_p1" | chpasswd
    unset _p1 _p2
  else
    bs_warn "无终端且未提供密码：锁定 $1 的密码（仍可用 SSH 公钥登录、免密 sudo）"
    passwd -l "$1" >/dev/null
  fi
  unset BOOTSTRAP_PASSWORD BOOTSTRAP_PASSWORD_HASH
}

# 把 root 的 authorized_keys 追加给新用户（去重）
bs_copy_root_keys() {
  _src=/root/.ssh/authorized_keys
  [ -s "$_src" ] || return 0
  _home=$(getent passwd "$1" | cut -d: -f6)
  install -d -m 700 -o "$1" -g "$(id -gn "$1")" "$_home/.ssh"
  _dst="$_home/.ssh/authorized_keys"
  touch "$_dst"
  # 逐行追加尚不存在的公钥
  while IFS= read -r _k; do
    [ -n "$_k" ] || continue
    grep -qxF "$_k" "$_dst" || printf '%s\n' "$_k" >>"$_dst"
  done <"$_src"
  chown "$1:$(id -gn "$1")" "$_dst"
  chmod 600 "$_dst"
  bs_log "已把 root 的 SSH 公钥复制给 $1"
}
