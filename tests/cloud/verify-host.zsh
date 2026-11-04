# tests/cloud/verify-host.zsh —— 真机部署后的主机检查（由 tests/run-cloud.sh 以部署用户在测试主机上运行）
st=$HOME/.local/state/bootstrap; u=$(id -un)
gh=$(sed -n "s/^export GH_PROXY='\(.*\)'$/\1/p" $st/env.sh); ghhost=${${gh#https://}%%/*}
check() { if eval "$2" >/dev/null 2>&1; then print "PASS $1"; else print "FAIL $1"; fi }
ghb=$(sed -n "s/^export GH_PROXY_BACKUP='\(.*\)'$/\1/p" $st/env.sh); ghbhost=${${ghb#https://}%%/*}
print "GH_PROXY: $gh  backup: $ghb"
print "os: $(. /etc/os-release; print $PRETTY_NAME) sudo: $(sudo -V | head -1) coreutils: $(ls --version 2>&1 | head -1)"
print "docker repo: $(cat /etc/apt/sources.list.d/docker.list 2>/dev/null)"
print "docker: $(docker --version 2>&1)"
check "mihomo active / enabled"        "systemctl is-active mihomo && systemctl is-enabled mihomo"
check "config: server profile, no tun" "sudo grep -q 'RULE-SET,accelerators,DIRECT' /etc/mihomo/config.yaml && ! sudo grep -q '^tun:' /etc/mihomo/config.yaml"
check "env.sh: http_proxy + GH_PROXY"  "grep -q 'http_proxy=' $st/env.sh && grep -q \"^export GH_PROXY='https\" $st/env.sh"
check "env.sh: MISE_URL_REPLACEMENTS"  "[[ -n $ghhost ]] && grep -q 'MISE_URL_REPLACEMENTS=.*$ghhost' $st/env.sh"
check "no_proxy contains GH_PROXY host" "grep -q 'no_proxy=.*$ghhost' $st/env.sh"
check "GH_PROXY_BACKUP selected (D-033)" "[[ -n $ghbhost && $ghb != $gh ]] && grep -q 'no_proxy=.*$ghbhost' $st/env.sh && grep -q \"^export GH_PROXY_BACKUP='https\" ~/.local/state/bootstrap/mirrors.env"
check "env.sh: PIP_INDEX_URL intranet" "grep -q 'PIP_INDEX_URL=.http://mirrors.tencentyun.com' $st/env.sh"
check "docker active + mirror + pull"  "systemctl is-active docker && docker info 2>/dev/null | grep -q mirror.ccs.tencentyun.com && docker pull -q hello-world"
check "dockerd proxy drop-in"          "systemctl show docker -p Environment | grep -q HTTP_PROXY=http://127.0.0.1:7890"
check "sudo nopasswd / docker group"   "sudo -n true && id -nG $u | grep -qw docker"
check "login shell zsh"                "getent passwd $u | grep -q zsh"
check "terminfo xterm-ghostty (D-034)" "[[ -e /etc/terminfo/x/xterm-ghostty ]] && TERM=xterm-ghostty tput colors | grep -qx 256 && dpkg -s ncurses-term"
check "zsh TERM fallback (D-034)"      "[[ \$(TERM=no-such-term zsh -i -c 'print -r -- \$TERM' 2>/dev/null | tail -n 1) == xterm-256color ]] && [[ \$(TERM=xterm-ghostty zsh -i -c 'print -r -- \$TERM' 2>/dev/null | tail -n 1) == xterm-ghostty ]]"
check "sshd root/password off"         "sudo /usr/sbin/sshd -T | grep -qx 'permitrootlogin no' && sudo /usr/sbin/sshd -T | grep -qx 'passwordauthentication no'"
check "root keys removed"              "! sudo test -s /root/.ssh/authorized_keys"
check "sudoers !admin_flag (or skipped)" "sudo test -f /etc/sudoers.d/00-bootstrap-no-admin-flag || ! sudo -V | grep -q 'Sudo version'"
check "home tidy"                      "[[ \"$(ls -A ~ | tr '\n' ' ')\" == '.cache .config .local .ssh .zshenv ' ]]"
check "no root-owned files in home"    "[[ -z \"$(sudo find ~ -xdev -user 0 | head -1)\" ]]"
check "checkout clean"                 "[[ -z \"$(git -C ~/.local/share/bootstrap status --porcelain)\" ]]"
check "zsh plugin origin canonical"    "git -C ~/.local/share/zsh/plugins/zsh-defer remote get-url origin | grep -qx 'https://github.com/romkatv/zsh-defer'"
check "nvim plugin origin canonical"   "git -C ~/.local/share/nvim/lazy/lazy.nvim remote get-url origin | grep -q '^https://github.com/'"
# 所有 mise 工具都能运行（捕获 glibc 版本不兼容等问题，P-043；tree-sitter 在 glibc < 2.39 上已知无法运行，单独列出）
bad=()
for t in node bun atuin bat claude delta eza fd fzf herdr micro rg starship vivid lazygit nvim; do
  out=$($t --version 2>&1 | head -1); [[ $out == *GLIBC* || $out == *"error while loading"* ]] && bad+=($t)
done
check "all mise tools run${bad:+ (FAIL: $bad)}" "(( ${#bad} == 0 ))"
print "tree-sitter: $(tree-sitter --version 2>&1 | head -1 | cut -c1-100)"
check "git conflictstyle matches git version" "s=\$(git config --get merge.conflictstyle); [[ \$s == zdiff3 || \$s == diff3 ]]"
check "nvim preinstalled"              "(( $(ls ~/.local/share/nvim/lazy | wc -l) >= 30 )) && (( $(ls ~/.local/share/nvim/mason/packages | wc -l) == 12 ))"
check "zsh startup clean (pty)"        "[[ -z \"$(script -qc 'zsh -i -c exit' /dev/null </dev/null | sed $'s/\x1b\\[[0-9;?]*[a-zA-Z]//g; s/\x1b\\][^\x07]*\x07//g' | tr -d '\r')\" ]]"
check "no key material on system"      "[[ -z \"$(sudo grep -rlsaE 'AGE-SECRET-KEY-1[0-9A-Z]{50,}' /home /var/log /tmp /dev/shm /root /run/log /etc 2>/dev/null | grep -v /age-keygen)\" ]]"
check "no key in journal"              "! sudo journalctl --no-pager -q | grep -qE 'AGE-SECRET-KEY-1[0-9A-Z]{50,}'"
print "HOME: $(ls -A ~ | tr '\n' ' ')"
