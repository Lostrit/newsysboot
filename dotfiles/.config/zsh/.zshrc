# ============================================================
#  $ZDOTDIR/.zshrc  —  zsh_unplugged 版（替代 antigen）
#  依赖 /etc/zsh/zshenv 已导出 XDG_*、ZDOTDIR、ZSH_COMPDUMP、fpath
# ============================================================

# ------------------------------------------------------------
# 0. 目录与基础变量
# ------------------------------------------------------------
: ${ZPLUGINDIR:=$XDG_DATA_HOME/zsh/plugins}
# GH_PROXY 形如 https://ghproxy.example/ （带尾斜杠），未设置时直连
: ${ZPLUGIN_GIT_BASE:=${GH_PROXY}https://github.com/}

() {
  local -a dirs=(
  "$ZPLUGINDIR"
  "$XDG_CACHE_HOME"/zsh
  "$XDG_STATE_HOME"/zsh
  "$XDG_CACHE_HOME"/fsh
  )
  mkdir -p -- "${dirs[@]}"
}

# fast-syntax-highlighting 默认把主题缓存写进插件目录，挪到 XDG cache
export FAST_WORK_DIR="$XDG_CACHE_HOME/fsh"

# ------------------------------------------------------------
# 1. 插件管理函数（zsh_unplugged，含 bug 修复）
# ------------------------------------------------------------

## ? 克隆插件、定位入口文件、source 它、并加入 fpath
## ? 用法: plugin-load [-d] <user/repo>[@<ref>] ...
## ?   -d        若 zsh-defer 可用则延迟加载（仅对纯 widget 类插件安全）
## ?   @<ref>    固定到某个 commit sha / tag / 分支，用于可重现构建
function plugin-load {
  local defer=0
  [[ "$1" == "-d" ]] && { defer=1; shift }

  local plugin repo ref plugdir initfile
  local -a clone_args initfiles

  for plugin in "$@"; do
    # 每轮必须重置，否则带 @ref 的插件会污染后续插件（原版 snippet 的 bug）
    repo="$plugin"
    ref=""
    clone_args=(-q --depth 1 --recursive --shallow-submodules)

    if [[ "$plugin" == *'@'* ]]; then
      repo="${plugin%@*}"
      ref="${plugin#*@}"
      clone_args=(-q --depth 1 --recursive --shallow-submodules --no-checkout)
    fi

    plugdir="$ZPLUGINDIR/${repo:t}"
    initfile="$plugdir/${repo:t}.plugin.zsh"

    if [[ ! -d "$plugdir" ]]; then
      print -u2 "Cloning $repo ..."
      git clone "${clone_args[@]}" "${ZPLUGIN_GIT_BASE}${repo}" "$plugdir" || {
        print -u2 "  clone failed: $repo"
        continue
      }
      if [[ -n "$ref" ]]; then
        git -C "$plugdir" fetch -q --depth 1 origin "$ref" \
          || git -C "$plugdir" fetch -q origin "$ref"
        git -C "$plugdir" checkout -q FETCH_HEAD || {
          print -u2 "  checkout '$ref' failed: $repo"
          continue
        }
      fi
    fi

    if [[ ! -e "$initfile" ]]; then
      initfiles=($plugdir/*.{plugin.zsh,zsh-theme,zsh,sh}(N))
      (( $#initfiles )) || { print -u2 "No init file found '$repo'."; continue }
      ln -sf "$initfiles[1]" "$initfile"
    fi

    fpath+="$plugdir"
    if (( defer )) && (( $+functions[zsh-defer] )); then
      zsh-defer . "$initfile"
    else
      . "$initfile"
    fi
  done
}

## ? 更新所有非固定版本的插件
function plugin-update {
  local plugdir
  for plugdir in $ZPLUGINDIR/*(/N); do
    print "Updating ${plugdir:t} ..."
    git -C "$plugdir" pull -q --ff-only --recurse-submodules 2>/dev/null \
      || print -u2 "  skipped（detached HEAD / 已固定版本）"
  done
  plugin-compile
}

## ? 预编译插件为 .zwc，降低启动开销（建议在镜像 build 期跑一次）
function plugin-compile {
  autoload -Uz zrecompile
  local f
  for f in $ZPLUGINDIR/*/*.zsh(N); do
    zrecompile -pq "$f"
  done
}

# ------------------------------------------------------------
# 2. mise —— 必须最先，后面所有 $+commands 判断都依赖它注入的 PATH
# ------------------------------------------------------------
(( $+commands[mise] )) && eval "$(mise activate zsh)"

# ------------------------------------------------------------
# 3. 环境变量 / 颜色
#    LS_COLORS 必须在下面的 completion zstyle 之前生成
# ------------------------------------------------------------
(( $+commands[less] )) && export PAGER=less
(( $+commands[vivid] )) && export LS_COLORS="$(vivid generate catppuccin-mocha)"

# ------------------------------------------------------------
# 4. compinit 之前的插件（只贡献 fpath，绝不能 defer）
# ------------------------------------------------------------
plugin-load romkatv/zsh-defer
plugin-load zsh-users/zsh-completions

# 自定义函数：fpath 只对补全和 autoload 过的函数有效
for _f in "${XDG_CONFIG_HOME}"/zsh/functions/*(N-.:t); do
  [[ $_f == _* ]] || autoload -Uz "$_f"
done
unset _f

# ------------------------------------------------------------
# 5. shell 选项与键位（替代 oh-my-zsh lib/*.zsh）
# ------------------------------------------------------------
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT
setopt EXTENDED_GLOB COMPLETE_IN_WORD ALWAYS_TO_END
setopt INTERACTIVE_COMMENTS NO_BEEP NO_FLOW_CONTROL

WORDCHARS='*?_-.[]~&;!#$%^(){}<>'

bindkey -e
bindkey '^[[H'  beginning-of-line
bindkey '^[[F'  end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

# ------------------------------------------------------------
# 6. 补全系统（替代 oh-my-zsh lib/completion.zsh）
# ------------------------------------------------------------
zmodload zsh/complist

zstyle ':completion:*' matcher-list 'm:{a-zA-Z-_}={A-Za-z_-}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:warnings'     format 'No matches: %d'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"
zstyle ':completion:*' special-dirs true
# fzf-tab 要求关闭 zsh 自带菜单，改由它接管
zstyle ':completion:*' menu no

() {
  local zcd="${ZSH_COMPDUMP:-$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION}"
  autoload -Uz compinit
  # 24 小时内只做一次完整 compaudit 扫描，其余走 -C 快速路径
  if [[ -n ${zcd}(#qN.mh-24) ]]; then
    compinit -C -d "$zcd"
  else
    compinit -d "$zcd"
    touch "$zcd"
  fi
  # 编译 dump，下次加载更快
  [[ -f "$zcd" && ( ! -f "$zcd.zwc" || "$zcd" -nt "$zcd.zwc" ) ]] \
    && zcompile -R -- "$zcd.zwc" "$zcd" 2>/dev/null
}

# ------------------------------------------------------------
# 7. 外部工具初始化（注册 widget / 补全，必须在 fzf-tab 之前）
# ------------------------------------------------------------
(( $+commands[fzf] )) && source <(fzf --zsh)
(( $+commands[atuin] )) && eval "$(atuin init zsh)"
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"

# ------------------------------------------------------------
# 8. compinit 之后的插件（顺序敏感）
# ------------------------------------------------------------
plugin-load Aloxaf/fzf-tab
zstyle ':fzf-tab:*' switch-group '<' '>'
(( $+commands[eza] )) && \
  zstyle ':fzf-tab:complete:(cd|z|__zoxide_z):*' fzf-preview 'eza -1 --color=always $realpath'

plugin-load z-shell/zsh-eza

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_MANUAL_REBIND=1 # 关掉每次 precmd 重绑，明显提速
plugin-load zsh-users/zsh-autosuggestions

# fast-syntax-highlighting 必须是最后一个加载的 widget 插件
plugin-load zdharma-continuum/fast-syntax-highlighting

# ------------------------------------------------------------
# 9. 提示符
# ------------------------------------------------------------
(( $+commands[starship] )) && eval "$(starship init zsh)"
