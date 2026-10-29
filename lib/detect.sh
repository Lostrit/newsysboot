#!/bin/sh
# lib/detect.sh — 环境检测（POSIX sh，被 bootstrap.sh source，也可以单独执行以打印检测结果）
#
# 输出变量（均以 BOOTSTRAP_ 开头）：
#   OS          linux | macos
#   DISTRO      debian | ubuntu | steamos | <os-release ID> | macos
#   VERSION     发行版版本号（如 13、24.04）
#   CODENAME    发行版代号（如 trixie、noble），没有则为空
#   ARCH        x64 | arm64 | <uname -m>
#   CONTAINER   1 表示运行在容器中（docker / podman / k8s 等）
#   SYSTEMD     1 表示 PID 1 是 systemd（容器中通常为 0）
#   MODULES     要启用的 mise 模块，逗号分隔（可以用 BOOTSTRAP_ENV 覆盖）
#
# 规则：容器中不安装 mihomo 和 Docker（不做 Docker in Docker），使用宿主机的代理。

bootstrap_is_container() {
  [ -f /.dockerenv ] && return 0
  [ -f /run/.containerenv ] && return 0 # podman
  [ -n "${container:-}" ] && return 0   # systemd-nspawn / podman 会设置
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt -cq 2>/dev/null && return 0
  fi
  # cgroup v1 下的 docker / containerd / k8s
  if [ -r /proc/1/cgroup ] && grep -qE '/(docker|containerd|kubepods|lxc)' /proc/1/cgroup 2>/dev/null; then
    return 0
  fi
  return 1
}

bootstrap_detect() {
  BOOTSTRAP_CONTAINER=0
  BOOTSTRAP_SYSTEMD=0
  BOOTSTRAP_CODENAME=

  case "$(uname -s)" in
    Darwin)
      BOOTSTRAP_OS=macos
      BOOTSTRAP_DISTRO=macos
      BOOTSTRAP_VERSION=$(sw_vers -productVersion 2>/dev/null)
      ;;
    Linux)
      BOOTSTRAP_OS=linux
      if [ -r /etc/os-release ]; then
        # 在子 shell 中读取，避免 os-release 中的变量污染当前环境
        BOOTSTRAP_DISTRO=$(. /etc/os-release && printf '%s' "${ID:-unknown}")
        BOOTSTRAP_VERSION=$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")
        BOOTSTRAP_CODENAME=$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}")
      else
        BOOTSTRAP_DISTRO=unknown
        BOOTSTRAP_VERSION=
      fi
      bootstrap_is_container && BOOTSTRAP_CONTAINER=1
      [ -d /run/systemd/system ] && BOOTSTRAP_SYSTEMD=1
      ;;
    *)
      printf 'detect: unsupported OS: %s\n' "$(uname -s)" >&2
      return 1
      ;;
  esac

  case "$(uname -m)" in
    x86_64 | amd64) BOOTSTRAP_ARCH=x64 ;;
    aarch64 | arm64) BOOTSTRAP_ARCH=arm64 ;;
    *) BOOTSTRAP_ARCH=$(uname -m) ;;
  esac

  if [ -n "${BOOTSTRAP_ENV:-}" ]; then
    BOOTSTRAP_MODULES=$BOOTSTRAP_ENV
  else
    case "$BOOTSTRAP_DISTRO" in
      debian | ubuntu)
        if [ "$BOOTSTRAP_CONTAINER" = 1 ]; then
          BOOTSTRAP_MODULES=debian,container
        else
          BOOTSTRAP_MODULES=debian,mihomo,docker
        fi
        ;;
      steamos) BOOTSTRAP_MODULES=steamos,mihomo ;;
      macos) BOOTSTRAP_MODULES=macos,mihomo ;;
      *)
        printf 'detect: unsupported distro: %s\n' "$BOOTSTRAP_DISTRO" >&2
        return 1
        ;;
    esac
  fi

  export BOOTSTRAP_OS BOOTSTRAP_DISTRO BOOTSTRAP_VERSION BOOTSTRAP_CODENAME \
    BOOTSTRAP_ARCH BOOTSTRAP_CONTAINER BOOTSTRAP_SYSTEMD BOOTSTRAP_MODULES
}

# 直接执行时打印检测结果
case "$0" in
  *detect.sh)
    bootstrap_detect || exit 1
    for v in OS DISTRO VERSION CODENAME ARCH CONTAINER SYSTEMD MODULES; do
      eval "printf 'BOOTSTRAP_%s=%s\n' $v \"\${BOOTSTRAP_$v}\""
    done
    ;;
esac
