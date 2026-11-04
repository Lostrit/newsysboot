#!/bin/sh
# tests/run-tidy.sh —— HOME 整理（lib/tidy.sh，D-030）：在 ubuntu 容器中按腾讯云 Ubuntu 主机的实际情况预置文件后检查结果
#   tencent：与 dev 主机一致的预置文件 → 删除 / 移动到 XDG 目录
#   modified：内容被改过的文件 → 保留并提示
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
img=${TEST_IMAGE:-ubuntu:24.04}
docker run --rm -v "$repo:/src:ro" "$img" sh -c '
set -eu
useradd -m -s /bin/sh u >/dev/null
H=/home/u
# 腾讯云镜像预置（与 dev 主机上的内容一致，含行尾空格）
mkdir -p $H/.pip
printf "[global]\nindex-url = http://mirrors.tencentyun.com/pypi/simple\ntrusted-host = mirrors.tencentyun.com\n" >$H/.pip/pip.conf
printf "[easy_install]\nindex-url = http://mirrors.tencentyun.com/pypi/simple    \n" >$H/.pydistutils.cfg
printf "registry=https://mirrors.tencentyun.com/npm\n" >$H/.npmrc
printf "exit\n" >$H/.bash_history
: >$H/.sudo_as_admin_successful
printf "# HSTS\n" >$H/.wget-hsts
mkdir -p $H/.terminfo/x && printf x >$H/.terminfo/x/xterm-ghostty
chown -R u:u $H
run() { su u -s /bin/sh -c "cd; export HOME=$H XDG_CONFIG_HOME=$H/.config XDG_DATA_HOME=$H/.local/share XDG_STATE_HOME=$H/.local/state XDG_CACHE_HOME=$H/.cache BOOTSTRAP_OS=linux; . /src/lib/common.sh; . /src/lib/tidy.sh; bs_tidy_home" 2>&1 | sed "s/\x1b\[[0-9;]*m//g"; }
echo "--- tencent"; run
echo "--- HOME:"; ls -A $H | tr "\n" " "; echo
f=0
chk() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; f=1; fi; }
chk "pip.conf 与 .pip 已删除"        "[ ! -e $H/.pip ]"
chk ".pydistutils.cfg 已删除"        "[ ! -e $H/.pydistutils.cfg ]"
chk ".npmrc 已删除"                  "[ ! -e $H/.npmrc ]"
chk "bash 默认文件已删除"            "[ ! -e $H/.bashrc ] && [ ! -e $H/.profile ] && [ ! -e $H/.bash_logout ]"
chk "bash 历史已移到 XDG"            "[ ! -e $H/.bash_history ] && grep -qx exit $H/.local/state/bash/history"
chk "terminfo 已移到 XDG"            "[ ! -e $H/.terminfo ] && [ -f $H/.local/share/terminfo/x/xterm-ghostty ]"
chk "wget HSTS 已移到 XDG"           "[ ! -e $H/.wget-hsts ] && [ -f $H/.cache/wget-hsts ]"
chk ".sudo_as_admin_successful 已删除" "[ ! -e $H/.sudo_as_admin_successful ]"
echo "--- 重复执行（应无输出）"; run
echo "--- modified"
printf "registry=https://registry.npmjs.org/\n" >$H/.npmrc
cp /etc/skel/.bashrc $H/.bashrc && echo "alias ll=\"ls -l\"" >>$H/.bashrc
printf "x\n" >$H/.bash_history; chown u:u $H/.npmrc $H/.bashrc $H/.bash_history
run
chk "自定义 .npmrc 保留"             "grep -q registry.npmjs.org $H/.npmrc"
chk "修改过的 .bashrc 保留"          "grep -q \"alias ll\" $H/.bashrc"
chk "历史冲突时不覆盖"               "[ -e $H/.bash_history ] && grep -qx exit $H/.local/state/bash/history"
exit $f'
