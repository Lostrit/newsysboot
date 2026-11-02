#!/bin/sh
# tests/run-pipe.sh — 测试管道模式（`curl … | sh` 的入口）：全新容器、没有 git、没有终端、不设置 BOOTSTRAP_NONINTERACTIVE
#
# 用法：tests/run-pipe.sh [镜像] [bootstrap.sh 参数…]
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
img=${1:-ubuntu:24.04}
[ $# -gt 0 ] && shift

snap=$(mktemp -d)
trap 'rm -rf "$snap"' EXIT
git -C "$repo" ls-files -coz --exclude-standard | (cd "$repo" && tar --null -T - -cf -) | tar -C "$snap" -xf -
git -C "$snap" init -q -b main && git -C "$snap" add -A
git -C "$snap" -c user.name=test -c user.email=test@localhost commit -qm snapshot
chmod -R a+rX "$snap"

block=""
for h in github.com api.github.com raw.githubusercontent.com objects.githubusercontent.com \
  release-assets.githubusercontent.com codeload.github.com; do
  block="$block --add-host $h:0.0.0.0"
done
# umask 077：root 的 umask 收紧时，新用户仍需能读取临时检出（P-027）
# shellcheck disable=SC2086
docker run --rm $block -v "$snap:/src:ro" -e BOOTSTRAP_REPO=/src -e BOOTSTRAP_USER=tester -e BOOTSTRAP_PASSWORD=tester \
  "$img" sh -c 'umask 077; cat /src/bootstrap.sh | sh -s -- "$@" && su tester -c "set -x; readlink ~/.zshenv; getent passwd tester | cut -d: -f7"' sh "$@"
