#!/bin/sh
# tests/container/verify.sh —— 容器部署后的检查（tests/run.sh 在容器中以 root 运行；D-036、D-038）
# 用法：sh verify.sh <部署用户>
u=${1:-tester}
fail=0
check() {
  if sh -c "$2" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail + 1)); fi
}
asu() { su - "$u" -c "$1"; }
st=$(getent passwd "$u" | cut -d: -f6)/.local/state/bootstrap

check "BOOTSTRAP_ROLE=container" "grep -qx \"export BOOTSTRAP_ROLE='container'\" $st/env.sh"
check "MISE_DISABLE_TOOLS：fnox age gh btop cnb" "grep -q \"^export MISE_DISABLE_TOOLS='fnox,age,aqua:cli/cli,aqua:aristocratos/btop,npm:@cnbcool/cnb-cli'\" $st/env.sh"
for t in fnox age gh btop cnb; do
  check "不安装 ${t}（容器中不落盘机密）" "! su - $u -c 'zsh -lc \"command -v $t\"'"
done
check "mise 中没有 fnox / age 的安装" "! ls $(dirname "$st")/../share/mise/installs 2>/dev/null | grep -qE '^(fnox|age)$'"
for t in jq eza bat rg fd nvim tmux herdr node; do
  check "工具 $t" "su - $u -c 'zsh -lc \"command -v $t\"'"
done
check "procps / iproute2" "command -v ps && command -v ip"
check "locale：zh_CN.UTF-8 与 en_US.UTF-8" "locale -a | grep -qix zh_CN.utf8 && locale -a | grep -qix en_US.utf8"
check "/etc/default/locale" "grep -qx 'LANG=zh_CN.UTF-8' /etc/default/locale && grep -qx 'LANGUAGE=zh_CN:en_US' /etc/default/locale"
check "zsh 中 LANG（docker exec 不经 PAM）" "[ \"\$(su $u -c 'env -u LANG zsh -c \"print -r -- \\\$LANG\"')\" = zh_CN.UTF-8 ]"
check "时区 Asia/Shanghai" "readlink /etc/localtime | grep -q 'Asia/Shanghai\$' && [ \"\$(date +%z)\" = +0800 ]"
check "镜像中没有 SSH 主机密钥" "! ls /etc/ssh/ssh_host_* 2>/dev/null"
check "sshd 配置与入口" "[ -x /usr/local/bin/bootstrap-sshd ] && grep -q '^HostKey /dev/shm/' /etc/ssh/sshd_config.d/00-bootstrap-container.conf"

# 功能测试：主机私钥经管道载入内存，授权公钥来自 /run/secrets，然后用公钥登录
t=$(mktemp -d /dev/shm/verify.XXXXXX)   # 测试用的密钥也只放在内存中
ssh-keygen -q -t ed25519 -N '' -f "$t/host" && ssh-keygen -q -t ed25519 -N '' -f "$t/client"
mkdir -p /run/secrets && cp "$t/client.pub" /run/secrets/ssh_authorized_keys
check "load-key 拒绝无效输入" "! echo not-a-key | bootstrap-sshd load-key"
check "load-key 载入主机私钥" "bootstrap-sshd load-key <$t/host && [ \"\$(stat -c %a /dev/shm/bootstrap-sshd/ssh_host_ed25519_key)\" = 600 ]"
# sshd 在后台运行：输出写入日志，避免它持有 docker exec 的输出导致 docker exec 不退出
bootstrap-sshd true >/tmp/bootstrap-sshd.log 2>&1 </dev/null
i=0
while [ "$i" -lt 20 ] && ! ssh-keyscan -T 2 127.0.0.1 >/dev/null 2>&1; do sleep 1; i=$((i + 1)); done
check "sshd 使用注入的主机私钥" "ssh-keyscan -t ed25519 127.0.0.1 2>/dev/null | awk '{print \$3}' | grep -qx \"\$(cut -d' ' -f2 $t/host.pub)\""
check "公钥登录 $u" "ssh -i $t/client -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $u@127.0.0.1 true"
check "禁止 root 登录" "! ssh -i $t/client -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@127.0.0.1 true"
check "禁止密码登录" "/usr/sbin/sshd -T | grep -qx 'passwordauthentication no'"
# 私钥第 2 行是所有 ed25519 私钥共有的头部，第 4 行才是这把私钥独有的内容
hostkey=$(sed -n 4p "$t/host")
cat /tmp/bootstrap-sshd.log
pkill -x sshd 2>/dev/null
rm -rf "$t" /run/secrets/ssh_authorized_keys
# 只搜根文件系统（-xdev：/proc、/sys、内存中的 /dev/shm 都是单独的挂载）；grep -r / 会读到 /proc 下的文件而卡住
check "主机私钥只在内存中" "[ -z \"\$(find / -xdev -type f -size -10M -print0 2>/dev/null | xargs -0 grep -lsF -- '$hostkey' 2>/dev/null)\" ]"
rm -rf /dev/shm/bootstrap-sshd
echo "==> FAIL $fail"
exit "$fail"
