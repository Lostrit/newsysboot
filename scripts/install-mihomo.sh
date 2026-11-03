#!/bin/sh
# scripts/install-mihomo.sh — 安装锁定版本的 mihomo
#
#   有 dpkg（Debian / Ubuntu）：官方 deb 包，自带 systemd unit（D-016）
#   没有 dpkg（SteamOS）：官方独立二进制，装到 $MIHOMO_PREFIX/bin（默认 /var/lib/mihomo，不碰只读的 /usr），
#                         unit 文件由 mise.steamos.toml 写入 /etc/systemd/system
#   macOS：官方独立二进制，装到 /opt/mihomo/bin（root 所有；由 root 的 LaunchDaemon 运行以支持 TUN，D-028。
#          不用 Homebrew 的 mihomo：其目录当前用户可写，以 root 运行用户可改写的程序等于交出 root 权限）
#
# 由 mise.mihomo.toml / mise.macos.toml 的 post-packages hook 调用；已是目标版本时什么都不做。
# 下载经 GH_PROXY（mihomo 生效前无法直连 GitHub），并校验 sha256（防止代理篡改）。
set -eu

VERSION=1.19.33

if [ "$(uname -s)" = Darwin ]; then
  : "${MIHOMO_PREFIX:=/opt/mihomo}"
  MODE=darwin
  BIN=$MIHOMO_PREFIX/bin/mihomo
elif command -v dpkg >/dev/null 2>&1; then
  MODE=deb
  BIN=/usr/bin/mihomo
else
  : "${MIHOMO_PREFIX:=/var/lib/mihomo}"
  MODE=bin
  BIN=$MIHOMO_PREFIX/bin/mihomo
fi

case "$MODE-$(uname -m)" in
  deb-x86_64 | deb-amd64) ASSET=mihomo-linux-amd64-v$VERSION.deb SHA256=3f6f31f325a392b87702241a763e124f3e684f31c2c1004cb581538eb04baf68 ;;
  deb-aarch64 | deb-arm64) ASSET=mihomo-linux-arm64-v$VERSION.deb SHA256=c01af4145bc400e40f3ac5995c238c2d89a8714421ce9ebb529061e9a0cf5154 ;;
  bin-x86_64 | bin-amd64) ASSET=mihomo-linux-amd64-v$VERSION.gz SHA256=132f6f3edf9a65e62f04853aed3358472e0b2b7666daa8419edfa2ddf5bb6323 ;;
  bin-aarch64 | bin-arm64) ASSET=mihomo-linux-arm64-v$VERSION.gz SHA256=ba408b317080ee265c46cb923a50018c1b82cbd708551cdd46a1e3e307396187 ;;
  # 与 GitHub Release 记录的 digest 核对过（2026-11-03）
  darwin-arm64) ASSET=mihomo-darwin-arm64-v$VERSION.gz SHA256=060b64b0f2c9a310831db0fe4adb2878de67bfa606c311813c1f13966aa504b6 ;;
  darwin-x86_64) ASSET=mihomo-darwin-amd64-v$VERSION.gz SHA256=551ae54ef8d77a5e21f7a8185a59b441fb13a0fb0514fcdef5ca2816f6f50015 ;;
  *)
    echo "install-mihomo: 不支持 $MODE / $(uname -m)" >&2
    exit 1
    ;;
esac

if [ -x "$BIN" ] && "$BIN" -v 2>/dev/null | grep -q "v$VERSION "; then
  echo "install-mihomo: 已是 v$VERSION（$BIN）"
  exit 0
fi

url="https://github.com/MetaCubeX/mihomo/releases/download/v$VERSION/$ASSET"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# 先经 GH_PROXY；失败时回退直连（D-031）。mihomo 是必需的，直连也失败（含超时）则报错退出
if [ -n "${GH_PROXY:-}" ]; then
  echo "install-mihomo: 下载 ${GH_PROXY}$url"
  curl -fsSL --retry 2 --connect-timeout 10 -m 300 -o "$tmp/$ASSET" "${GH_PROXY}$url" || {
    echo "install-mihomo: WARNING: 经 GitHub 加速代理 $GH_PROXY 下载失败，改为直连" >&2
    rm -f "$tmp/$ASSET"
  }
fi
if [ ! -s "$tmp/$ASSET" ]; then
  echo "install-mihomo: 下载 $url"
  curl -fsSL --retry 2 --connect-timeout 10 -m 300 -o "$tmp/$ASSET" "$url" || {
    echo "install-mihomo: 直连下载失败（含超时），无法安装 mihomo" >&2
    exit 1
  }
fi
# macOS 没有 sha256sum
if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$tmp/$ASSET"); else got=$(shasum -a 256 "$tmp/$ASSET"); fi
[ "${got%% *}" = "$SHA256" ] || {
  echo "install-mihomo: sha256 校验失败" >&2
  exit 1
}

if [ "$MODE" = deb ]; then
  # 包内的 /etc/mihomo/config.yaml 是 conffile；我们会用模板覆盖，dpkg 升级时保留现有版本（P-020）
  sudo env DEBIAN_FRONTEND=noninteractive dpkg -i --force-confold "$tmp/$ASSET" >/dev/null
else
  gzip -dc "$tmp/$ASSET" >"$tmp/mihomo"
  # root 所有、其他用户不可写（macOS 上由 root 的 LaunchDaemon 运行）
  sudo install -d -m 755 -o root "$MIHOMO_PREFIX/bin"
  sudo install -m 755 -o root "$tmp/mihomo" "$BIN"
fi
echo "install-mihomo: 已安装 $("$BIN" -v | head -n 1)"
