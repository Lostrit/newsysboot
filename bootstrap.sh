#!/bin/sh
# bootstrap.sh — stage-0 入口（POSIX sh；docs/plan.md）
#
# 用法：
#   curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/Lostrit/newsysboot/main/bootstrap.sh | sh                  # 全新机器：完整初始化
#   curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/Lostrit/newsysboot/main/bootstrap.sh | sh -s -- --dotfiles # 只部署 dotfiles 与工具（不需要 root，D-009）
#   sh bootstrap.sh [选项]                               # 在仓库检出目录中执行
#
# 选项：
#   --dotfiles        只部署 dotfiles / 工具，不改系统
#   --source <s>      拉取来源：github（经加速）| cnb；默认询问，环境变量 BOOTSTRAP_SOURCE
#   --dir <dir>       仓库检出目录，默认 $XDG_DATA_HOME/bootstrap；环境变量 BOOTSTRAP_DIR
#   --env <a,b>       覆盖自动检测的模块；环境变量 BOOTSTRAP_ENV
#   --harden-ssh      执行（或重新执行）SSH 加固
#   --reprobe         忽略缓存，重新测速选源
#   --skip <parts>    传给 mise bootstrap 的 --skip（如 tools）
#   --no-nvim         不预装 nvim 插件与工具（默认：网络检测通过时预装，否则给出 WARNING 跳过）；BOOTSTRAP_NVIM=0
#   --nvim            不检测网络、强制预装，失败则退出非零（适合 Dockerfile）；BOOTSTRAP_NVIM=1
#   --dry-run         mise bootstrap 只预览
#   -h, --help
#
# 无人值守时使用的环境变量：BOOTSTRAP_USER、BOOTSTRAP_PASSWORD(_HASH)、BOOTSTRAP_HARDEN_SSH=1、
# FNOX_AGE_KEY（age 私钥）、BOOTSTRAP_NONINTERACTIVE=1；完整列表见 docs/usage.md。
set -eu

# 远程仓库地址（创建远程仓库后填入默认值，D-011）
: "${BOOTSTRAP_REPO_GITHUB:=https://github.com/Lostrit/newsysboot.git}"
: "${BOOTSTRAP_REPO_CNB:=https://cnb.cool/xfengjing/lostrit/NewSysBoot.git}"

# ---------------------------------------------------------------------------
# 管道模式：脚本旁边没有 lib/，先把仓库拉到临时目录，再交给仓库中的 bootstrap.sh
# ---------------------------------------------------------------------------
bs_self_dir() {
  case "$0" in */*) (cd "${0%/*}" && pwd) ;; *) pwd ;; esac
}

if [ ! -f "$(bs_self_dir)/lib/common.sh" ]; then
  _say() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
  _die() {
    printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
    exit 1
  }
  _root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }

  if [ -z "${BOOTSTRAP_SOURCE:-}" ]; then
    # 在子 shell 中尝试打开 /dev/tty：`:` 是特殊内建命令，重定向失败会让整个 shell 退出（P-026）
    if (exec </dev/tty) 2>/dev/null; then
      printf '从哪里拉取本仓库？ 1) GitHub（经加速代理）  2) CNB  [1]: ' >/dev/tty
      read -r _c </dev/tty || _c=
      case "$_c" in 2 | cnb) BOOTSTRAP_SOURCE=cnb ;; *) BOOTSTRAP_SOURCE=github ;; esac
    else
      BOOTSTRAP_SOURCE=github
    fi
  fi
  export BOOTSTRAP_SOURCE

  # macOS：/usr/bin/git 只是占位程序，没有 Xcode 命令行工具时 `command -v git` 也能找到它，但无法使用（P-038）。
  # 先触发系统的安装窗口，并等待安装完成（最多 30 分钟），之后继续，不需要重新运行
  if [ "$(uname -s)" = Darwin ] && ! xcode-select -p >/dev/null 2>&1; then
    _say "安装 Xcode 命令行工具（提供 git）：请在弹出的系统窗口中点击「安装」，完成后会自动继续"
    xcode-select --install >/dev/null 2>&1 || true
    # 轮询间隔与最长等待时间（秒）可以覆盖，供测试使用
    _poll=${BS_CLT_POLL:-5}
    _max=$((${BS_CLT_TIMEOUT:-1800} / _poll))
    _every=$((60 / _poll))
    [ "$_every" -ge 1 ] || _every=1
    _i=0
    while ! xcode-select -p >/dev/null 2>&1; do
      [ "$_i" -lt "$_max" ] || _die "Xcode 命令行工具尚未安装完成；安装完成后请重新运行本命令"
      _i=$((_i + 1))
      [ $((_i % _every)) -ne 0 ] || _say "等待 Xcode 命令行工具安装完成（已等待 $((_i * _poll / 60)) 分钟）…"
      sleep "$_poll"
    done
    _say "Xcode 命令行工具已安装：$(xcode-select -p)"
  fi

  # 需要 git：Debian / Ubuntu 上先把默认源的域名换成国内镜像（http，不依赖 CA 证书）再安装
  if ! command -v git >/dev/null 2>&1; then
    command -v apt-get >/dev/null 2>&1 || _die "需要 git，请先安装"
    _m=${BOOTSTRAP_APT_MIRROR:-http://mirrors.cloud.tencent.com}
    for _f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources; do
      [ -f "$_f" ] && _root sed -i -E \
        "s#https?://(deb|security)\.debian\.org#$_m#g; s#https?://(archive|security|ports)\.ubuntu\.com#$_m#g" "$_f"
    done
    _say "安装 git（临时源：$_m）"
    _root apt-get update -q
    _root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends git ca-certificates
  fi

  _tmp=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap.XXXXXX")
  chmod 755 "$_tmp" # 之后切换到新用户时仍需读取
  if [ -n "${BOOTSTRAP_REPO:-}" ]; then
    git clone -q "$BOOTSTRAP_REPO" "$_tmp/repo" || _die "clone 失败：$BOOTSTRAP_REPO"
  elif [ "$BOOTSTRAP_SOURCE" = cnb ]; then
    BOOTSTRAP_REPO=$BOOTSTRAP_REPO_CNB
    git clone -q --depth 1 "$BOOTSTRAP_REPO" "$_tmp/repo" || _die "clone 失败：$BOOTSTRAP_REPO"
  else
    # GitHub：此时还没有选源结果，按内置列表（scripts/update-gh-proxies.sh 维护，D-031）依次尝试加速代理，最后才直连
    # （默认国内网络）；跳过重复的候选（P-039）；直连在国内常常卡住，只给 30 秒
    BOOTSTRAP_REPO=$BOOTSTRAP_REPO_GITHUB
    _tried=
    for _p in "${GH_PROXY:-_none_}" https://github.cnxiaobai.com/ https://git.yylx.win/ https://gh.padao.fun/ https://ghproxy.sakuramoe.dev/ ""; do  # @gh-proxies
      [ "$_p" != _none_ ] || continue
      case "$_tried" in *"[$_p]"*) continue ;; esac
      _tried="$_tried[$_p]"
      _say "clone ${_p}$BOOTSTRAP_REPO"
      # macOS 默认没有 timeout 命令
      _to=
      if command -v timeout >/dev/null 2>&1; then
        if [ -z "$_p" ]; then _to="timeout 30"; else _to="timeout 120"; fi
      fi
      if $_to git clone -q --depth 1 "${_p}$BOOTSTRAP_REPO" "$_tmp/repo" 2>/dev/null; then break; fi
      rm -rf "$_tmp/repo"
    done
    [ -d "$_tmp/repo" ] || _die "无法从 GitHub 拉取仓库，可改用 --source cnb"
  fi
  # 之后切换到新用户时仍需读取：不受当前 umask（如 077）影响（P-027）
  chmod -R a+rX "$_tmp/repo"
  export BOOTSTRAP_REPO
  # 不用 exec：结束后删除临时检出（之后以 ~/.local/share/bootstrap 中的检出为准）
  _rc=0
  sh "$_tmp/repo/bootstrap.sh" "$@" || _rc=$?
  rm -rf "$_tmp"
  exit "$_rc"
fi

# ---------------------------------------------------------------------------
# 仓库模式
# ---------------------------------------------------------------------------
BS_SRC=$(bs_self_dir)
. "$BS_SRC/lib/common.sh"
. "$BS_SRC/lib/detect.sh"
. "$BS_SRC/lib/mirrors.sh"
. "$BS_SRC/lib/apt.sh"
. "$BS_SRC/lib/user.sh"
. "$BS_SRC/lib/ssh.sh"
. "$BS_SRC/lib/macos.sh"
. "$BS_SRC/lib/tidy.sh"
. "$BS_SRC/lib/terminfo.sh"
. "$BS_SRC/lib/roles.sh"
. "$BS_SRC/lib/system.sh"
. "$BS_SRC/lib/fonts.sh"
. "$BS_SRC/lib/stage.sh"

BS_MODE=full
BS_STAGE=root
BS_HARDEN_ONLY=
BS_SKIP=${BOOTSTRAP_SKIP:-}
BS_DRY_RUN=
while [ $# -gt 0 ]; do
  case "$1" in
    --dotfiles) BS_MODE=dotfiles ;;
    --source) BOOTSTRAP_SOURCE=$2; shift ;;
    --dir) BOOTSTRAP_DIR=$2; shift ;;
    --env) BOOTSTRAP_ENV=$2; shift ;;
    --harden-ssh) BS_HARDEN_ONLY=1 ;;
    --reprobe) BOOTSTRAP_REPROBE=1 ;;
    --nvim) BOOTSTRAP_NVIM=1 ;;
    --no-nvim) BOOTSTRAP_NVIM=0 ;;
    --skip) BS_SKIP=$2; shift ;;
    --dry-run) BS_DRY_RUN=1 ;;
    --stage) BS_STAGE=$2; shift ;; # 内部使用：root 阶段结束后以新用户身份进入 user 阶段
    -h | --help)
      sed -n '2,/^set -eu/p' "$0" | sed '$d; s/^# \{0,1\}//'
      exit 0
      ;;
    *) bs_die "未知选项：$1（--help 查看用法）" ;;
  esac
  shift
done
export BOOTSTRAP_SOURCE="${BOOTSTRAP_SOURCE:-}" BOOTSTRAP_ENV="${BOOTSTRAP_ENV:-}" BOOTSTRAP_REPROBE="${BOOTSTRAP_REPROBE:-}" BOOTSTRAP_NVIM="${BOOTSTRAP_NVIM:-}"

bs_export_xdg
bootstrap_detect

if [ -n "$BS_HARDEN_ONLY" ]; then
  # 普通用户运行时默认加固当前用户
  [ "$(id -u)" = 0 ] || exec sudo env BOOTSTRAP_USER="${BOOTSTRAP_USER:-$(id -un)}" \
    BOOTSTRAP_HARDEN_SSH="${BOOTSTRAP_HARDEN_SSH:-}" sh "$0" --harden-ssh
  [ -n "${BOOTSTRAP_USER:-}" ] || bs_ask BOOTSTRAP_USER "SSH 加固后用于登录的普通用户名: "
  bs_harden_ssh "$BOOTSTRAP_USER"
  exit 0
fi

case "$BS_STAGE" in
  root) bs_stage_root ;;
  user) bs_stage_user ;;
  *) bs_die "未知阶段：$BS_STAGE" ;;
esac
