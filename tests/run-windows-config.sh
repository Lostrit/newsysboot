#!/bin/sh
# tests/run-windows-config.sh —— Windows 用 mihomo 配置的检查（D-029）
#   1. files/mihomo/windows-desktop.yaml 与模板（desktop 场景）一致
#   2. 按 bootstrap.ps1 的方式替换节点占位行后，mihomo -t 校验通过（需要 mihomo；没有时跳过这一步）
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
sh "$repo/scripts/gen-windows-mihomo.sh" --check
command -v mihomo >/dev/null 2>&1 || { echo "跳过 mihomo -t：没有 mihomo"; exit 0; }
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
nodes='proxies:
  - name: test-dummy
    type: socks5
    server: 127.0.0.2
    port: 9'
awk -v n="$nodes" '$0 == "# @@MIHOMO_PROXIES@@" { print n; next } { print }' "$repo/files/mihomo/windows-desktop.yaml" >"$d/config.yaml"
grep -q '^proxies:' "$d/config.yaml"
timeout 180 mihomo -t -d "$d" -f "$d/config.yaml" | tail -1
