# $ZDOTDIR/tools.zsh — 工具清单：shell 集成（补全 / init 脚本）唯一需要随工具增减修改的地方（D-010）
#
# 格式：ztool <命令> <comp|env|init> '<生成命令>'
# 没有安装的工具会被跳过；init 按声明顺序在 compinit 之后加载。

# ---- 补全 ----
ztool mise      comp 'mise completion zsh'
ztool atuin     comp 'atuin gen-completions --shell zsh'
ztool bat       comp 'bat --completion zsh'
ztool bun       comp 'SHELL=zsh bun completions'
ztool delta     comp 'delta --generate-completion zsh'
ztool fd        comp 'fd --gen-completions zsh'
ztool herdr     comp 'herdr completion zsh'
ztool rg        comp 'rg --generate complete-zsh'
ztool starship  comp 'starship completions zsh'
ztool taplo     comp 'taplo completions zsh'
ztool lefthook  comp 'lefthook completion zsh'
# eza 的发布包不带补全：从与 mise 中版本一致的 tag 下载（升级 eza 时同步修改 tag）
ztool eza       comp 'curl -fsSL -m 10 "${GH_PROXY:-}https://raw.githubusercontent.com/eza-community/eza/v0.23.5/completions/zsh/_eza"'

# ---- compinit 之前加载 ----
# LS_COLORS 必须在补全的 list-colors zstyle 之前生成
ztool vivid     env  'print -r -- "export LS_COLORS=${(qq)$(vivid generate catppuccin-mocha)}"'

# ---- compinit 之后加载（顺序敏感：须在 fzf-tab 等插件之前）----
ztool fzf       init 'fzf --zsh'
ztool atuin     init 'atuin init zsh'
ztool zoxide    init 'zoxide init zsh'
ztool starship  init 'starship init zsh --print-full-init'
