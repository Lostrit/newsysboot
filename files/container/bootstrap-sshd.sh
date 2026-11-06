#!/bin/sh
# /usr/local/bin/bootstrap-sshd —— 容器中的 sshd 入口（由 bootstrap 安装，D-038；用法见 docs/container.md）
#
#   bootstrap-sshd [命令 …]   容器主进程（建议在 tini 之下）：准备授权公钥，后台等待主机私钥就绪后启动 sshd，
#                             然后执行「命令」（默认 sleep infinity，保持容器运行）
#   bootstrap-sshd load-key   从标准输入读取主机私钥，写入内存（/dev/shm），必须以 root 运行：
#                             fnox get SSH_HOST_KEY | docker compose exec -T -u root <服务> bootstrap-sshd load-key
#
# 主机私钥只放在容器的 /dev/shm（tmpfs）：不进镜像、不进容器层；容器重启后需要重新 load-key。
# 授权公钥（公开信息）：docker secrets 的 /run/secrets/ssh_authorized_keys，复制为 /etc/ssh/bootstrap_authorized_keys。
# 兼容：如果存在 /run/secrets/ssh_host_ed25519_key（compose 的 secrets 注入），也会使用它（明文会在主机磁盘上，不推荐）。
set -eu
secrets=${BOOTSTRAP_SSHD_SECRETS:-/run/secrets}
keydir=/dev/shm/bootstrap-sshd
key=$keydir/ssh_host_ed25519_key
say() { printf 'bootstrap-sshd: %s\n' "$*" >&2; }

load_key() {
  [ "$(id -u)" = 0 ] || { say "load-key 需要 root（docker exec -u root）"; exit 1; }
  umask 077
  mkdir -p "$keydir"
  cat >"$key.tmp"
  if ! ssh-keygen -y -f "$key.tmp" >"$key.pub.tmp" 2>/dev/null; then
    rm -f "$key.tmp" "$key.pub.tmp"
    say "标准输入不是有效的 SSH 私钥（需要无口令的 ed25519 私钥）"
    exit 1
  fi
  mv "$key.tmp" "$key"
  mv "$key.pub.tmp" "$key.pub"
  chmod 644 "$key.pub"
  say "主机私钥已载入内存：$(ssh-keygen -lf "$key.pub")"
}

if [ "${1:-}" = load-key ]; then
  load_key
  exit 0
fi

if [ "$(id -u)" != 0 ]; then
  say "以非 root 运行，不启动 sshd"
else
  install -d -m 755 /run/sshd
  if [ -s "$secrets/ssh_authorized_keys" ]; then
    install -m 644 "$secrets/ssh_authorized_keys" /etc/ssh/bootstrap_authorized_keys
  else
    say "没有授权公钥（docker secrets：ssh_authorized_keys），暂时无法经 SSH 登录"
  fi
  if [ -s "$secrets/ssh_host_ed25519_key" ] && [ ! -s "$key" ]; then
    load_key <"$secrets/ssh_host_ed25519_key"
  fi
  # 后台等待主机私钥就绪后启动 sshd（前台运行，日志进容器的标准错误）
  (
    i=0
    while [ ! -s "$key" ]; do
      [ $((i % 60)) -ne 0 ] || say "等待主机私钥：fnox get SSH_HOST_KEY | docker compose exec -T -u root <服务> bootstrap-sshd load-key"
      i=$((i + 1))
      sleep 1
    done
    say "启动 sshd"
    exec /usr/sbin/sshd -D -e
  ) &
fi

[ $# -gt 0 ] || set -- sleep infinity
exec "$@"
