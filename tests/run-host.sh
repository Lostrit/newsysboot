#!/bin/sh
# tests/run-host.sh — 在带 systemd 的特权容器中按「主机」测试：mihomo、docker、SSH 加固（阶段 3）
#
# 默认使用测试专用的 age 密钥与假节点（不接触真实私钥）：快照中的 fnox.toml 会被替换。
# 假节点无法代理，因此测试的是「mihomo 不可用 → 继续使用 GH_PROXY」的分支。
# 要用真实节点测试代理切换：TEST_REAL_SECRETS=1，并由调用者自己在环境中提供 FNOX_AGE_KEY。
#
# TEST_SUDO_USER=1：模拟「已有 sudo 普通用户」的云主机（如腾讯云 Ubuntu 的 ubuntu 用户）：预先创建免密 sudo 的
# tester 并复制 root 的公钥，全程以 tester 运行（不新建用户，对 tester 执行 SSH 加固，D-025）。
#
# 用法：tests/run-host.sh [bootstrap.sh 参数…]    （TEST_RUNS=2  TEST_KEEP=1  TEST_SUDO_USER=1）
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
runs=${TEST_RUNS:-2}
docker image inspect bs-systemd:debian13 >/dev/null 2>&1 || docker build -q -t bs-systemd:debian13 "$repo/tests/systemd"

snap=$(mktemp -d)
git -C "$repo" ls-files -coz --exclude-standard | (cd "$repo" && tar --null -T - -cf -) | tar -C "$snap" -xf -

if [ "${TEST_REAL_SECRETS:-}" = 1 ]; then
  [ -n "${FNOX_AGE_KEY:-}" ] || { echo "TEST_REAL_SECRETS=1 需要在环境中提供 FNOX_AGE_KEY" >&2; exit 1; }
else
  # 测试密钥 + 假节点（127.0.0.2:9 不存在服务）
  keydir=$(mktemp -d)
  (cd "$repo" && mise exec age -- age-keygen -o "$keydir/key.txt") 2>/dev/null
  pub=$(sed -n 's/^# public key: //p' "$keydir/key.txt")
  printf '[providers.age]\ntype = "age"\nrecipients = ["%s"]\n' "$pub" >"$snap/fnox.toml"
  printf 'proxies:\n  - name: test-dummy\n    type: socks5\n    server: 127.0.0.2\n    port: 9\n' |
    (cd "$snap" && mise exec fnox -- fnox set MIHOMO_PROXIES --provider age >/dev/null)
  FNOX_AGE_KEY=$(grep '^AGE-SECRET-KEY-' "$keydir/key.txt")
  export FNOX_AGE_KEY
  rm -rf "$keydir"
fi

git -C "$snap" init -q -b main && git -C "$snap" add -A
git -C "$snap" -c user.name=test -c user.email=test@localhost commit -qm snapshot
chmod -R a+rX "$snap"

block=""
for h in github.com api.github.com raw.githubusercontent.com objects.githubusercontent.com \
  release-assets.githubusercontent.com codeload.github.com; do
  block="$block --add-host $h:0.0.0.0"
done

name=bs-test-host
docker rm -f -v "$name" >/dev/null 2>&1 || true
# /var/lib/docker 用匿名卷：容器内的 dockerd 不能在 overlay 上再叠 overlay
# shellcheck disable=SC2086
docker run -d --name "$name" --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /run/lock -v /var/lib/docker $block -v "$snap:/src:ro" bs-systemd:debian13 >/dev/null
trap '[ -n "${TEST_KEEP:-}" ] || docker rm -f -v "$name" >/dev/null; rm -rf "$snap"' EXIT
i=0
until docker exec "$name" systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'; do
  i=$((i + 1)); [ "$i" -lt 60 ] || { echo "systemd 未启动" >&2; exit 1; }; sleep 1
done

# FNOX_AGE_KEY 只通过 -e（不带值，取自当前环境）传入，不出现在命令行
envs="-e BOOTSTRAP_USER=tester -e BOOTSTRAP_PASSWORD=tester -e BOOTSTRAP_NONINTERACTIVE=1 -e BOOTSTRAP_ASSUME_HOST=1 -e BOOTSTRAP_HARDEN_SSH=1 -e FNOX_AGE_KEY"
if [ "${TEST_SUDO_USER:-}" = 1 ]; then
  docker exec "$name" sh -c '
    # 云主机镜像自带 sudo；测试镜像没有，临时经国内镜像安装（之后恢复默认源，与真实环境一致）
    f=/etc/apt/sources.list.d/debian.sources
    sed -i "s#http://deb.debian.org#http://mirrors.cloud.tencent.com#g" $f
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo >/dev/null
    sed -i "s#http://mirrors.cloud.tencent.com#http://deb.debian.org#g" $f
    useradd -m -s /bin/bash -G sudo tester
    echo "tester ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/90-cloud-init-users && chmod 440 /etc/sudoers.d/90-cloud-init-users
    install -d -m 700 -o tester -g tester /home/tester/.ssh
    install -m 600 -o tester -g tester /root/.ssh/authorized_keys /home/tester/.ssh/authorized_keys'
fi

n=1
while [ "$n" -le "$runs" ]; do
  echo "######## run $n"
  if [ "${TEST_SUDO_USER:-}" = 1 ]; then
    # shellcheck disable=SC2086
    docker exec $envs -u tester -w /home/tester "$name" sh /src/bootstrap.sh "$@"
  elif [ "$n" = 1 ]; then
    # shellcheck disable=SC2086
    docker exec $envs "$name" sh /src/bootstrap.sh "$@"
  else
    # shellcheck disable=SC2086
    docker exec $envs -u tester -w /home/tester "$name" sh /home/tester/.local/share/bootstrap/bootstrap.sh "$@"
  fi
  n=$((n + 1))
done

# 日常重新应用：经 zsh（~/.zshenv 会读取 env.sh，继承上次生成的 GH_PROXY / 代理变量）运行 --dotfiles，
# 之后的 env.sh 检查验证代理设置没有丢失（P-028）
echo "######## --dotfiles via zsh"
docker exec -u tester -w /home/tester -e BOOTSTRAP_ASSUME_HOST=1 "$name" zsh -c 'sh ~/.local/share/bootstrap/bootstrap.sh --dotfiles' |
  grep -E '==>|ERROR' || true

echo "######## checks"
docker exec -e TEST_REAL_SECRETS="${TEST_REAL_SECRETS:-}" "$name" sh -c '
  fail=0
  check() { if eval "$2" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
  st=/home/tester/.local/state/bootstrap
  check "terminfo xterm-ghostty"         "TERM=xterm-ghostty tput colors | grep -qx 256"
  check "role host, no disabled tools"   "grep -q \"^export BOOTSTRAP_ROLE=.host.\\\$\" $st/env.sh && grep -q \"^export MISE_DISABLE_TOOLS=..\\\$\" $st/env.sh"
  check "locale zh_CN + timezone"        "locale -a | grep -qix zh_CN.utf8 && grep -qx LANG=zh_CN.UTF-8 /etc/default/locale && readlink /etc/localtime | grep -q Asia/Shanghai"
  check "host tools: jq gh btop fnox age" "su - tester -c \"zsh -lc \\\"jq --version && gh --version && btop --version && fnox --version && age --version\\\"\""
  check "mihomo active"                  "systemctl is-active mihomo"
  check "mihomo enabled"                 "systemctl is-enabled mihomo"
  check "mihomo config 0600 root"        "[ \"\$(stat -c %a:%U /etc/mihomo/config.yaml)\" = 600:root ]"
  check "mihomo config valid"            "mihomo -t -d /etc/mihomo -f /etc/mihomo/config.yaml"
  check "mihomo listening 7890"          "curl -s -o /dev/null -m 3 http://127.0.0.1:7890"
  if [ -n "$TEST_REAL_SECRETS" ]; then
    check "proxy reaches github"         "curl -fsS -x http://127.0.0.1:7890 -m 10 -o /dev/null https://github.com"
    check "env.sh: proxy + GH_PROXY"     "grep -q \"http_proxy=\" $st/env.sh && grep -q \"^export GH_PROXY=.https\" $st/env.sh"
  else
    check "env.sh: fallback GH_PROXY"    "! grep -q \"http_proxy=\" $st/env.sh && grep -q \"^export GH_PROXY=.https\" $st/env.sh"
  fi
  check "docker active"                  "systemctl is-active docker"
  check "docker registry mirror"         "docker info 2>/dev/null | grep -q mirror.ccs.tencentyun.com"
  check "dockerd proxy drop-in"          "systemctl show docker -p Environment | grep -q HTTP_PROXY=http://127.0.0.1:7890"
  check "tester in docker group"         "id -nG tester | grep -qw docker"
  check "tester sudo nopasswd"           "su tester -c \"sudo -n true\""
  check "tester login shell zsh"         "getent passwd tester | grep -q /usr/bin/zsh"
  check "tester has root ssh key"        "grep -q TestKeyOnly /home/tester/.ssh/authorized_keys"
  check "root keys removed"              "[ ! -e /root/.ssh/authorized_keys ]"
  check "sshd PermitRootLogin no"        "sshd -T | grep -qx \"permitrootlogin no\""
  check "sshd PasswordAuthentication no" "sshd -T | grep -qx \"passwordauthentication no\""
  check "docker pull via mirror"         "docker pull -q hello-world"
  check "home tidy (no skel bash files)"  "[ ! -e /home/tester/.bashrc ] && [ ! -e /home/tester/.profile ] && [ ! -e /home/tester/.bash_logout ]"
  check "sudoers !admin_flag"            "grep -qx \"Defaults !admin_flag\" /etc/sudoers.d/00-bootstrap-no-admin-flag"
  check "env.sh: PIP_INDEX_URL"          "grep -q ^export.PIP_INDEX_URL= $st/env.sh"
  check "no root-owned files in home"    "[ -z \"\$(find /home/tester -xdev -user 0 | head -1)\" ]"
  check "zsh startup without errors"     "sh /src/tests/zsh-startup-check.sh tester"
  check "no age key in state/logs/tmp"   "! grep -rqs AGE-SECRET-KEY $st /var/log /tmp /dev/shm"
  exit $fail
'
