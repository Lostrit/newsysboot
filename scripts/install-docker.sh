#!/bin/sh
# scripts/install-docker.sh — 用锁定版本的 get-docker.sh 安装 Docker（D-005），并把当前用户加入 docker 组
#
# 由 mise.docker.toml 的 post-packages hook 调用。已安装时只做加组。
# DOWNLOAD_URL 来自 stage-0 的选源结果（BOOTSTRAP_DOCKER_MIRROR，D-006）。
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v docker >/dev/null 2>&1; then
  want=$(cut -d' ' -f1 "$root/vendor/get-docker.sh.sha256")
  got=$(sha256sum <"$root/vendor/get-docker.sh" | cut -d' ' -f1)
  [ "$want" = "$got" ] || {
    echo "install-docker: vendor/get-docker.sh 校验失败" >&2
    exit 1
  }
  echo "install-docker: DOWNLOAD_URL=${BOOTSTRAP_DOCKER_MIRROR:-<官方>}"
  sudo env ${BOOTSTRAP_DOCKER_MIRROR:+DOWNLOAD_URL="$BOOTSTRAP_DOCKER_MIRROR"} sh "$root/vendor/get-docker.sh"
fi

user=$(id -un)
if [ "$user" != root ] && ! id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
  sudo usermod -aG docker "$user"
  echo "install-docker: 已把 $user 加入 docker 组（重新登录后生效）"
fi
