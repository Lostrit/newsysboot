#!/bin/sh
# scripts/macos-mihomo-daemon.sh — 加载 / 重启 macOS 上 mihomo 的 LaunchDaemon（D-028）
#
# mise 只管理用户级 LaunchAgent，因此由 mise.macos.toml 的 post-dotfiles hook 调用本脚本（此时配置与 plist 已写好）：
#   未加载 → launchctl bootstrap；已加载且配置 / plist / 二进制有变化 → kickstart -k 重启；否则什么都不做。
set -eu
label=bootstrap.mihomo
plist=/Library/LaunchDaemons/$label.plist
state=${XDG_STATE_HOME:-$HOME/.local/state}/bootstrap/mihomo-daemon.sha256

[ -f "$plist" ] || { echo "macos-mihomo-daemon: 缺少 $plist" >&2; exit 1; }
# 配置只有 root 可读
sum=$(sudo shasum -a 256 /opt/mihomo/config/config.yaml "$plist" /opt/mihomo/bin/mihomo | shasum -a 256 | cut -d' ' -f1)
mkdir -p "$(dirname "$state")"

if ! sudo launchctl print "system/$label" >/dev/null 2>&1; then
  sudo launchctl bootstrap system "$plist"
  echo "macos-mihomo-daemon: 已加载 $label"
elif [ "$(cat "$state" 2>/dev/null)" != "$sum" ]; then
  sudo launchctl kickstart -k "system/$label"
  echo "macos-mihomo-daemon: 配置有变化，已重启 $label"
fi
echo "$sum" >"$state"
