#!/bin/sh
# scripts/render-mihomo.sh <server|desktop|steamos> <输出文件>
#
# 单独渲染一份 mihomo 配置（files/mihomo/config.yaml.tera，D-027）：
#   - Windows 等不经 bootstrap 部署 mihomo 的环境：在任意已部署本仓库的 Linux / macOS 上渲染 desktop 配置，导入客户端
#   - 测试：环境中已有 MIHOMO_PROXIES 时直接使用（不需要私钥），否则经 fnox 用 age 私钥（FNOX_AGE_KEY）解密
# 监听设置可用 BOOTSTRAP_MIHOMO_PORT / _ALLOW_LAN / _BIND / _LAN_IPS 覆盖，默认值与部署时相同。
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
[ $# -eq 2 ] || { echo "用法：$0 <server|desktop|steamos> <输出文件>" >&2; exit 2; }
profile=$1
case "$2" in /*) out=$2 ;; *) out=$PWD/$2 ;; esac
case "$profile" in
  server) lan=true bind='*' ips=127.0.0.0/8,172.16.0.0/12 ;;
  desktop | steamos) lan=false bind=127.0.0.1 ips=127.0.0.0/8 ;;
  *) echo "未知场景：$profile" >&2; exit 2 ;;
esac

# mise 要求输出文件的父目录已存在
mkdir -p "$(dirname "$out")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/mise.toml" <<TOML
[vars]
mihomo_profile = "$profile"
mihomo_mixed_port = "${BOOTSTRAP_MIHOMO_PORT:-7890}"
mihomo_allow_lan = "${BOOTSTRAP_MIHOMO_ALLOW_LAN:-$lan}"
mihomo_bind_address = "${BOOTSTRAP_MIHOMO_BIND:-$bind}"
mihomo_lan_allowed_ips = "${BOOTSTRAP_MIHOMO_LAN_IPS:-$ips}"

[bootstrap.secrets.mihomo_proxies]
env = "MIHOMO_PROXIES"

[bootstrap.files."$out"]
source = "$repo/files/mihomo/config.yaml.tera"
template = true
mode = "0600"
TOML
mise trust -q "$tmp/mise.toml"
if [ -n "${MIHOMO_PROXIES:-}" ]; then
  mise -C "$tmp" bootstrap --yes --only files
else
  (cd "$repo" && mise exec fnox -- fnox exec -- mise -C "$tmp" bootstrap --yes --only files)
fi
echo "已渲染 $profile 配置：$out"
