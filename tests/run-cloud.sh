#!/bin/sh
# tests/run-cloud.sh —— 真机测试：经腾讯云 API 把测试主机 dev 重装为指定镜像，注入 age 私钥，一键部署并检查（D-032）
#
# 用法：sh tests/run-cloud.sh <BlueprintId> <默认登录用户> [--as-root]
#   Debian 镜像：sh tests/run-cloud.sh lhbp-mxml4cnq root
#   Ubuntu 镜像：sh tests/run-cloud.sh lhbp-1l4ptuvm ubuntu              # 以已有 sudo 用户运行（D-025）
#                sh tests/run-cloud.sh lhbp-qg4ymn4o ubuntu --as-root    # 经 sudo 以 root 运行，新建用户 lostrit
# 环境变量：DEV_IP（默认 62.234.97.210）、BOOTSTRAP_SOURCE（github | cnb，默认 github）、TEST_SKIP_RESET=1（不重装）
#
# 需要 ~/.config/tencentcloud/dev.env（scripts/tccloud.py）。部署的是**已推送**的代码：入口脚本从 CNB 拉取（国内直连）。
# 部署日志在测试主机的 /var/tmp/bs-run.log；检查脚本为 tests/cloud/verify-{host,route}.zsh。
# 本机只做调度（ssh / API），重活都在测试主机上（开发机资源有限，P-042）。
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 2 ] || { sed -n '2,14p' "$0"; exit 2; }
bp=$1 login=$2 asroot=${3:-}
ip=${DEV_IP:-62.234.97.210}
src=${BOOTSTRAP_SOURCE:-github}
so="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=15"
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
# shellcheck disable=SC2086
rsh() { _u=$1; shift; timeout 600 ssh $so "$_u@$ip" "$@"; }

if [ "$login" = root ] || [ "$asroot" = --as-root ]; then mode=root final=lostrit; else mode=user final=$login; fi
sudo_=""
[ "$login" = root ] || sudo_="sudo -n"

# 1. 重装
if [ "${TEST_SKIP_RESET:-}" != 1 ]; then
  log "重装 dev 为 $bp"
  python3 "$repo/scripts/tccloud.py" reset "$bp"
fi
ssh-keygen -R "$ip" >/dev/null 2>&1 || true
log "等待 SSH（$login@$ip）"
i=0
until rsh "$login" true 2>/dev/null; do
  i=$((i + 1)); [ "$i" -lt 60 ] || { echo "SSH 不可用" >&2; exit 1; }
  sleep 10
done
rsh "$login" '. /etc/os-release; echo "系统：$PRETTY_NAME"; id'

# 2. 注入私钥（TAT 命令只执行、不查询内容；经 SSH 检查是否写入）
if ! rsh "$login" "$sudo_ test -s /dev/shm/bootstrap-age.key" 2>/dev/null; then
  log "注入 age 私钥"
  python3 "$repo/scripts/tccloud.py" inject
  i=0
  until rsh "$login" "$sudo_ test -s /dev/shm/bootstrap-age.key" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 30 ] || { echo "私钥注入失败：/dev/shm/bootstrap-age.key 不存在" >&2; exit 1; }
    sleep 10
  done
fi
rsh "$login" "$sudo_ stat -c '私钥文件：%n %s 字节 %a %U' /dev/shm/bootstrap-age.key"

# 3. 一键部署（后台运行，写日志）
log "部署（模式：$mode，来源：$src，最终用户：$final）"
if [ "$mode" = root ]; then
  hash=$(openssl rand -base64 18 | openssl passwd -6 -stdin)
  envs="BOOTSTRAP_USER=$final BOOTSTRAP_PASSWORD_HASH='$hash'"
  run_as="sudo -n"
  [ "$login" = root ] && run_as=""
else
  envs=""
  run_as=""
fi
rsh "$login" "cat > /tmp/bs-run.sh" <<EOF
#!/bin/sh
exec >/var/tmp/bs-run.log 2>&1
export FNOX_AGE_KEY="\$(sudo -n cat /dev/shm/bootstrap-age.key 2>/dev/null || cat /dev/shm/bootstrap-age.key)"
sudo -n rm -f /dev/shm/bootstrap-age.key 2>/dev/null || rm -f /dev/shm/bootstrap-age.key
export BOOTSTRAP_SOURCE=$src BOOTSTRAP_HARDEN_SSH=1 BOOTSTRAP_NONINTERACTIVE=1 $envs
curl -fsSL https://cnb.cool/xfengjing/lostrit/NewSysBoot/-/git/raw/main/bootstrap.sh | sh
echo "EXIT=\$?"
EOF
rsh "$login" "chmod 755 /tmp/bs-run.sh; $run_as touch /var/tmp/bs-run.log; $run_as chmod 644 /var/tmp/bs-run.log; $run_as setsid nohup sh /tmp/bs-run.sh >/dev/null 2>&1 </dev/null &"

# 4. 等待完成（SSH 加固后 root 不能登录：依次尝试最终用户与登录用户）
poll() { for _u in "$final" "$login"; do rsh "$_u" "$@" 2>/dev/null && return 0; done; return 1; }
t0=$(date +%s)
until poll 'grep -q "^EXIT=" /var/tmp/bs-run.log'; do
  [ $(($(date +%s) - t0)) -lt 3600 ] || { echo "部署超时" >&2; exit 1; }
  sleep 30
done
log "部署结束（$(($(date +%s) - t0)) 秒）"
# 完整部署日志拷回本机（测试主机下次重装就没了），与检查结果放在一起
full=${TEST_OUT:-${TMPDIR:-/tmp}/run-cloud}.deploy.log
for _u in "$final" "$login"; do
  timeout 60 scp -q $so "$_u@$ip:/var/tmp/bs-run.log" "$full" 2>/dev/null && { log "完整部署日志：$full"; break; }
done
poll 'sed "s/\x1b\[[0-9;]*m//g" /var/tmp/bs-run.log | grep -E "==>|^warn|^error|WARNING|EXIT=|E: |installed .* tools|bootstrap\.sh: (完成|3 次)|install-mihomo: (下载|已)" | grep -v "⇢"'

# 5. 检查（以最终用户运行；最终用户不能 SSH 登录时经登录用户 sudo 切换）；结果另存到 TEST_OUT
out=${TEST_OUT:-$(mktemp "${TMPDIR:-/tmp}/run-cloud.XXXXXX")}
for f in verify-host verify-route; do
  rsh_ok=
  for _u in "$final" "$login"; do
    if timeout 60 scp -q $so "$repo/tests/cloud/$f.zsh" "$_u@$ip:/tmp/$f.zsh" 2>/dev/null; then rsh_ok=$_u; break; fi
  done
  [ -n "$rsh_ok" ] || { echo "无法复制检查脚本" >&2; exit 1; }
  log "$f（经 $rsh_ok）"
  if [ "$rsh_ok" = "$final" ]; then
    rsh "$final" "zsh /tmp/$f.zsh; rm -f /tmp/$f.zsh"
  else
    rsh "$login" "chmod 644 /tmp/$f.zsh; sudo -n -u $final -i zsh /tmp/$f.zsh; rm -f /tmp/$f.zsh"
  fi
done | tee "$out"
nfail=$(grep -c '^FAIL' "$out" || true)
log "检查结果：PASS $(grep -c '^PASS' "$out" || true)，FAIL $nfail（$out）"
[ "$nfail" = 0 ]
