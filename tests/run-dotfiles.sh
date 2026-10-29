#!/bin/sh
# tests/run-dotfiles.sh — 测试 `bootstrap.sh --dotfiles`（D-009）：已有环境、普通用户、没有 sudo
#
# 用法：tests/run-dotfiles.sh [镜像] [bootstrap.sh 额外参数…]
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
img=${1:-debian:13}
[ $# -gt 0 ] && shift

snap=$(mktemp -d)
git -C "$repo" ls-files -coz --exclude-standard | (cd "$repo" && tar --null -T - -cf -) | tar -C "$snap" -xf -
git -C "$snap" init -q -b main && git -C "$snap" add -A
git -C "$snap" -c user.name=test -c user.email=test@localhost commit -qm snapshot
chmod -R a+rX "$snap"

block=""
for h in github.com api.github.com raw.githubusercontent.com objects.githubusercontent.com \
  release-assets.githubusercontent.com codeload.github.com; do
  block="$block --add-host $h:0.0.0.0"
done
name=bs-test-dot
docker rm -f "$name" >/dev/null 2>&1 || true
# shellcheck disable=SC2086
docker run -d --name "$name" $block -v "$snap:/src:ro" "$img" sleep infinity >/dev/null
trap 'docker rm -f "$name" >/dev/null; rm -rf "$snap"' EXIT

# 预置「已初始化的环境」：git / curl / zsh 已装好，普通用户 dev 没有 sudo
docker exec "$name" sh -c 'sed -i "s#http://deb.debian.org#http://mirrors.cloud.tencent.com#g" /etc/apt/sources.list.d/*.sources 2>/dev/null;
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends git curl ca-certificates zsh >/dev/null && useradd -m dev'

echo "######## --dotfiles as dev"
docker exec -u dev -w /home/dev "$name" sh /src/bootstrap.sh --dotfiles "$@"
echo "######## second run"
docker exec -u dev -w /home/dev "$name" sh /home/dev/.local/share/bootstrap/bootstrap.sh --dotfiles "$@"
echo "######## checks"
docker exec -u dev -w /home/dev "$name" sh -c 'set -x; readlink ~/.zshenv ~/.config/nvim; getent passwd dev | cut -d: -f7; command -v sudo || echo "no sudo (expected)"'
