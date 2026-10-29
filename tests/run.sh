#!/bin/sh
# tests/run.sh — 在容器中运行 bootstrap（模拟国内网络：屏蔽 GitHub 直连）
#
# 用法：tests/run.sh [镜像] [bootstrap.sh 参数…]
#   TEST_RUNS=2       连续执行次数（第二次用于检查幂等）
#   TEST_KEEP=1       测试后保留容器（名为 bs-test）
#   TEST_ENV="K=V …"  额外传入容器的环境变量
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
img=${1:-debian:13}
[ $# -gt 0 ] && shift
runs=${TEST_RUNS:-2}

block=""
for h in github.com api.github.com raw.githubusercontent.com objects.githubusercontent.com \
  release-assets.githubusercontent.com codeload.github.com; do
  block="$block --add-host $h:0.0.0.0"
done

envs="-e BOOTSTRAP_USER=tester -e BOOTSTRAP_PASSWORD=tester -e BOOTSTRAP_NONINTERACTIVE=1"
for kv in ${TEST_ENV:-}; do envs="$envs -e $kv"; done

# 工作区快照：user 阶段用 git clone 复制仓库，只会带上已提交的内容，因此把当前工作区（含未提交修改）提交到临时仓库
snap=$(mktemp -d)
git -C "$repo" ls-files -coz --exclude-standard | (cd "$repo" && tar --null -T - -cf -) | tar -C "$snap" -xf -
git -C "$snap" init -q -b main
git -C "$snap" add -A
git -C "$snap" -c user.name=test -c user.email=test@localhost commit -qm snapshot
chmod -R a+rX "$snap"

name=bs-test
docker rm -f "$name" >/dev/null 2>&1 || true
# shellcheck disable=SC2086
docker run -d --name "$name" $block $envs -v "$snap:/src:ro" "$img" sleep infinity >/dev/null
trap '[ -n "${TEST_KEEP:-}" ] || docker rm -f "$name" >/dev/null; rm -rf "$snap"' EXIT

i=1
while [ "$i" -le "$runs" ]; do
  echo "######## run $i: $img $*"
  if [ "$i" = 1 ]; then
    docker exec "$name" sh /src/bootstrap.sh "$@"
  else
    # 之后以普通用户、在固定检出中执行（与真实使用一致）
    docker exec -u tester -w /home/tester "$name" sh /home/tester/.local/share/bootstrap/bootstrap.sh "$@"
  fi
  i=$((i + 1))
done

echo "######## checks"
docker exec -u tester -w /home/tester "$name" sh -c '
  set -x
  getent passwd tester | cut -d: -f7
  sudo -n true && echo "sudo nopasswd OK"
  readlink ~/.zshenv ~/.config/zsh ~/.config/mise
  ls ~/.local/state/bootstrap
  cd ~/.local/share/bootstrap && ~/.local/bin/mise -E debian,container bootstrap status 2>&1 | tail -n 30
'
