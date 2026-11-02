#!/bin/sh
# lib/mirrors.sh — 选源（D-006）：apt、docker-ce、Docker Hub 镜像、GitHub 加速代理
#
# 规则：先探测各家云的内网镜像（短超时，能访问即用）；没有内网时对公网镜像测速，
# 每个候选测 BS_SAMPLES 次，任意一次失败即淘汰，按最慢一次的速度排序（保证稳定）。
# 所有探测都绕过代理（--noproxy '*'），测的是直连质量。
#
# 结果写入 $BS_STATE_DIR/mirrors.env，有效期 BS_MIRRORS_TTL 秒；环境变量可覆盖任一结果：
#   BOOTSTRAP_APT_MIRROR  BOOTSTRAP_DOCKER_MIRROR  BOOTSTRAP_DOCKER_REGISTRY_MIRRORS  GH_PROXY

: "${BS_SAMPLES:=2}"
: "${BS_MIRRORS_TTL:=604800}"

# 各家云的内网镜像（只在对应云内可访问；华为云、火山引擎的域名待在对应云上核实，research R-004）
BS_INTRANET_MIRRORS="http://mirrors.tencentyun.com http://mirrors.cloud.aliyuncs.com http://mirrors.myhuaweicloud.com http://mirrors.ivolces.com"
# 公网镜像（https）
BS_PUBLIC_MIRRORS="https://mirrors.cloud.tencent.com https://mirrors.aliyun.com https://mirrors.huaweicloud.com https://mirrors.volces.com https://mirrors.ustc.edu.cn https://mirrors.tuna.tsinghua.edu.cn"
# Docker Hub 镜像：内网（腾讯云）与公网第三方（research R-009，仅作辅助）
BS_INTRANET_REGISTRIES="https://mirror.ccs.tencentyun.com"
BS_PUBLIC_REGISTRIES="https://docker.1ms.run https://docker.m.daocloud.io"
# GitHub 加速代理（前缀形式，带尾斜杠）；"direct" 表示直连
BS_GH_PROXIES="direct https://gh-proxy.com/ https://ghfast.top/ https://gh.qninq.cn/ https://github.cnxiaobai.com/ https://tvv.tw/ https://gh-proxy.org/"
# GitHub 测速文件：不可变的 release 资源，取前 1MiB 并校验 sha256，防止代理篡改内容
BS_GH_PROBE_URL="https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-linux-amd64.tar.gz"
BS_GH_PROBE_SHA256="75c2d0d2265769452a72f14e9b956b6cc3968d0abd5a19904cb79a9267a117b1"

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

# GitHub：直连与各代理一起测速，直连最快时 GH_PROXY 为空
bs_select_gh_proxy() {
  # 全部失败时放宽超时、只测一次再试（网络繁忙时 10 秒可能不够，P-029）
  _best=$(bs_pick_fastest "$BS_GH_PROBE_URL" 1048576 "$BS_GH_PROBE_SHA256" $BS_GH_PROXIES) ||
    _best=$(BS_PROBE_MAX_TIME=30 BS_SAMPLES=1 bs_pick_fastest "$BS_GH_PROBE_URL" 1048576 "$BS_GH_PROBE_SHA256" $BS_GH_PROXIES) ||
    return 1
  [ "$_best" = direct ] && _best=
  printf '%s\n' "$_best"
}

# 读取缓存（同一发行版且未过期）或重新探测；结果导出为环境变量
bs_select_mirrors() {
  _cache="$BS_STATE_DIR/mirrors.env"
  _key="$BOOTSTRAP_DISTRO-$BOOTSTRAP_CODENAME-$BOOTSTRAP_ARCH"
  # 从 env.sh 继承来的 GH_PROXY 是上次生成的结果，不是用户指定（P-028）
  if [ -n "${BOOTSTRAP_GENERATED_GH_PROXY+x}" ] && [ "${GH_PROXY-}" = "$BOOTSTRAP_GENERATED_GH_PROXY" ]; then
    unset GH_PROXY
  fi
  if [ -z "${BOOTSTRAP_REPROBE:-}" ] && [ -r "$_cache" ]; then
    _ts=$(sed -n "s/^export BS_MIRRORS_TS='\(.*\)'$/\1/p" "$_cache")
    _ck=$(sed -n "s/^export BS_MIRRORS_KEY='\(.*\)'$/\1/p" "$_cache")
    if [ "$_ck" = "$_key" ] && [ $(($(date +%s) - ${_ts:-0})) -lt "$BS_MIRRORS_TTL" ]; then
      bs_log "使用缓存的选源结果：$_cache（BOOTSTRAP_REPROBE=1 可重新测速）"
      _keep_apt=${BOOTSTRAP_APT_MIRROR-}
      _keep_docker=${BOOTSTRAP_DOCKER_MIRROR-}
      _keep_reg=${BOOTSTRAP_DOCKER_REGISTRY_MIRRORS-}
      _keep_gh=${GH_PROXY-__unset__}
      . "$_cache"
      [ -n "$_keep_apt" ] && BOOTSTRAP_APT_MIRROR=$_keep_apt
      [ -n "$_keep_docker" ] && BOOTSTRAP_DOCKER_MIRROR=$_keep_docker
      [ -n "$_keep_reg" ] && BOOTSTRAP_DOCKER_REGISTRY_MIRRORS=$_keep_reg
      [ "$_keep_gh" != __unset__ ] && GH_PROXY=$_keep_gh
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
  if [ -z "${GH_PROXY+x}" ]; then
    GH_PROXY=$(bs_select_gh_proxy) || {
      bs_warn "GitHub 直连和所有加速代理都不可用"
      GH_PROXY=
    }
  fi

  mkdir -p "$BS_STATE_DIR"
  {
    bs_env_line BS_MIRRORS_TS "$(date +%s)"
    bs_env_line BS_MIRRORS_KEY "$_key"
    bs_env_line BOOTSTRAP_APT_MIRROR "${BOOTSTRAP_APT_MIRROR:-}"
    bs_env_line BOOTSTRAP_DOCKER_MIRROR "${BOOTSTRAP_DOCKER_MIRROR:-}"
    bs_env_line BOOTSTRAP_DOCKER_REGISTRY_MIRRORS "${BOOTSTRAP_DOCKER_REGISTRY_MIRRORS:-}"
    bs_env_line GH_PROXY "$GH_PROXY"
  } >"$_cache"
}

bs_export_mirrors() {
  export BOOTSTRAP_APT_MIRROR="${BOOTSTRAP_APT_MIRROR:-}" \
    BOOTSTRAP_DOCKER_MIRROR="${BOOTSTRAP_DOCKER_MIRROR:-}" \
    BOOTSTRAP_DOCKER_REGISTRY_MIRRORS="${BOOTSTRAP_DOCKER_REGISTRY_MIRRORS:-}" \
    GH_PROXY="${GH_PROXY:-}"
  bs_log "apt: ${BOOTSTRAP_APT_MIRROR:-<默认>}  docker-ce: ${BOOTSTRAP_DOCKER_MIRROR:-<不适用>}  registry: ${BOOTSTRAP_DOCKER_REGISTRY_MIRRORS:-<无>}  GH_PROXY: ${GH_PROXY:-<直连>}"
}
