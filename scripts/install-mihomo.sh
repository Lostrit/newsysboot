#!/bin/sh
# scripts/install-mihomo.sh — 安装锁定版本的 mihomo
#
#   有 dpkg（Debian / Ubuntu）：官方 deb 包，自带 systemd unit（D-016）
#   没有 dpkg（SteamOS）：官方独立二进制，装到 $MIHOMO_PREFIX/bin（默认 /var/lib/mihomo，不碰只读的 /usr），
#                         unit 文件由 mise.steamos.toml 写入 /etc/systemd/system
#
# 由 mise.mihomo.toml 的 post-packages hook 调用；已是目标版本时什么都不做。
# 下载经 GH_PROXY（mihomo 生效前无法直连 GitHub），并校验 sha256（防止代理篡改）。
set -eu

VERSION=1.19.33
: "${MIHOMO_PREFIX:=/var/lib/mihomo}"

if command -v dpkg >/dev/null 2>&1; then
  MODE=deb
  BIN=/usr/bin/mihomo
else
  MODE=bin
  BIN=$MIHOMO_PREFIX/bin/mihomo
fi

case "$MODE-$(uname -m)" in
  deb-x86_64 | deb-amd64) ASSET=mihomo-linux-amd64-v$VERSION.deb SHA256=3f6f31f325a392b87702241a763e124f3e684f31c2c1004cb581538eb04baf68 ;;
  deb-aarch64 | deb-arm64) ASSET=mihomo-linux-arm64-v$VERSION.deb SHA256=c01af4145bc400e40f3ac5995c238c2d89a8714421ce9ebb529061e9a0cf5154 ;;
  bin-x86_64 | bin-amd64) ASSET=mihomo-linux-amd64-v$VERSION.gz SHA256=132f6f3edf9a65e62f04853aed3358472e0b2b7666daa8419edfa2ddf5bb6323 ;;
  bin-aarch64 | bin-arm64) ASSET=mihomo-linux-arm64-v$VERSION.gz SHA256=ba408b317080ee265c46cb923a50018c1b82cbd708551cdd46a1e3e307396187 ;;
  *)
    echo "install-mihomo: 不支持 $MODE / $(uname -m)" >&2
    exit 1
    ;;
esac

if [ -x "$BIN" ] && "$BIN" -v 2>/dev/null | grep -q "v$VERSION "; then
  echo "install-mihomo: 已是 v$VERSION（$BIN）"
  exit 0
fi

url="${GH_PROXY:-}https://github.com/MetaCubeX/mihomo/releases/download/v$VERSION/$ASSET"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "install-mihomo: 下载 $url"
curl -fsSL --retry 3 -o "$tmp/$ASSET" "$url"
echo "$SHA256  $tmp/$ASSET" | sha256sum -c - >/dev/null || {
  echo "install-mihomo: sha256 校验失败" >&2
  exit 1
}

if [ "$MODE" = deb ]; then
  # 包内的 /etc/mihomo/config.yaml 是 conffile；我们会用模板覆盖，dpkg 升级时保留现有版本（P-020）
  sudo env DEBIAN_FRONTEND=noninteractive dpkg -i --force-confold "$tmp/$ASSET" >/dev/null
else
  gzip -dc "$tmp/$ASSET" >"$tmp/mihomo"
  sudo install -d -m 755 "$MIHOMO_PREFIX/bin"
  sudo install -m 755 "$tmp/mihomo" "$BIN"
fi
echo "install-mihomo: 已安装 $("$BIN" -v | head -n 1)"
