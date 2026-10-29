#!/bin/sh
# lib/ssh.sh — SSH 加固（D-004）：禁止 root 登录与密码登录，删除 root 的公钥
#
# 只在有 sshd 的 Linux 主机上执行（容器跳过）。为防止把自己锁在外面：
#   1. 新用户必须已有 authorized_keys；
#   2. 交互模式下要求用户新开终端验证新用户能登录并 sudo，输入 yes 才继续；
#      无人值守时必须显式设置 BOOTSTRAP_HARDEN_SSH=1。
# drop-in 命名为 00- 开头：sshd 对同一选项取第一次读到的值，要排在 cloud-init 的 50-cloud-init.conf 之前（P-005）。

BS_SSHD_DROPIN=/etc/ssh/sshd_config.d/00-bootstrap.conf

bs_sshd_present() {
  [ -x /usr/sbin/sshd ] && [ -d /etc/ssh ]
}

bs_harden_ssh() {
  _u=$1
  bs_sshd_present || {
    bs_log "未安装 sshd，跳过 SSH 加固"
    return 0
  }
  _home=$(getent passwd "$_u" | cut -d: -f6)
  if [ ! -s "$_home/.ssh/authorized_keys" ]; then
    bs_warn "$_u 没有 SSH 公钥，为避免无法登录，跳过 SSH 加固（root 的公钥与登录方式保持不变）"
    return 0
  fi

  if [ "${BOOTSTRAP_HARDEN_SSH:-}" != 1 ]; then
    if ! bs_has_tty; then
      bs_warn "无人值守且未设置 BOOTSTRAP_HARDEN_SSH=1，跳过 SSH 加固"
      return 0
    fi
    printf '\n请保持当前会话不要断开，新开一个终端执行：\n  ssh %s@<本机地址> sudo true\n确认能登录且 sudo 不需要密码后再继续。\n' "$_u" >/dev/tty
    bs_confirm "新用户 $_u 已验证可以登录并 sudo？" || {
      bs_warn "未确认，跳过 SSH 加固；之后可执行 bootstrap.sh --harden-ssh 重新进行"
      return 0
    }
  fi

  _tmp=$(mktemp)
  cat >"$_tmp" <<'EOF'
# 由 bootstrap 生成（lib/ssh.sh）。文件名以 00- 开头，保证先于 50-cloud-init.conf 等生效
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
  install -d -m 755 /etc/ssh/sshd_config.d
  # 主配置中必须包含 sshd_config.d（Debian 12+ / Ubuntu 22.04+ 默认包含）
  grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config ||
    bs_die "/etc/ssh/sshd_config 没有 Include sshd_config.d，请手动检查"
  install -m 644 "$_tmp" "$BS_SSHD_DROPIN"
  rm -f "$_tmp"
  if ! /usr/sbin/sshd -t; then
    rm -f "$BS_SSHD_DROPIN"
    bs_die "sshd 配置校验失败，已撤销改动"
  fi
  # 确认实际生效的值（防止被其他 drop-in 覆盖）
  _eff=$(/usr/sbin/sshd -T 2>/dev/null | grep -Ei '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication) ')
  printf '%s\n' "$_eff" | grep -qi '^permitrootlogin no' || bs_die "PermitRootLogin 未生效：$_eff"
  printf '%s\n' "$_eff" | grep -qi '^passwordauthentication no' || bs_die "PasswordAuthentication 未生效：$_eff"

  # 先让配置生效，再删除 root 的公钥
  if bs_have systemctl && [ -d /run/systemd/system ]; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  fi
  if [ -e /root/.ssh/authorized_keys ]; then
    mv /root/.ssh/authorized_keys "/root/.ssh/authorized_keys.bootstrap.removed.$(date +%Y%m%d%H%M%S)"
    chmod 600 /root/.ssh/authorized_keys.bootstrap.removed.* 2>/dev/null || true
    bs_log "已移除 root 的 authorized_keys（备份在 /root/.ssh/authorized_keys.bootstrap.removed.*）"
  fi
  bs_log "SSH 加固完成：禁止 root 登录、禁止密码登录"
}
