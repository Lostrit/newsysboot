#!/bin/sh
# lib/mirrors.sh — 选源（D-006）：apt、docker-ce、Docker Hub 镜像、GitHub 加速代理
#
# 规则：先探测各家云的内网镜像（短超时，能访问即用）；没有内网时对公网镜像测速，
# 每个候选测 BS_SAMPLES 次，任意一次失败即淘汰，按最慢一次的速度排序（保证稳定）。
# 所有探测都绕过代理（--noproxy '*'），测的是直连质量。
#
# 结果写入 $BS_STATE_DIR/mirrors.env，有效期 BS_MIRRORS_TTL 秒；环境变量可覆盖任一结果：
#   BOOTSTRAP_APT_MIRROR  BOOTSTRAP_DOCKER_MIRROR  BOOTSTRAP_DOCKER_REGISTRY_MIRRORS  GH_PROXY  GH_PROXY_BACKUP

: "${BS_SAMPLES:=2}"
: "${BS_MIRRORS_TTL:=604800}"

# 各家云的内网镜像（只在对应云内可访问；华为云、火山引擎的域名待在对应云上核实，research R-004）
BS_INTRANET_MIRRORS="http://mirrors.tencentyun.com http://mirrors.cloud.aliyuncs.com http://mirrors.myhuaweicloud.com http://mirrors.ivolces.com"
# 公网镜像（https）
BS_PUBLIC_MIRRORS="https://mirrors.cloud.tencent.com https://mirrors.aliyun.com https://mirrors.huaweicloud.com https://mirrors.volces.com https://mirrors.ustc.edu.cn https://mirrors.tuna.tsinghua.edu.cn"
# Docker Hub 镜像：内网（腾讯云）与公网第三方（research R-009，仅作辅助）
BS_INTRANET_REGISTRIES="https://mirror.ccs.tencentyun.com"
BS_PUBLIC_REGISTRIES="https://docker.1ms.run https://docker.m.daocloud.io"
# GitHub 加速代理（前缀形式，带尾斜杠）：候选来自 lib/gh-proxies.txt（由 scripts/update-gh-proxies.sh 从
# https://github.xxlab.tech/ 收集并逐项验证后生成，D-031）；文件缺失时使用下面的内置列表
BS_GH_PROXIES_BUILTIN="https://github.cnxiaobai.com/ https://git.yylx.win/ https://gh.padao.fun/ https://ghproxy.sakuramoe.dev/"
# 部署时：先对全部候选测延时，再对延时最低的 BS_GH_FINALISTS 个做完整的真实测试
: "${BS_GH_FINALISTS:=5}"
# GitHub 测速文件：不可变的 release 资源，取前 1MiB 并校验 sha256，防止代理篡改内容
BS_GH_PROBE_URL="https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-linux-amd64.tar.gz"
BS_GH_PROBE_SHA256="75c2d0d2265769452a72f14e9b956b6cc3968d0abd5a19904cb79a9267a117b1"
# 部署链路用到的 GitHub 获取方式，所选代理必须全部支持（D-031）：
#   release —— mihomo、mise 的 aqua / github 工具、Mason、blink.cmp（上面的测速文件）
#   raw     —— raw.githubusercontent.com 文件（eza 补全）
#   archive —— github.com/<repo>/archive/<rev>.tar.gz（treesitter 语法解析器源码）
#   clone   —— git 智能 HTTP（本仓库、zsh 插件、lazy.nvim 插件）
BS_GH_RAW_URL="https://raw.githubusercontent.com/eza-community/eza/v0.23.5/completions/zsh/_eza"
BS_GH_RAW_SHA256="251d3f3059fe6dbe17a14f55250b554ffa85ad7939e7a55720ff61a9747aff1e"
BS_GH_ARCHIVE_URL="https://github.com/romkatv/zsh-defer/archive/53a26e287fbbe2dcebb3aa1801546c6de32416fa.tar.gz"
BS_GH_ARCHIVE_FILE="zsh-defer-53a26e287fbbe2dcebb3aa1801546c6de32416fa/zsh-defer.plugin.zsh"
BS_GH_CLONE_URL="https://github.com/romkatv/zsh-defer.git"
BS_GH_CLONE_FILE="zsh-defer.plugin.zsh"

# 候选列表：lib/gh-proxies.txt 中每行第一列（# 开头为注释）
bs_gh_candidates() {
  _gf="${BS_SRC:-.}/lib/gh-proxies.txt"
  if [ -r "$_gf" ]; then
    sed -n 's/^\(https:[^[:space:]#]*\).*/\1/p' "$_gf"
  else
    printf '%s\n' $BS_GH_PROXIES_BUILTIN
  fi
}

# bs_gh_latency <前缀>：首字节时间（毫秒）；连不上不输出
bs_gh_latency() {
  _t=$(curl -s --noproxy '*' --connect-timeout 3 -m 5 -o /dev/null -w '%{http_code} %{time_starttransfer}' "$1" 2>/dev/null) || return 0
  case "$_t" in 000*) return 0 ;; esac
  awk -v t="${_t#* }" 'BEGIN { printf "%d\n", t * 1000 }'
}

# bs_gh_test <前缀>：对部署链路用到的全部获取方式做真实请求（直连代理，不经环境中的代理）。
# 全部通过时输出 release 下载速度（B/s）；任一失败返回 1，并在 stderr 说明哪一项失败
bs_gh_test() {
  _p=$1
  _d=$(mktemp -d)
  _fail=
  _sp=$(bs_score "$_p$BS_GH_PROBE_URL" 1048576 "$BS_GH_PROBE_SHA256")
  [ -n "$_sp" ] || _fail="$_fail release"
  if [ -z "$_fail" ]; then
    curl -fsSL --noproxy '*' --connect-timeout 5 -m 20 -o "$_d/raw" "$_p$BS_GH_RAW_URL" 2>/dev/null &&
      [ "$(bs_sha256 <"$_d/raw")" = "$BS_GH_RAW_SHA256" ] || _fail="$_fail raw"
  fi
  if [ -z "$_fail" ]; then
    curl -fsSL --noproxy '*' --connect-timeout 5 -m 30 -o "$_d/a.tgz" "$_p$BS_GH_ARCHIVE_URL" 2>/dev/null &&
      tar -tzf "$_d/a.tgz" 2>/dev/null | grep -qx "$BS_GH_ARCHIVE_FILE" || _fail="$_fail archive"
  fi
  if [ -z "$_fail" ]; then
    _to=
    command -v timeout >/dev/null 2>&1 && _to="timeout 60"
    env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY GIT_TERMINAL_PROMPT=0 \
      $_to git -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=15 clone -q --depth 1 "$_p$BS_GH_CLONE_URL" "$_d/clone" \
      >/dev/null 2>&1 && [ -f "$_d/clone/$BS_GH_CLONE_FILE" ] || _fail="$_fail clone"
  fi
  rm -rf "$_d"
  if [ -n "$_fail" ]; then
    printf '%s 不支持 / 失败：%s\n' "$_p" "$_fail" >&2
    return 1
  fi
  printf '%s\n' "$_sp"
}

# bs_fetch_ok <url> [max_time]：能在短时间内拿到 2xx 即成功（用于内网探测）
bs_fetch_ok() {
  _code=$(curl -s --noproxy '*' --connect-timeout 1 -m "${2:-3}" -o /dev/null -w '%{http_code}' "$1" 2>/dev/null) || _code=000
  case "$_code" in 2??) return 0 ;; esac
  return 1
}

# bs_speed <url> <bytes> [sha256]：下载前 <bytes> 字节，输出速度（B/s，整数）；失败不输出
bs_speed() {
  _tmp=$(mktemp)
  _out=$(curl -sL --noproxy '*' --connect-timeout 3 -m "${BS_PROBE_MAX_TIME:-10}" -r "0-$(($2 - 1))" -o "$_tmp" \
    -w '%{http_code} %{size_download} %{speed_download}' "$1" 2>/dev/null) || _out="000 0 0"
  set -- "$1" "$2" "${3:-}" $_out
  if [ "$4" = 206 ] || [ "$4" = 200 ]; then
    if [ "$5" -gt 0 ] && { [ -z "$3" ] || [ "$(bs_sha256 <"$_tmp")" = "$3" ]; }; then
      printf '%s\n' "${6%.*}"
    fi
  fi
  rm -f "$_tmp"
}

# bs_score <url> <bytes> [sha256]：测 BS_SAMPLES 次，输出最慢一次的速度；任意一次失败不输出
bs_score() {
  _min=
  _i=0
  while [ "$_i" -lt "$BS_SAMPLES" ]; do
    _s=$(bs_speed "$@")
    [ -n "$_s" ] || return 0
    if [ -z "$_min" ] || [ "$_s" -lt "$_min" ]; then _min=$_s; fi
    _i=$((_i + 1))
  done
  printf '%s\n' "$_min"
}

# bs_pick_fastest <路径后缀> <bytes> <sha256|""> <候选...>：并行测速，输出最快的候选
# 候选 "direct" 表示不加前缀（用于 GitHub 代理）
bs_pick_fastest() {
  _suffix=$1
  _bytes=$2
  _sha=$3
  shift 3
  _dir=$(mktemp -d)
  _n=0
  for _c in "$@"; do
    _n=$((_n + 1))
    (
      _base=$_c
      [ "$_c" = direct ] && _base=
      _sc=$(bs_score "$_base$_suffix" "$_bytes" "$_sha")
      [ -n "$_sc" ] && printf '%s %s\n' "$_sc" "$_c" >"$_dir/$_n"
    ) &
  done
  wait
  _best=$(cat "$_dir"/* 2>/dev/null | sort -rn | head -n 1)
  if [ -n "${BS_DEBUG:-}" ]; then cat "$_dir"/* 2>/dev/null | sort -rn | sed 's/^/  speed /' >&2; fi
  rm -rf "$_dir"
  [ -n "$_best" ] && printf '%s\n' "${_best#* }"
}

# 发行版在镜像站上的目录（Ubuntu 的非 x86 架构在 ubuntu-ports）
bs_apt_path() {
  case "$BOOTSTRAP_DISTRO" in
    ubuntu) [ "$BOOTSTRAP_ARCH" = x64 ] && echo ubuntu || echo ubuntu-ports ;;
    *) echo "$BOOTSTRAP_DISTRO" ;;
  esac
}

bs_deb_arch() {
  case "$BOOTSTRAP_ARCH" in x64) echo amd64 ;; *) echo "$BOOTSTRAP_ARCH" ;; esac
}

bs_select_apt_mirror() {
  _p=$(bs_apt_path)
  for _m in $BS_INTRANET_MIRRORS; do
    if bs_fetch_ok "$_m/$_p/dists/$BOOTSTRAP_CODENAME/Release"; then
      echo "$_m"
      return 0
    fi
  done
  bs_pick_fastest "/$_p/dists/$BOOTSTRAP_CODENAME/main/binary-$(bs_deb_arch)/Packages.xz" 524288 "" $BS_PUBLIC_MIRRORS
}

bs_select_docker_mirror() {
  # docker-ce 只有 debian / ubuntu 两个目录
  _d=$BOOTSTRAP_DISTRO
  for _m in $BS_INTRANET_MIRRORS; do
    if bs_fetch_ok "$_m/docker-ce/linux/$_d/gpg"; then
      echo "$_m/docker-ce"
      return 0
    fi
  done
  _best=$(bs_pick_fastest "/docker-ce/linux/$_d/dists/$BOOTSTRAP_CODENAME/stable/binary-$(bs_deb_arch)/Packages" 262144 "" $BS_PUBLIC_MIRRORS) || return 1
  echo "$_best/docker-ce"
}

# Docker Hub 镜像：内网可用时只用内网；否则列出可访问的公网镜像（最多 2 个，按延迟排序）
bs_select_registry_mirrors() {
  for _r in $BS_INTRANET_REGISTRIES; do
    if bs_fetch_ok "$_r/v2/"; then
      echo "$_r"
      return 0
    fi
  done
  for _r in $BS_PUBLIC_REGISTRIES; do
    # registry 的 /v2/ 返回 200 或 401（认证质询）都表示在线
    _o=$(curl -s --noproxy '*' --connect-timeout 2 -m 4 -o /dev/null -w '%{http_code} %{time_total}' "$_r/v2/" 2>/dev/null) || continue
    case "${_o% *}" in 200 | 401) printf '%s %s\n' "${_o#* }" "$_r" ;; esac
  done | sort -n | head -n 2 | cut -d' ' -f2 | paste -sd, -
}

# GitHub：选出主代理与备用代理（D-031、D-033）。输出一行「主代理 备用代理」（备用代理可能没有）
bs_select_gh_proxy() {
  # 1. 全部候选并行测延时，取最低的 BS_GH_FINALISTS 个
  _gd=$(mktemp -d)
  _n=0
  for _c in $(bs_gh_candidates); do
    _n=$((_n + 1))
    ( _l=$(bs_gh_latency "$_c"); [ -z "$_l" ] || printf '%s %s\n' "$_l" "$_c" >"$_gd/$_n" ) &
  done
  wait
  _finalists=$(cat "$_gd"/* 2>/dev/null | sort -n | head -n "$BS_GH_FINALISTS" | cut -d' ' -f2)
  rm -rf "$_gd"
  # 2. 依次对入围者做真实请求测试（release / raw / archive / clone），全部通过者按 release 下载速度排序，
  #    最快的为主代理，第二快的为备用代理（主代理在部署中途被限流或失效时使用）
  _ok=
  for _c in $_finalists; do
    _sp=$(bs_gh_test "$_c" 2>/dev/null) || continue
    _ok="$_ok$_sp $_c
"
  done
  [ -n "$_ok" ] || return 1
  printf '%s' "$_ok" | sort -rn | head -n 2 | cut -d' ' -f2 | paste -sd' ' -
}

# 读取缓存（同一发行版且未过期）或重新探测；结果导出为环境变量
bs_select_mirrors() {
  _cache="$BS_STATE_DIR/mirrors.env"
  _key="$BOOTSTRAP_DISTRO-$BOOTSTRAP_CODENAME-$BOOTSTRAP_ARCH"
  # 从 env.sh 继承来的 GH_PROXY 是上次生成的结果，不是用户指定（P-028）
  if [ -n "${BOOTSTRAP_GENERATED_GH_PROXY+x}" ] && [ "${GH_PROXY-}" = "$BOOTSTRAP_GENERATED_GH_PROXY" ]; then
    unset GH_PROXY GH_PROXY_BACKUP
  fi
  if [ -n "${BOOTSTRAP_GENERATED_GH_PROXY_BACKUP+x}" ] && [ "${GH_PROXY_BACKUP-}" = "$BOOTSTRAP_GENERATED_GH_PROXY_BACKUP" ]; then
    unset GH_PROXY_BACKUP
  fi
  if [ -z "${BOOTSTRAP_REPROBE:-}" ] && [ -r "$_cache" ]; then
    _ts=$(sed -n "s/^export BS_MIRRORS_TS='\(.*\)'$/\1/p" "$_cache")
    _ck=$(sed -n "s/^export BS_MIRRORS_KEY='\(.*\)'$/\1/p" "$_cache")
    if [ "$_ck" = "$_key" ] && [ $(($(date +%s) - ${_ts:-0})) -lt "$BS_MIRRORS_TTL" ]; then
      bs_log "使用缓存的选源结果：${_cache}（BOOTSTRAP_REPROBE=1 可重新测速）"
      _keep_apt=${BOOTSTRAP_APT_MIRROR-}
      _keep_docker=${BOOTSTRAP_DOCKER_MIRROR-}
      _keep_reg=${BOOTSTRAP_DOCKER_REGISTRY_MIRRORS-}
      _keep_gh=${GH_PROXY-__unset__}
      _keep_ghb=${GH_PROXY_BACKUP-}
      . "$_cache"
      [ -n "$_keep_apt" ] && BOOTSTRAP_APT_MIRROR=$_keep_apt
      [ -n "$_keep_docker" ] && BOOTSTRAP_DOCKER_MIRROR=$_keep_docker
      [ -n "$_keep_reg" ] && BOOTSTRAP_DOCKER_REGISTRY_MIRRORS=$_keep_reg
      # 用户指定了 GH_PROXY：备用代理也只用用户指定的（没有就不用）
      [ "$_keep_gh" != __unset__ ] && GH_PROXY=$_keep_gh GH_PROXY_BACKUP=$_keep_ghb
      # 缓存中没有 GitHub 加速代理（上次选择被推迟，P-040）：有 git 时补选并写入缓存
      BS_GH_PENDING=
      if [ -z "${GH_PROXY+x}" ]; then
        BS_GH_PENDING=1
        bs_select_gh_proxy_pending
      fi
      return 0
    fi
  fi

  bs_log "选源测速中（内网优先，其次公网测速）…"
  if [ "$BOOTSTRAP_OS" = linux ]; then
    case "$BOOTSTRAP_DISTRO" in
      debian | ubuntu)
        [ -n "${BOOTSTRAP_APT_MIRROR:-}" ] || BOOTSTRAP_APT_MIRROR=$(bs_select_apt_mirror) || true
        [ -n "$BOOTSTRAP_APT_MIRROR" ] || bs_warn "没有可用的 apt 镜像，保留系统默认源"
        case ",$BOOTSTRAP_MODULES," in
          *,docker,*)
            [ -n "${BOOTSTRAP_DOCKER_MIRROR:-}" ] || BOOTSTRAP_DOCKER_MIRROR=$(bs_select_docker_mirror) || true
            [ -n "${BOOTSTRAP_DOCKER_REGISTRY_MIRRORS:-}" ] || BOOTSTRAP_DOCKER_REGISTRY_MIRRORS=$(bs_select_registry_mirrors) || true
            ;;
        esac
        ;;
    esac
  fi
  BS_GH_PENDING=
  if [ -z "${GH_PROXY+x}" ]; then
    if bs_have git; then
      bs_select_gh_proxy_now
    else
      # clone 测试需要 git：root 阶段装好基础包后再选（bs_select_gh_proxy_pending，P-040）
      BS_GH_PENDING=1
    fi
  fi

  mkdir -p "$BS_STATE_DIR"
  {
    bs_env_line BS_MIRRORS_TS "$(date +%s)"
    bs_env_line BS_MIRRORS_KEY "$_key"
    bs_env_line BOOTSTRAP_APT_MIRROR "${BOOTSTRAP_APT_MIRROR:-}"
    bs_env_line BOOTSTRAP_DOCKER_MIRROR "${BOOTSTRAP_DOCKER_MIRROR:-}"
    bs_env_line BOOTSTRAP_DOCKER_REGISTRY_MIRRORS "${BOOTSTRAP_DOCKER_REGISTRY_MIRRORS:-}"
    [ -n "$BS_GH_PENDING" ] || { bs_env_line GH_PROXY "$GH_PROXY"; bs_env_line GH_PROXY_BACKUP "${GH_PROXY_BACKUP:-}"; }
  } >"$_cache"
}

bs_select_gh_proxy_now() {
  if _sel=$(bs_select_gh_proxy); then
    GH_PROXY=${_sel%% *}
    GH_PROXY_BACKUP=
    case "$_sel" in *' '*) GH_PROXY_BACKUP=${_sel#* } ;; esac
    [ -n "$GH_PROXY_BACKUP" ] || bs_warn "WARNING: 只有一个完整可用的 GitHub 加速代理（${GH_PROXY}），没有备用代理"
  else
    bs_warn "WARNING: 没有完整可用的 GitHub 加速代理，GitHub 下载将直连（国内可能很慢或失败）"
    GH_PROXY= GH_PROXY_BACKUP=
  fi
}

# 选源时还没有 git（无法测试 clone）的情况：装好 git 后再选择 GitHub 加速代理，并补写进缓存
bs_select_gh_proxy_pending() {
  [ -n "${BS_GH_PENDING:-}" ] || return 0
  bs_have git || return 0
  BS_GH_PENDING=
  bs_log "选择 GitHub 加速代理（测延时与 release / raw / archive / clone）…"
  bs_select_gh_proxy_now
  [ -w "$BS_STATE_DIR/mirrors.env" ] &&
    { bs_env_line GH_PROXY "$GH_PROXY"; bs_env_line GH_PROXY_BACKUP "$GH_PROXY_BACKUP"; } >>"$BS_STATE_DIR/mirrors.env"
  export GH_PROXY GH_PROXY_BACKUP
  bs_log "GH_PROXY: ${GH_PROXY:-<直连>}  备用：${GH_PROXY_BACKUP:-<无>}"
}

bs_export_mirrors() {
  export BOOTSTRAP_APT_MIRROR="${BOOTSTRAP_APT_MIRROR:-}" \
    BOOTSTRAP_DOCKER_MIRROR="${BOOTSTRAP_DOCKER_MIRROR:-}" \
    BOOTSTRAP_DOCKER_REGISTRY_MIRRORS="${BOOTSTRAP_DOCKER_REGISTRY_MIRRORS:-}" \
    GH_PROXY="${GH_PROXY:-}" GH_PROXY_BACKUP="${GH_PROXY_BACKUP:-}"
  if [ -n "${BS_GH_PENDING:-}" ]; then _ghs="<装好 git 后选择>"; else _ghs="${GH_PROXY:-<直连>}  备用：${GH_PROXY_BACKUP:-<无>}"; fi
  bs_log "apt: ${BOOTSTRAP_APT_MIRROR:-<默认>}  docker-ce: ${BOOTSTRAP_DOCKER_MIRROR:-<不适用>}  registry: ${BOOTSTRAP_DOCKER_REGISTRY_MIRRORS:-<无>}  GH_PROXY: $_ghs"
}
