#!/bin/sh
# scripts/gen-windows-mihomo.sh [--check] —— 生成 Windows 用的 mihomo 配置 files/mihomo/windows-desktop.yaml（D-029）
#
# Windows 上 mise 的 [bootstrap.files] 不可用，无法渲染 Tera 模板，因此预先把 desktop 场景渲染好提交到仓库：
# 节点（机密）的位置是占位行「# @@MIHOMO_PROXIES@@」，bootstrap.ps1 用 fnox 解密出的节点替换它。
# 修改 files/mihomo/config.yaml.tera 后必须重新生成；--check 只检查是否与模板一致（tests/run-windows-config.sh 使用）。
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
out=$repo/files/mihomo/windows-desktop.yaml
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

MIHOMO_PROXIES="# @@MIHOMO_PROXIES@@" sh "$repo/scripts/render-mihomo.sh" desktop "$tmp/config.yaml" >"$tmp/log" 2>&1 || { cat "$tmp/log" >&2; exit 1; }
{
  echo "# 由 scripts/gen-windows-mihomo.sh 从 files/mihomo/config.yaml.tera（desktop 场景）生成，勿直接编辑（D-029）"
  cat "$tmp/config.yaml"
} >"$tmp/out.yaml"
grep -qx '# @@MIHOMO_PROXIES@@' "$tmp/out.yaml" || { echo "gen-windows-mihomo: 缺少节点占位行" >&2; exit 1; }

if [ "${1:-}" = --check ]; then
  if cmp -s "$tmp/out.yaml" "$out"; then
    echo "gen-windows-mihomo: $out 与模板一致"
  else
    echo "gen-windows-mihomo: $out 与模板不一致，请运行 scripts/gen-windows-mihomo.sh 重新生成" >&2
    diff -u "$out" "$tmp/out.yaml" | head -20 >&2 || true
    exit 1
  fi
else
  cp "$tmp/out.yaml" "$out"
  echo "gen-windows-mihomo: 已生成 $out"
fi
