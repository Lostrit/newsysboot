#!/bin/sh
# scripts/install-mihomo.sh — 安装锁定版本的 mihomo（Debian / Ubuntu：官方 deb 包，带 systemd unit）
#
# 由 mise.mihomo.toml 的 post-packages hook 调用；已是目标版本时什么都不做。
# 下载经 GH_PROXY（mihomo 生效前无法直连 GitHub），并校验 sha256（防止代理篡改）。
set -eu

VERSION=1.19.33
case "$(uname -m)" in
  x86_64 | amd64)
    ARCH=amd64
    SHA256=3f6f31f325a392b87702241a763e124f3e684f31c2c1004cb581538eb04baf68
    ;;
  aarch64 | arm64)
    ARCH=arm64
    SHA256=c01af4145bc400e40f3ac5995c238c2d89a8714421ce9ebb529061e9a0cf5154
    ;;
  *)
    echo "install-mihomo: 不支持的架构 $(uname -m)" >&2
    exit 1
    ;;
esac

if command -v mihomo >/dev/null 2>&1 && mihomo -v 2>/dev/null | grep -q "v$VERSION "; then
  echo "install-mihomo: 已是 v$VERSION"
  exit 0
fi

name="mihomo-linux-$ARCH-v$VERSION.deb"
url="${GH_PROXY:-}https://github.com/MetaCubeX/mihomo/releases/download/v$VERSION/$name"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "install-mihomo: 下载 $url"
curl -fsSL --retry 3 -o "$tmp/$name" "$url"
echo "$SHA256  $tmp/$name" | sha256sum -c - >/dev/null || {
  echo "install-mihomo: sha256 校验失败" >&2
  exit 1
}
# 包内的 /etc/mihomo/config.yaml 是 conffile；我们会用模板覆盖，dpkg 升级时保留现有版本
sudo env DEBIAN_FRONTEND=noninteractive dpkg -i --force-confold "$tmp/$name" >/dev/null
echo "install-mihomo: 已安装 $(mihomo -v | head -n 1)"
