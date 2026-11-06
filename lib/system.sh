#!/bin/sh
# lib/system.sh — 远程系统（Debian / Ubuntu 主机与容器）的 locale、时区与容器 sshd（D-038）
#
#   locale：生成 en_US.UTF-8 与 BOOTSTRAP_LOCALE（默认 zh_CN.UTF-8），系统默认 LANG=BOOTSTRAP_LOCALE、
#           LANGUAGE=BOOTSTRAP_LANGUAGE（默认 zh_CN:en_US）；不设置 LC_ALL（会覆盖所有分类）。BOOTSTRAP_LOCALE=none 跳过
#   时区：BOOTSTRAP_TZ（默认 Asia/Shanghai）；BOOTSTRAP_TZ=none 跳过
#   容器 sshd：不在镜像 / 容器层中保存主机私钥；主机私钥在容器启动后经 docker exec 写入内存（/dev/shm），
#             授权公钥来自 docker secrets（files/container/bootstrap-sshd.sh、docs/container.md）

# locale 名称比较时忽略大小写与「-」：locale -a 输出 zh_CN.utf8
bs_locale_norm() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '-'
}

bs_locale_have() {
  locale -a 2>/dev/null | while read -r _x; do
    [ "$(bs_locale_norm "$_x")" = "$(bs_locale_norm "$1")" ] && { echo yes; break; }
  done | grep -q yes
}

bs_locale_setup() {
  _loc=${BOOTSTRAP_LOCALE:-zh_CN.UTF-8}
  _lang=${BOOTSTRAP_LANGUAGE:-zh_CN:en_US}
  [ "$_loc" != none ] || return 0
  bs_have locale-gen || {
    bs_warn "WARNING: 没有 locale-gen（locales 软件包），跳过 locale 设置"
    return 0
  }
  _missing=
  for _l in en_US.UTF-8 "$_loc"; do
    bs_locale_have "$_l" || _missing="$_missing $_l"
  done
  if [ -n "$_missing" ]; then
    bs_log "生成 locale：$_missing"
    for _l in $_missing; do
      _e="$_l ${_l##*.}"
      [ -f /etc/locale.gen ] || bs_root touch /etc/locale.gen
      if grep -q "^#[[:space:]]*$_e\$" /etc/locale.gen; then
        bs_root sed -i "s/^#[[:space:]]*$_e\$/$_e/" /etc/locale.gen
      elif ! grep -q "^$_e\$" /etc/locale.gen; then
        printf '%s\n' "$_e" | bs_root tee -a /etc/locale.gen >/dev/null
      fi
    done
    # Debian 的 locale-gen 按 /etc/locale.gen 生成；Ubuntu 的需要在参数中指定
    if [ "$BOOTSTRAP_DISTRO" = ubuntu ]; then
      # shellcheck disable=SC2086
      bs_root locale-gen $_missing >/dev/null || true
    else
      bs_root locale-gen >/dev/null || true
    fi
    for _l in $_missing; do
      bs_locale_have "$_l" || bs_warn "WARNING: locale $_l 生成失败"
    done
  fi
  # 系统默认 locale（登录会话经 PAM 读取 /etc/default/locale）
  _want="LANG=$_loc
LANGUAGE=$_lang"
  if [ "$(grep -E '^(LANG|LANGUAGE)=' /etc/default/locale 2>/dev/null | tr -d '"' | sort)" != "$(printf '%s\n' "$_want" | sort)" ]; then
    bs_log "系统默认 locale：LANG=$_loc LANGUAGE=$_lang"
    if bs_have update-locale && bs_locale_have "$_loc"; then
      bs_root update-locale "LANG=$_loc" "LANGUAGE=$_lang" || bs_warn "WARNING: update-locale 失败"
    elif ! bs_locale_have "$_loc"; then
      bs_warn "WARNING: 没有 locale $_loc，不修改系统默认 locale"
      return 0
    else
      printf '%s\n' "$_want" | bs_root tee /etc/default/locale >/dev/null
    fi
  fi
}

bs_timezone_setup() {
  _tz=${BOOTSTRAP_TZ:-Asia/Shanghai}
  [ "$_tz" != none ] || return 0
  [ -e "/usr/share/zoneinfo/$_tz" ] || {
    bs_warn "WARNING: 没有时区数据 /usr/share/zoneinfo/$_tz（tzdata 软件包），跳过时区设置"
    return 0
  }
  _cur=$(readlink /etc/localtime 2>/dev/null | sed 's#.*zoneinfo/##')
  if [ "$_cur" != "$_tz" ]; then
    bs_log "时区：${_cur:-<未设置>} → $_tz"
    # timedatectl 需要 systemd-timedated（带 systemd 的容器中可能没有），失败时直接改链接
    if ! { [ "$BOOTSTRAP_SYSTEMD" = 1 ] && bs_have timedatectl && bs_root timedatectl set-timezone "$_tz" 2>/dev/null; }; then
      bs_root ln -snf "/usr/share/zoneinfo/$_tz" /etc/localtime
    fi
  fi
  # Debian 13 起 tzdata 不再使用 /etc/timezone：只在文件已存在时保持一致
  if [ -f /etc/timezone ] && [ "$(cat /etc/timezone)" != "$_tz" ]; then
    printf '%s\n' "$_tz" | bs_root tee /etc/timezone >/dev/null
  fi
}

BS_SSHD_CONTAINER_DROPIN=/etc/ssh/sshd_config.d/00-bootstrap-container.conf

# 容器中的 sshd：删除安装时生成的主机私钥，写入配置与入口脚本（不启动：容器没有 systemd，由镜像入口启动）
bs_container_sshd_setup() {
  [ -x /usr/sbin/sshd ] || return 0
  # openssh-server 安装后会生成主机私钥，留在镜像层中就等于所有容器共用、且随镜像分发（D-038）
  for _k in /etc/ssh/ssh_host_*; do
    [ -e "$_k" ] || continue
    bs_log "删除镜像中的 SSH 主机密钥：/etc/ssh/ssh_host_*"
    bs_root rm -f /etc/ssh/ssh_host_*
    break
  done
  bs_root install -m 755 "$BS_SRC/files/container/bootstrap-sshd.sh" /usr/local/bin/bootstrap-sshd
  _conf="# 由 bootstrap 生成（lib/system.sh，D-038），重新运行 bootstrap.sh 会覆盖
# 主机私钥：容器启动后经 docker exec 写入内存（bootstrap-sshd load-key），不在镜像 / 容器层中保存
HostKey /dev/shm/bootstrap-sshd/ssh_host_ed25519_key
# 授权公钥：容器启动时由 bootstrap-sshd 从 docker secrets 复制
AuthorizedKeysFile /etc/ssh/bootstrap_authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no"
  if [ "$(cat "$BS_SSHD_CONTAINER_DROPIN" 2>/dev/null)" != "$_conf" ]; then
    bs_root mkdir -p /etc/ssh/sshd_config.d
    printf '%s\n' "$_conf" | bs_root tee "$BS_SSHD_CONTAINER_DROPIN" >/dev/null
    bs_log "sshd 配置：$BS_SSHD_CONTAINER_DROPIN（入口：/usr/local/bin/bootstrap-sshd）"
  fi
}
