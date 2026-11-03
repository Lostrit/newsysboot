# tests/cloud/verify-route.zsh —— 真实节点下的分流检查：发请求后从 journalctl -u mihomo 核对实际策略（由 tests/run-cloud.sh 运行）
fail=0
gh=$(sed -n "s/^export GH_PROXY='\(.*\)'$/\1/p" ~/.local/state/bootstrap/env.sh); ghhost=${${gh#https://}%%/*}
check() { # <主机> <预期组 | DIRECT | BYPASS> [url]
  local host=$1 want=$2 url=${3:-https://$1/} t0=$(date '+%Y-%m-%d %H:%M:%S')
  local code=$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$url"); sleep 1
  local line=$(sudo journalctl -u mihomo --since "$t0" --no-pager -o cat | grep -F -- "--> ${host}:" | tail -1) got
  if [[ -z $line ]]; then got=BYPASS; else got=$(print -r -- "$line" | sed -n 's/.* using \([^[" ]*\).*/\1/p'); fi
  if [[ $got == $want ]]; then print "PASS $host → $got（HTTP $code）"; else print "FAIL $host → ${got:-?}，预期 $want（HTTP $code）"; fail=1; fi
}
for h in github.com huggingface.co registry.npmjs.org proxy.golang.org registry-1.docker.io pypi.org api.openai.com api.anthropic.com; do check $h 开发; done
[[ -n $ghhost ]] && check $ghhost BYPASS
check mirrors.tencentyun.com BYPASS http://mirrors.tencentyun.com/
for h in ghfast.top goproxy.cn registry.npmmirror.com cdn.jsdelivr.net; do check $h DIRECT; done
check www.baidu.com DIRECT; check 119.29.29.29 DIRECT http://119.29.29.29/
check www.google.com PROXY
print -- "--- 部署期间 mihomo 中的 GitHub 相关连接（下载应经 GH_PROXY，不应出现 release / codeload / objects）："
sudo journalctl -u mihomo --no-pager -o cat | grep -oE -- '--> [a-z0-9.-]*(github|githubusercontent)[a-z.]*:' | sort | uniq -c
print "fail=$fail"
