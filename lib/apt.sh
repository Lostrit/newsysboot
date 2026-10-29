#!/bin/sh
# lib/apt.sh — Debian / Ubuntu apt 换源与基础包安装（D-006）
#
# 统一写成 deb822 格式（apt ≥ 1.1 支持，Debian 11 / Ubuntu 22.04 起均可用）：
#   /etc/apt/sources.list.d/{debian,ubuntu}.sources
# 原有的 sources.list / *.sources 首次改写前备份为 *.bootstrap.bak。

# 进入 stage-0 时还没有 curl / CA 证书时使用的临时源（全国各家云均可访问；http 不依赖 CA 证书）
: "${BS_APT_FALLBACK_MIRROR:=http://mirrors.cloud.tencent.com}"

bs_apt_keyring() {
  for _k in "/usr/share/keyrings/$BOOTSTRAP_DISTRO-archive-keyring.pgp" \
    "/usr/share/keyrings/$BOOTSTRAP_DISTRO-archive-keyring.gpg"; do
    [ -r "$_k" ] && {
      echo "$_k"
      return 0
    }
  done
  bs_die "找不到 $BOOTSTRAP_DISTRO 的 archive keyring"
}

# 生成 deb822 内容：bs_apt_sources <mirror>
bs_apt_sources() {
  _m=${1%/}
  _kr=$(bs_apt_keyring)
  _c=$BOOTSTRAP_CODENAME
  case "$BOOTSTRAP_DISTRO" in
    debian)
      _comp="main contrib non-free"
      [ "${BOOTSTRAP_VERSION%%.*}" -ge 12 ] 2>/dev/null && _comp="$_comp non-free-firmware"
      cat <<EOF
# 由 bootstrap 生成（lib/apt.sh），原文件备份为 *.bootstrap.bak
Types: deb
URIs: $_m/debian
Suites: $_c $_c-updates
Components: $_comp
Signed-By: $_kr

Types: deb
URIs: $_m/debian-security
Suites: $_c-security
Components: $_comp
Signed-By: $_kr
EOF
      ;;
    ubuntu)
      _p=$(bs_apt_path)
      cat <<EOF
# 由 bootstrap 生成（lib/apt.sh），原文件备份为 *.bootstrap.bak
Types: deb
URIs: $_m/$_p
Suites: $_c $_c-updates $_c-backports $_c-security
Components: main restricted universe multiverse
Signed-By: $_kr
EOF
      ;;
    *) bs_die "apt 换源不支持 $BOOTSTRAP_DISTRO" ;;
  esac
}

# bs_apt_set_mirror <mirror>：写入源文件；内容有变化时返回 0（需要 apt-get update）
bs_apt_set_mirror() {
  [ -n "$1" ] || return 1
  [ -n "$BOOTSTRAP_CODENAME" ] || bs_die "无法确定发行版代号（/etc/os-release 缺少 VERSION_CODENAME）"
  _target="/etc/apt/sources.list.d/$BOOTSTRAP_DISTRO.sources"
  _new=$(bs_apt_sources "$1")
  if [ -r "$_target" ] && [ "$(cat "$_target")" = "$_new" ]; then
    return 1
  fi
  for _f in /etc/apt/sources.list "$_target"; do
    if [ -s "$_f" ] && [ ! -e "$_f.bootstrap.bak" ] && ! grep -q '由 bootstrap 生成' "$_f"; then
      bs_root cp -p "$_f" "$_f.bootstrap.bak"
    fi
  done
  # sources.list 中的条目会与 deb822 重复，清空（备份已保留）
  if [ -s /etc/apt/sources.list ] && grep -qE '^[[:space:]]*deb ' /etc/apt/sources.list; then
    printf '# 已迁移到 %s（bootstrap），原内容见 sources.list.bootstrap.bak\n' "$_target" | bs_root tee /etc/apt/sources.list >/dev/null
  fi
  printf '%s\n' "$_new" | bs_root tee "$_target" >/dev/null
  bs_log "apt 源已切换到 $1"
  return 0
}

# apt 的正常输出很长，默认只显示错误（BS_DEBUG=1 显示全部）
bs_apt_install() {
  bs_log "apt-get install $*"
  if [ -n "${BS_DEBUG:-}" ]; then
    bs_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends "$@"
  else
    bs_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" >/dev/null
  fi
}

bs_apt_update() {
  bs_log "apt-get update"
  if [ -n "${BS_DEBUG:-}" ]; then bs_root apt-get update -q; else bs_root apt-get update -qq >/dev/null; fi
}

# 保证 curl 和 CA 证书可用（全新镜像中都没有），必要时先切到临时源
bs_apt_ensure_curl() {
  if bs_have curl && [ -r /etc/ssl/certs/ca-certificates.crt ]; then
    return 0
  fi
  bs_log "安装 curl / ca-certificates（临时源：${BOOTSTRAP_APT_MIRROR:-$BS_APT_FALLBACK_MIRROR}）"
  bs_apt_set_mirror "${BOOTSTRAP_APT_MIRROR:-$BS_APT_FALLBACK_MIRROR}" || true
  bs_apt_update
  bs_apt_install curl ca-certificates
}
