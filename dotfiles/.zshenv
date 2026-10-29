# ~/.zshenv — 由 bootstrap 链接到仓库 dotfiles/.zshenv（D-003）
#
# zsh 最先读取的文件（所有 zsh，包括非交互式）。只做引导：XDG、ZDOTDIR、PATH、fpath，
# 以及 bootstrap 的选源结果（GH_PROXY 等）。其余配置在 $ZDOTDIR/.zshrc。

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export ZSH_COMPDUMP="$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"

typeset -U path fpath
path=("$HOME/.local/bin" $path)
fpath=("$XDG_DATA_HOME/zsh/site-functions" $fpath)

# bootstrap 写入的环境（GH_PROXY、MISE_URL_REPLACEMENTS 等），见 lib/env.sh
[[ -r "$XDG_STATE_HOME/bootstrap/env.sh" ]] && source "$XDG_STATE_HOME/bootstrap/env.sh"
