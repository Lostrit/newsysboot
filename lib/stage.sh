#!/bin/sh
# lib/stage.sh — stage-0 的两个阶段
#
#   root 阶段：选源、apt 换源与基础包、root → 普通用户、SSH 加固，然后以普通用户身份进入 user 阶段
#   user 阶段：仓库检出、安装 mise、写入环境、（解密机密）、运行 mise bootstrap

# mise 版本：与 vendor/mise-install.sh 内置的版本一致，安装时只走 CDN（D-012）
bs_mise_version() {
  sed -n 's/^  current_version="v\(.*\)"$/\1/p' "$BS_SRC/vendor/mise-install.sh" | head -n 1
}

bs_is_debian_like() {
  case "$BOOTSTRAP_DISTRO" in debian | ubuntu) return 0 ;; esac
  return 1
}

bs_has_module() {
  case ",$BOOTSTRAP_MODULES," in *,"$1",*) return 0 ;; esac
  return 1
}

# ---------------------------------------------------------------------------
# root 阶段
# ---------------------------------------------------------------------------
bs_stage_root() {
  if [ "$BS_MODE" = dotfiles ]; then
    # 只部署 dotfiles：不改系统，直接以当前用户进入 user 阶段（选源在 user 阶段进行）
    bs_stage_user
    return
  fi

  if [ "$BOOTSTRAP_OS" = linux ] && bs_is_debian_like; then
    bs_apt_ensure_curl
  fi
  bs_have curl || bs_die "需要 curl"

  bs_select_mirrors
  bs_export_mirrors

  if [ "$BOOTSTRAP_OS" = linux ] && bs_is_debian_like; then
    if bs_apt_set_mirror "$BOOTSTRAP_APT_MIRROR" || [ ! -e "$BS_STATE_DIR/apt-updated" ]; then
      bs_apt_update
      mkdir -p "$BS_STATE_DIR" && : >"$BS_STATE_DIR/apt-updated"
    fi
    # user 阶段之前就需要的包（mise 的 apt 包列表在 mise.debian.toml 中）
    bs_apt_install git sudo zsh curl ca-certificates
  fi

  if [ "$(id -u)" != 0 ]; then
    bs_stage_user
    return
  fi

  # ---- 当前是 root：创建普通用户，之后的步骤以该用户运行（D-004）----
  if [ "${BOOTSTRAP_ALLOW_ROOT:-}" = 1 ]; then
    bs_warn "BOOTSTRAP_ALLOW_ROOT=1：以 root 继续（不创建普通用户）"
    bs_stage_user
    return
  fi
  bs_create_user
  if [ "$BOOTSTRAP_CONTAINER" != 1 ] && [ "$BOOTSTRAP_OS" = linux ]; then
    bs_harden_ssh "$BOOTSTRAP_USER"
  fi

  # 把选源结果交给新用户，避免重复测速
  _uhome=$(getent passwd "$BOOTSTRAP_USER" | cut -d: -f6)
  _ustate="$_uhome/.local/state/bootstrap"
  install -d -m 755 -o "$BOOTSTRAP_USER" -g "$(id -gn "$BOOTSTRAP_USER")" \
    "$_uhome/.local" "$_uhome/.local/state" "$_ustate"
  install -m 644 -o "$BOOTSTRAP_USER" -g "$(id -gn "$BOOTSTRAP_USER")" "$BS_STATE_DIR/mirrors.env" "$_ustate/mirrors.env"

  bs_log "切换到用户 $BOOTSTRAP_USER 继续"
  # 新用户需要能读取当前检出（管道模式下位于 /tmp/bootstrap.*，已设为 755）
  exec sudo -u "$BOOTSTRAP_USER" -H env \
    BOOTSTRAP_SOURCE="$BOOTSTRAP_SOURCE" BOOTSTRAP_ENV="$BOOTSTRAP_ENV" \
    BOOTSTRAP_REPO="${BOOTSTRAP_REPO:-}" BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-}" \
    BOOTSTRAP_SKIP="$BS_SKIP" BOOTSTRAP_NONINTERACTIVE="${BOOTSTRAP_NONINTERACTIVE:-}" \
    FNOX_AGE_KEY="${FNOX_AGE_KEY:-}" \
    http_proxy="${http_proxy:-}" https_proxy="${https_proxy:-}" no_proxy="${no_proxy:-}" all_proxy="${all_proxy:-}" \
    sh "$BS_SRC/bootstrap.sh" --stage user ${BS_DRY_RUN:+--dry-run}
}

# ---------------------------------------------------------------------------
# user 阶段
# ---------------------------------------------------------------------------
bs_stage_user() {
  # 选源结果：root 阶段已传入，或在此重新读取缓存
  bs_select_mirrors
  bs_export_mirrors

  bs_ensure_checkout
  bs_ensure_mise
  bs_write_env
  bs_run_mise
}

# 仓库检出到固定位置（D-002：dotfiles 以链接部署，必须指向稳定的检出目录）
bs_ensure_checkout() {
  BOOTSTRAP_DIR=${BOOTSTRAP_DIR:-$XDG_DATA_HOME/bootstrap}
  export BOOTSTRAP_DIR
  if [ "$BS_SRC" = "$BOOTSTRAP_DIR" ] || [ "$(cd "$BS_SRC" && pwd -P)" = "$(cd "$BOOTSTRAP_DIR" 2>/dev/null && pwd -P)" ]; then
    return 0
  fi
  if [ -d "$BOOTSTRAP_DIR/.git" ]; then
    if [ -z "$(git -C "$BOOTSTRAP_DIR" status --porcelain 2>/dev/null)" ]; then
      bs_log "更新仓库 $BOOTSTRAP_DIR"
      git -C "$BOOTSTRAP_DIR" pull -q --ff-only || bs_warn "仓库更新失败，使用现有检出"
    else
      bs_warn "$BOOTSTRAP_DIR 有未提交的修改，跳过更新"
    fi
  else
    bs_log "检出仓库到 $BOOTSTRAP_DIR"
    mkdir -p "$(dirname "$BOOTSTRAP_DIR")"
    # 从当前检出本地克隆（不再走网络），再把 origin 改为远程地址
    # 源检出可能属于 root（管道模式的临时目录），需要放行 safe.directory（P-007）。
    # `git -c safe.directory=*` 对本地 clone 无效（upload-pack 子进程不认），只能用临时的全局配置
    _gc=$(mktemp)
    printf '[safe]\n\tdirectory = *\n' >"$_gc"
    GIT_CONFIG_GLOBAL=$_gc git clone -q "$BS_SRC" "$BOOTSTRAP_DIR"
    rm -f "$_gc"
    if [ -n "${BOOTSTRAP_REPO:-}" ] && [ "$BOOTSTRAP_REPO" != "$BS_SRC" ]; then
      git -C "$BOOTSTRAP_DIR" remote set-url origin "$BOOTSTRAP_REPO"
    fi
  fi
  # 之后的步骤都使用固定检出中的文件
  BS_SRC=$BOOTSTRAP_DIR
}

bs_ensure_mise() {
  _want=$(bs_mise_version)
  export PATH="$HOME/.local/bin:$PATH"
  if bs_have mise; then
    bs_log "mise 已安装：$(mise --version 2>/dev/null | cut -d' ' -f1)"
    return 0
  fi
  [ "$(bs_sha256 <"$BS_SRC/vendor/mise-install.sh")" = "$(cut -d' ' -f1 "$BS_SRC/vendor/mise-install.sh.sha256")" ] ||
    bs_die "vendor/mise-install.sh 校验失败"
  bs_log "安装 mise $_want（CDN：mise.jdx.dev）"
  mkdir -p "$BS_STATE_DIR"
  # 安装脚本的 curl 进度条很长，输出写入日志，失败时再显示
  if ! MISE_VERSION=$_want MISE_QUIET=1 sh "$BS_SRC/vendor/mise-install.sh" >"$BS_STATE_DIR/mise-install.log" 2>&1; then
    cat "$BS_STATE_DIR/mise-install.log" >&2
    bs_die "mise 安装失败"
  fi
  bs_have mise || bs_die "mise 安装失败"
}

# 写入 ~/.local/state/bootstrap/env.sh：~/.zshenv 会读取它（GH_PROXY 等），本脚本也用它驱动 mise
bs_write_env() {
  mkdir -p "$BS_STATE_DIR"
  {
    echo "# 由 bootstrap 生成（lib/stage.sh），~/.zshenv 读取；重新运行 bootstrap.sh 会覆盖"
    bs_env_line BOOTSTRAP_DIR "$BOOTSTRAP_DIR"
    bs_env_line BOOTSTRAP_MODULES "$BOOTSTRAP_MODULES"
    bs_env_line GH_PROXY "$GH_PROXY"
    if [ -n "$GH_PROXY" ]; then
      # mise 的所有 GitHub 下载经加速代理（research R-001）；aqua 的签名校验不受影响
      bs_env_line MISE_URL_REPLACEMENTS "{\"https://github.com/\":\"${GH_PROXY}https://github.com/\",\"https://raw.githubusercontent.com/\":\"${GH_PROXY}https://raw.githubusercontent.com/\"}"
    fi
    # node 从国内镜像下载
    bs_env_line MISE_NODE_MIRROR_URL "${MISE_NODE_MIRROR_URL:-https://mirrors.cloud.tencent.com/nodejs-release/}"
  } >"$BS_STATE_DIR/env.sh"
  . "$BS_STATE_DIR/env.sh"
}

bs_run_mise() {
  cd "$BS_SRC"
  mise trust -q "$BS_SRC/mise.toml"
  for _m in $(printf '%s' "$BOOTSTRAP_MODULES" | tr ',' ' '); do
    [ -f "$BS_SRC/mise.$_m.toml" ] && mise trust -q "$BS_SRC/mise.$_m.toml"
  done

  set -- bootstrap --yes
  [ -n "$BS_DRY_RUN" ] && set -- "$@" --dry-run
  if [ "$BS_MODE" = dotfiles ]; then
    # 只部署用户目录内的内容（D-009）：不加载系统模块。
    # mise 不允许 --only 与 --skip 同时使用，因此从 --only 列表中去掉要跳过的部分
    _only=
    for _p in files dotfiles tools task; do
      case ",$BS_SKIP," in *,"$_p",*) continue ;; esac
      _only="${_only:+$_only,}$_p"
    done
    set -- "$@" --only "$_only"
    _envs=
  else
    [ -n "$BS_SKIP" ] && set -- "$@" --skip "$BS_SKIP"
    _envs=$BOOTSTRAP_MODULES
  fi

  # 需要机密的模块：读取 age 私钥，交给 fnox 注入（D-008）
  if bs_has_module mihomo && [ "$BS_MODE" != dotfiles ] && [ -z "${FNOX_AGE_KEY:-}" ]; then
    bs_ask FNOX_AGE_KEY "请输入 age 私钥（AGE-SECRET-KEY-…，用于解密 mihomo 配置）: " secret
  fi
  export FNOX_AGE_KEY="${FNOX_AGE_KEY:-}"

  bs_log "mise ${_envs:+-E $_envs }$*"
  if [ -n "$FNOX_AGE_KEY" ]; then
    mise install -q fnox
    mise exec fnox -- fnox exec -- mise ${_envs:+-E "$_envs"} "$@"
  else
    mise ${_envs:+-E "$_envs"} "$@"
  fi
  bs_log "完成。新开一个终端（或执行 exec zsh -l）使配置生效。"
}
