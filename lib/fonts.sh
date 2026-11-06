#!/bin/sh
# lib/fonts.sh — 本地系统（macOS、SteamOS；Windows 见 bootstrap.ps1）的终端字体：Maple Mono Normal NF CN（D-039）
#
# Maple Mono（https://github.com/subframe7536/maple-font）：「Normal」字形、带连字（文件名不含 NL）、
# Nerd Font 图标（NF）、中文（CN）、hinted（文件名不含 -unhinted）。
# 锁定版本与 sha256（经第三方 GitHub 加速代理下载，必须校验）；bootstrap.ps1 读取下面三个变量，两边共用一份定义。
# 压缩包内有 16 个字重（解压后约 330 MB），默认只装终端用到的 4 个：BOOTSTRAP_FONT_STYLES=all 安装全部；
# BOOTSTRAP_FONTS=0 不安装。只决定安装，终端中选用哪个字体由用户在终端设置中完成。
BS_FONT_VERSION="7.9"
BS_FONT_ASSET="MapleMonoNormal-NF-CN.zip"
BS_FONT_SHA256="24aeb14ed756d78b112e6692ea02c669e16afaa0f01e7bfdbb37d2e63fa45fa7"
BS_FONT_STYLES="Regular Italic Bold BoldItalic"

bs_font_dir() {
  if [ "$BOOTSTRAP_OS" = macos ]; then echo "$HOME/Library/Fonts"; else echo "$XDG_DATA_HOME/fonts/MapleMono"; fi
}

# 解压指定文件（没有 unzip 时用 python3）
bs_unzip() {
  _z=$1 _d=$2
  shift 2
  if bs_have unzip; then
    unzip -qoj "$_z" "$@" -d "$_d"
  elif bs_have python3; then
    python3 -I - "$_z" "$_d" "$@" <<'EOF'
import os, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = sys.argv[3:] or [n for n in z.namelist() if n.endswith(".ttf")]
for n in names:
    with z.open(n) as src, open(os.path.join(sys.argv[2], os.path.basename(n)), "wb") as dst:
        dst.write(src.read())
EOF
  else
    bs_warn "WARNING: 没有 unzip，也没有 python3，无法解压字体"
    return 1
  fi
}

bs_fonts_install() {
  [ "${BOOTSTRAP_FONTS:-1}" != 0 ] || return 0
  bs_is_local_role || return 0
  _styles=${BOOTSTRAP_FONT_STYLES:-$BS_FONT_STYLES}
  _base=${BS_FONT_ASSET%.zip}
  _dir=$(bs_font_dir)
  _mark="$_dir/.bootstrap-maple-mono"
  _want="$BS_FONT_VERSION $BS_FONT_ASSET $_styles"
  if [ "$(cat "$_mark" 2>/dev/null)" = "$_want" ]; then
    return 0
  fi
  _url="https://github.com/subframe7536/maple-font/releases/download/v$BS_FONT_VERSION/$BS_FONT_ASSET"
  _t=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-font.XXXXXX")
  _ok=
  # 主代理 → 备用代理 → 直连（有 mihomo 时经代理，D-031、D-033）；约 150 MB，按速度判断超时
  for _p in ${GH_PROXY:-} ${GH_PROXY_BACKUP:-} direct; do
    [ "$_p" != direct ] || _p=
    bs_log "下载字体 Maple Mono $BS_FONT_VERSION（约 150 MB）：${_p}$_url"
    if curl -fsSL --connect-timeout 10 --speed-limit 20480 --speed-time 60 -o "$_t/f.zip" "${_p}$_url" &&
      [ "$(bs_sha256 <"$_t/f.zip")" = "$BS_FONT_SHA256" ]; then
      _ok=1
      break
    fi
    bs_warn "WARNING: 字体下载失败或 sha256 不符：${_p}$_url"
    rm -f "$_t/f.zip"
  done
  if [ -z "$_ok" ]; then
    rm -rf "$_t"
    bs_warn "WARNING: 字体未安装；网络可用后重新运行 bootstrap.sh 即可"
    return 0
  fi
  mkdir -p "$_dir"
  if [ "$_styles" = all ]; then
    set --
  else
    set --
    for _s in $_styles; do set -- "$@" "$_base-$_s.ttf"; done
  fi
  if bs_unzip "$_t/f.zip" "$_dir" "$@"; then
    printf '%s\n' "$_want" >"$_mark"
    # Linux：刷新 fontconfig 缓存（macOS 放进 ~/Library/Fonts 即可使用）
    if [ "$BOOTSTRAP_OS" = linux ] && bs_have fc-cache; then fc-cache -f "$_dir" >/dev/null 2>&1 || true; fi
    bs_log "字体已安装：$_dir（$_styles）；请在终端设置中选用「Maple Mono Normal NF CN」"
  else
    bs_warn "WARNING: 字体解压失败"
  fi
  rm -rf "$_t"
}
