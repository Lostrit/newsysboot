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
# Ubuntu 的 /etc/zsh/zshrc 会先执行一次 compinit（dump 写到 $ZDOTDIR/.zcompdump，即仓库中）；
# compinit 由 .zshrc 负责，这里跳过全局的那次（P-032）
skip_global_compinit=1

typeset -U path fpath
# 非交互式 shell（ssh host 命令、cron、systemd 用户服务等）不执行 mise activate：经 shims 提供 mise 管理的工具，
# 通过 shim 运行时 mise 会带上 [env] 中的变量；交互式 shell 中 mise activate 会把工具的真实路径放在前面（评审第 9 项）
path=("$HOME/.local/bin" "$XDG_DATA_HOME/mise/shims" $path)
# shell 自身使用的变量（git commit 等会读取），shim 带不过来，与 mise 配置 [env] 保持一致
export EDITOR=micro VISUAL=micro

# 让常见工具把文件放进 XDG 目录，保持 HOME 整洁（D-030；目录由 mise.toml 的 [tasks.bootstrap] 创建）
export LESSHISTFILE="$XDG_STATE_HOME/less/history"
export PYTHON_HISTORY="$XDG_STATE_HOME/python/history"   # Python 3.13+
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
export WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"   # HSTS 记录不写 ~/.wget-hsts（P-048）
# 终端经 SSH 安装的 terminfo（如 Ghostty）：末尾的「:」表示之后继续搜索系统默认目录
# 赋值时 zsh 会重新初始化终端；TERM 没有对应的 terminfo（如 Ghostty 首次登录、sudo -i 的 TERM=unknown）时会报警告，屏蔽它（P-044）
{ export TERMINFO_DIRS="$XDG_DATA_HOME/terminfo:"; } 2>/dev/null
fpath=("$XDG_DATA_HOME/zsh/site-functions" $fpath)

# bootstrap 写入的环境（GH_PROXY、MISE_URL_REPLACEMENTS 等），见 lib/env.sh
[[ -r "$XDG_STATE_HOME/bootstrap/env.sh" ]] && source "$XDG_STATE_HOME/bootstrap/env.sh"
