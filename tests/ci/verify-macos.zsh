# tests/ci/verify-macos.zsh —— macOS 以 --dotfiles 部署后的检查（GitHub Actions，D-041；也可以在真机上运行）
st=$HOME/.local/state/bootstrap
source $st/env.sh
eval "$(mise activate zsh)"
fail=0
check() {
  if eval "$2" >/dev/null 2>&1; then print "PASS $1"; else
    print "FAIL $1"; (( fail++ ))
    # GitHub Actions 的注解可以匿名读取（作业日志不行）；附上命令的输出
    [[ -n $GITHUB_ACTIONS ]] && print -r -- "::error title=FAIL $1::${${$(eval "$2" 2>&1 | tail -n 15)//\%/%25}//$'\n'/%0A}"
  fi
}
print "macOS $(sw_vers -productVersion) $(uname -m)  MISE_DISABLE_TOOLS=$MISE_DISABLE_TOOLS"

check "BOOTSTRAP_ROLE=macos"            "[[ \$BOOTSTRAP_ROLE == macos ]]"
# 启用的工具都能运行（D-036）
for t in bat fd rg starship atuin fzf jq micro vivid nvim node bun lazygit gh fnox age; do
  check "工具 $t" "mise which $t && \$(mise which $t) --version"
done
for t in eza delta; do
  check "工具 $t（Homebrew）" "[[ \$(command -v $t) == /opt/homebrew/* || \$(command -v $t) == /usr/local/* ]] && $t --version"
done
# 排除的工具 mise 不提供（runner 上可能另有系统自带的，所以用 mise which 判断）
for t in tmux herdr claude btop eza delta; do
  check "不启用 $t" "! mise which $t"
done
check "jq 配色（mise [env]）"           "[[ \$JQ_COLORS == 38\\;2\\;* ]]"
check "gh 只链接 config.yml"            "[[ -L ~/.config/gh/config.yml && ! -L ~/.config/gh ]]"
check "btop 配置已链接"                 "[[ -L ~/.config/btop ]]"
for s in Regular Italic Bold BoldItalic; do
  check "字体 $s (D-039)" "[[ -f ~/Library/Fonts/MapleMonoNormal-NF-CN-$s.ttf ]]"
done
check "zsh 启动无输出"                  "[[ -z \"\$(zsh -i -c exit 2>&1 </dev/null)\" ]]"
check "nvim 插件已预装"                 "(( \$(ls ~/.local/share/nvim/lazy | wc -l) >= 30 ))"
check "仓库工作区干净"                  "[[ -z \"\$(git -C \$BOOTSTRAP_DIR status --porcelain)\" ]]"
print "==> FAIL $fail"
exit $fail
