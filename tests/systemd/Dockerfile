# tests/systemd/Dockerfile — 带 systemd 的 Debian 13，模拟「主机」（mihomo / docker / sshd）
# 只预装 systemd 与 openssh-server，其余保持官方镜像的状态（默认源、无 curl）
FROM debian:13
RUN sed -i 's#http://deb.debian.org#http://mirrors.cloud.tencent.com#g' /etc/apt/sources.list.d/debian.sources \
 && apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends systemd systemd-sysv dbus openssh-server >/dev/null \
 && rm -rf /var/lib/apt/lists/* \
 && sed -i 's#http://mirrors.cloud.tencent.com#http://deb.debian.org#g' /etc/apt/sources.list.d/debian.sources \
 && printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/50-cloud-init.conf \
 && install -d -m 700 /root/.ssh \
 && printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnlyForBootstrapTests test@bootstrap\n' > /root/.ssh/authorized_keys \
 && chmod 600 /root/.ssh/authorized_keys
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
