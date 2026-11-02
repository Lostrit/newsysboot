# $ZDOTDIR/.zshenv — 继承了 ZDOTDIR 的嵌套 zsh（tmux 面板、zsh 中再启动 zsh 等）只读这个文件、不读 ~/.zshenv，
# 因此转而读取 ~/.zshenv，让所有 zsh 的引导一致（未导出的设置如 skip_global_compinit 不会被继承，P-032）。
# 顶层登录时 ZDOTDIR 尚未设置，zsh 只读 ~/.zshenv，不会递归。
[[ -r "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
