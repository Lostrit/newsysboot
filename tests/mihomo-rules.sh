#!/bin/sh
# tests/mihomo-rules.sh —— 验证各场景 mihomo 配置的分流结果（D-027）
#
# 需要在装有 mihomo 的机器上运行（如部署后的 Linux 主机）：
#   1. 用假节点（127.0.0.2:9，不可用）经 scripts/render-mihomo.sh 渲染 server / desktop / steamos 三份配置
#   2. 分别在临时端口启动 mihomo（steamos 关闭 TUN，避免接管本机网络），等待规则集下载
#   3. 经该端口访问下方清单中的地址，从日志中取出每个连接实际使用的策略，与预期比较
# 假节点不可用，因此 Steam 商店的 fallback 组应回退到 DIRECT，正好验证「代理不可用时回退直连」
# （健康检查地址换成能直连的地址，见下方说明）。
#
# 用法：sh tests/mihomo-rules.sh [server|desktop|steamos ...]
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
command -v mihomo >/dev/null 2>&1 || { echo "需要 mihomo" >&2; exit 1; }
work=$(mktemp -d)
trap 'kill $(cat "$work"/*.pid 2>/dev/null) 2>/dev/null || true; rm -rf "$work"' EXIT

export MIHOMO_PROXIES="proxies:
  - name: test-dummy
    type: socks5
    server: 127.0.0.2
    port: 9"

# 场景 主机 预期策略：组名（只比较组名）或 组名[成员]（同时比较组内实际选中的成员）；DIRECT / REJECT 原样
cases() {
  cat <<'EOF'
server github.com 开发
server raw.githubusercontent.com 开发
server huggingface.co 开发
server api.openai.com 开发
server api.anthropic.com 开发
server generativelanguage.googleapis.com 开发
server registry.npmjs.org 开发
server proxy.golang.org 开发
server registry-1.docker.io 开发
server pypi.org 开发
server mirrors.tencentyun.com DIRECT
server mirrors.aliyun.com DIRECT
server ghfast.top DIRECT
server gh-proxy.com DIRECT
server mirror.ccs.tencentyun.com DIRECT
server docker.m.daocloud.io DIRECT
server goproxy.cn DIRECT
server registry.npmmirror.com DIRECT
server 119.29.29.29 DIRECT
server 10.0.0.1 DIRECT
server www.baidu.com DIRECT
server www.google.com PROXY
server doubleclick.net PROXY
desktop apps.apple.com DIRECT
desktop www.apple.com DIRECT
desktop storeedgefd.dsx.mp.microsoft.com DIRECT
desktop www.microsoft.com DIRECT
desktop github.com 开发
desktop api.github.com 开发
desktop huggingface.co 开发
desktop registry.npmjs.org 开发
desktop proxy.golang.org 开发
desktop registry-1.docker.io 开发
desktop chatgpt.com AI
desktop claude.ai AI
desktop gemini.google.com AI
desktop www.youtube.com 海外服务
desktop www.netflix.com 海外服务
desktop www.twitch.tv 海外服务
desktop web.telegram.org 海外服务
desktop discord.com 海外服务
desktop x.com 海外服务
desktop www.facebook.com 海外服务
desktop www.reddit.com 海外服务
desktop www.google.com 海外服务
desktop www.bbc.com PROXY
desktop www.nytimes.com PROXY
desktop doubleclick.net AD
desktop www.baidu.com DIRECT
desktop www.bilibili.com DIRECT
desktop mirrors.tencentyun.com DIRECT
steamos store.steampowered.com Steam商店[DIRECT]
steamos steamcommunity.com Steam商店[DIRECT]
steamos api.steampowered.com Steam商店[DIRECT]
steamos cdn.akamai.steamstatic.com Steam商店[DIRECT]
steamos steampipe.akamaized.net DIRECT
steamos cache1-hkg1.steamcontent.com DIRECT
steamos cdn-ali.content.steamchina.com DIRECT
steamos ext1-hkg1.steamserver.net DIRECT
steamos 119.29.29.29 DIRECT
steamos 192.168.1.10 DIRECT
steamos www.baidu.com DIRECT
steamos www.google.com PROXY
EOF
}

profiles=${*:-server desktop steamos}
port=17890
fail=0
for p in $profiles; do
  port=$((port + 1))
  d="$work/$p"
  BOOTSTRAP_MIHOMO_PORT=$port sh "$repo/scripts/render-mihomo.sh" "$p" "$d/config.yaml" >/dev/null 2>&1 ||
    { echo "FAIL ${p}：渲染失败"; fail=1; continue; }
  # 测试实例：不开 TUN、不开 DNS 监听
  sed -i 's/^  enable: true$/  enable: false/' "$d/config.yaml"
  # Steam 商店的健康检查地址换成能直连的地址，模拟家庭网络中「直连可用、代理不可用」：
  # 测试机（国内云主机）直连 Steam 商店会超时，此时 DIRECT 也被判为不可用，fallback 按顺序选第一个（节点）
  sed -i 's#url: https://store.steampowered.com/robots.txt#url: https://www.baidu.com/#' "$d/config.yaml"
  mihomo -d "$d" -f "$d/config.yaml" >"$d/log" 2>&1 &
  echo $! >"$work/$p.pid"
  i=0
  until grep -q "Mixed(http+socks) proxy listening" "$d/log" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 120 ] || { echo "FAIL ${p}：mihomo 未启动"; tail -5 "$d/log"; fail=1; continue 2; }
    sleep 1
  done
  # 规则集在后台下载；等日志中不再出现新的下载记录
  sleep 15
  [ "$p" = steamos ] && sleep 10 # 等 fallback 组完成一次健康检查（假节点失败 → DIRECT）
  cases | while read -r cp host want; do
    [ "$cp" = "$p" ] || continue
    case "$host" in [0-9]*) url="http://$host/" ;; *) url="https://$host/" ;; esac
    curl -s -o /dev/null -m 4 --noproxy "" -x "http://127.0.0.1:$port" "$url" 2>/dev/null || true
    # 连接失败（如不可达的内网地址）时，mihomo 要等拨号超时才写日志：最多等 12 秒
    n=0
    while ! grep -qF -- "--> ${host}:" "$d/log" && [ "$n" -lt 24 ]; do sleep 0.5; n=$((n + 1)); done
    # 成功：「match … using 组[节点]」；节点不可用：「dial 组 (match …) … error」
    line=$(grep -F -- "--> ${host}:" "$d/log" | tail -1)
    case "$want" in
      *\[*)
        got=$(printf '%s\n' "$line" | sed -n 's/.* using \([^" ]*\).*/\1/p' | head -1)
        # 拨号失败时日志里没有组内成员：报错中出现假节点地址则是走了节点，否则是 DIRECT
        if [ -z "$got" ]; then
          g=$(printf '%s\n' "$line" | sed -n 's/.*\] dial \([^ ]*\) (match.*/\1/p')
          case "$line" in *127.0.0.2:9*) got="$g[test-dummy]" ;; *) [ -z "$g" ] || got="$g[DIRECT]" ;; esac
        fi
        ;;
      *) got=$(printf '%s\n' "$line" | sed -n -e 's/.* using \([^[" ]*\).*/\1/p' -e 's/.*\] dial \([^ ]*\) (match.*/\1/p' | head -1) ;;
    esac
    if [ "$got" = "$want" ]; then
      echo "PASS $p $host → $got"
    else
      echo "FAIL $p $host → ${got:-<无记录>}（预期 ${want}）：$(printf '%s' "$line" | sed -n 's/.*msg="\(.*\)"/\1/p' | cut -c1-160)"
      echo 1 >"$work/failed"
    fi
  done
  kill "$(cat "$work/$p.pid")" 2>/dev/null || true
done
[ ! -e "$work/failed" ] && [ "$fail" = 0 ]
