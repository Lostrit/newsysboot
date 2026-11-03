#!/bin/sh
# tests/run-macos-clt.sh —— 管道模式在 macOS 上等待 Xcode 命令行工具安装（P-038），在 Linux 容器中模拟：
#   uname -s 返回 Darwin；xcode-select -p 前几次失败、之后成功（模拟用户在系统窗口中完成安装）；
#   仓库换成只打印标记的假仓库，确认装好后继续 clone 并进入仓库中的 bootstrap.sh。
# 场景：ok（等待后继续）、timeout（一直未安装，超时退出非零）
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
img=${TEST_IMAGE:-buildpack-deps:bookworm-scm} # 自带 git 与 curl
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/stub" "$work/fake"
cat >"$work/stub/uname" <<'S'
#!/bin/sh
[ "${1:-}" = -s ] && { echo Darwin; exit 0; }
exec /usr/bin/uname "$@"
S
cat >"$work/stub/xcode-select" <<'S'
#!/bin/sh
case "$1" in
  --install) echo called >>/tmp/clt-install; exit 1 ;;
  -p)
    n=$(($(cat /tmp/clt-n 2>/dev/null || echo 0) + 1)); echo "$n" >/tmp/clt-n
    [ "$n" -ge "${CLT_READY_AFTER:-4}" ] && { echo /Library/Developer/CommandLineTools; exit 0; }
    exit 2 ;;
esac
S
chmod +x "$work/stub/uname" "$work/stub/xcode-select"
printf '#!/bin/sh\necho REPO-STAGE-REACHED\n' >"$work/fake/bootstrap.sh"
(cd "$work/fake" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm fake)
chmod -R a+rX "$work"

run() { # <CLT_READY_AFTER> <BS_CLT_TIMEOUT>
  docker run --rm -v "$work/stub:/stub:ro" -v "$work/fake:/src:ro" -v "$repo/bootstrap.sh:/bootstrap.sh:ro" \
    -e PATH=/stub:/usr/local/bin:/usr/bin:/bin -e BOOTSTRAP_REPO=/src -e BOOTSTRAP_SOURCE=github \
    -e BS_CLT_POLL=1 -e BS_CLT_TIMEOUT="$2" -e CLT_READY_AFTER="$1" \
    "$img" sh -c 'cat /bootstrap.sh | sh; echo "EXIT=$?"; echo "install-calls=$(wc -l </tmp/clt-install)"' 2>&1
}

fail=0
out=$(run 4 30)
echo "$out" | grep -q 'Xcode 命令行工具已安装' && echo "$out" | grep -q 'REPO-STAGE-REACHED' && echo "$out" | grep -q 'EXIT=0' &&
  echo "$out" | grep -q 'install-calls=1' && echo "PASS ok：等待安装完成后继续 clone" || { echo "FAIL ok"; echo "$out"; fail=1; }
out=$(run 999 3)
echo "$out" | grep -q '尚未安装完成' && ! echo "$out" | grep -q 'REPO-STAGE-REACHED' && echo "$out" | grep -q 'EXIT=1' &&
  echo "PASS timeout：超时后退出非零，不继续" || { echo "FAIL timeout"; echo "$out"; fail=1; }
out=$(run 1 30)
! echo "$out" | grep -q 'install-calls=1' && echo "$out" | grep -q 'REPO-STAGE-REACHED' &&
  echo "PASS installed：已安装时不触发安装" || { echo "FAIL installed"; echo "$out"; fail=1; }
exit $fail
