#!/bin/sh
# scripts/update-gh-proxies.sh — 维护 GitHub 加速代理候选列表（D-031）
#
# 1. 从 https://github.xxlab.tech/ 抓取全部加速前缀，并与现有的 lib/gh-proxies.txt 合并（现有条目也重新验证）
# 2. 每个候选做 BS_GH_ROUNDS 轮（默认 3）完整测试（lib/mirrors.sh 的 bs_gh_test：release / raw / archive / clone，
#    直连代理，不经环境中的代理），只保留每一轮都全部通过的（稳定性）
# 3. 按最慢一轮的 release 下载速度排序写入 lib/gh-proxies.txt，并更新 bootstrap.sh / bootstrap.ps1 / lib/mirrors.sh 中的内置列表
#    （拉取仓库之前还没有 lib/gh-proxies.txt，管道模式与 Windows 入口使用内置列表）
#
# 必须在国内网络、且不经代理（无 TUN）的机器上运行，结果才代表部署时的真实情况。
# 用法：sh scripts/update-gh-proxies.sh            （BS_GH_ROUNDS=3  BS_GH_JOBS=8  BS_GH_BUILTIN=4）
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
rounds=${BS_GH_ROUNDS:-3}
jobs=${BS_GH_JOBS:-8}
nbuiltin=${BS_GH_BUILTIN:-4}
source_url=https://github.xxlab.tech/
out=$repo/lib/gh-proxies.txt
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# 1. 候选：页面中「加速源」下拉框的选项 + 现有列表
curl -fsSL --noproxy '*' -m 30 "$source_url" -o "$work/page.html"
{
  grep -o '<option value="https://[^"]*"' "$work/page.html" | sed 's/<option value="//; s/"$//'
  if [ -r "$out" ]; then sed -n 's/^\(https:[^[:space:]#]*\).*/\1/p' "$out"; fi
} | sed 's#/*$#/#' | sort -u >"$work/candidates"
total=$(wc -l <"$work/candidates")
echo "update-gh-proxies: 候选 $total 个（来源：$source_url 与现有列表），每个测试 $rounds 轮…" >&2

# 2. 并行测试；每个候选输出一行：ok <最慢一轮速度> <最高延时ms> <前缀> | fail <前缀> <原因>
cat >"$work/one.sh" <<'EOF'
set -u
BS_SRC=$1; p=$2; rounds=$3
. "$BS_SRC/lib/common.sh"; . "$BS_SRC/lib/mirrors.sh"
min= maxlat=0 i=0
while [ "$i" -lt "$rounds" ]; do
  i=$((i + 1))
  lat=$(bs_gh_latency "$p")
  [ -n "$lat" ] || { echo "fail $p 第${i}轮连接失败"; exit 0; }
  sp=$(bs_gh_test "$p" 2>"$BS_TMP_ERR") || { echo "fail $p 第${i}轮：$(sed 's/.*：//' "$BS_TMP_ERR")"; exit 0; }
  [ "$lat" -gt "$maxlat" ] && maxlat=$lat
  if [ -z "$min" ] || [ "$sp" -lt "$min" ]; then min=$sp; fi
done
echo "ok $min $maxlat $p"
EOF
tr '\n' '\0' <"$work/candidates" | xargs -0 -P "$jobs" -I{} sh -c \
  'BS_TMP_ERR=$(mktemp); export BS_TMP_ERR; sh "$1" "$2" "$3" "$4"; rm -f "$BS_TMP_ERR"' _ "$work/one.sh" "$repo" {} "$rounds" \
  >"$work/results"

grep '^ok ' "$work/results" | sort -k2,2nr >"$work/ok" || true
nok=$(wc -l <"$work/ok")
[ "$nok" -gt 0 ] || { echo "update-gh-proxies: 没有通过全部测试的候选，保留原列表" >&2; sed 's/^/  /' "$work/results" >&2; exit 1; }

# 3. 写入列表
{
  echo "# lib/gh-proxies.txt — GitHub 加速代理候选（D-031），由 scripts/update-gh-proxies.sh 生成，勿直接编辑"
  echo "# 来源：$source_url（以及上一版列表）；生成时间：$(date '+%Y-%m-%d %H:%M %z')；测试机：$(hostname)"
  echo "# 条件：直连可用，$rounds 轮测试中 release / raw / archive / clone 每一轮都全部通过；按最慢一轮的 release 下载速度排序"
  echo "# 部署时（lib/mirrors.sh 的 bs_select_gh_proxy）会在本机重新测延时与真实下载，从中选出最优的一个"
  awk '{ printf "%-48s # 最慢一轮 %d KB/s，最高延时 %d ms\n", $4, $2 / 1024, $3 }' "$work/ok"
} >"$out"
echo "update-gh-proxies: $nok / $total 个通过，已写入 $out" >&2
grep '^fail ' "$work/results" | sed 's/^fail /  未通过：/' >&2 || true

# 内置列表（前 nbuiltin 个）
top=$(awk -v n="$nbuiltin" 'NR <= n { print $4 }' "$work/ok" | tr '\n' ' ' | sed 's/ $//')
sed -i.bak "s#^BS_GH_PROXIES_BUILTIN=.*#BS_GH_PROXIES_BUILTIN=\"$top\"#" "$repo/lib/mirrors.sh"
sed -i.bak "s#^    for _p in \"\${GH_PROXY:-_none_}\" .*; do  \# @gh-proxies\$#    for _p in \"\${GH_PROXY:-_none_}\" $top \"\"; do  \# @gh-proxies#" "$repo/bootstrap.sh"
ps_list=$(printf '%s' "$top" | sed "s/[^ ]*/'&'/g; s/ /, /g")
sed -i.bak "s#^\$GhProxies = @(.*)  \# @gh-proxies\$#\$GhProxies = @($ps_list)  \# @gh-proxies#" "$repo/bootstrap.ps1"
rm -f "$repo/lib/mirrors.sh.bak" "$repo/bootstrap.sh.bak" "$repo/bootstrap.ps1.bak"
grep -n '@gh-proxies' "$repo/bootstrap.sh" "$repo/bootstrap.ps1" >&2
grep -n '^BS_GH_PROXIES_BUILTIN=' "$repo/lib/mirrors.sh" >&2
