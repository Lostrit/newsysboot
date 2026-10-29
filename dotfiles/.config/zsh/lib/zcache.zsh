# $ZDOTDIR/lib/zcache.zsh — 工具 shell 集成的生成与缓存（D-010，docs/design-zsh-tools.md）
#
#   ztool <命令> <类型> <生成命令>
#     comp  生成补全文件 _<命令>，放入 fpath（须在 compinit 之前声明）
#     env   生成需要在 compinit 之前 source 的脚本（如 LS_COLORS，补全配色会用到）
#     init  生成需要在 compinit 之后 source 的脚本（如 fzf / atuin / starship 的 init）
#
# 机器上没有该命令时直接跳过。缓存键 = 命令的真实路径（mise 的安装路径带版本号）+ 生成命令，
# 工具升级或生成命令变化时自动重新生成；命中缓存时不起任何子进程。
# 生成失败时写入失败标记，24 小时内不再重试（避免网络问题拖慢每次启动）；zcache-clear 可清空缓存。

: ${ZCACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcache}
typeset -ga _zcache_env _zcache_init
typeset -gi _zcache_comp_changed=0
fpath=("$ZCACHE_DIR/completions" $fpath)

function ztool {
  emulate -L zsh
  setopt extended_glob
  local cmd=$1 kind=$2 gen=$3 out
  (( $+commands[$cmd] )) || return 0
  case $kind in
    comp) out=$ZCACHE_DIR/completions/_$cmd ;;
    env | init) out=$ZCACHE_DIR/$kind/$cmd.zsh ;;
    *) print -u2 "ztool: 未知类型 $kind（$cmd）"; return 1 ;;
  esac
  local key="${commands[$cmd]:A}"$'\t'"$gen" stamp=$out.stamp

  if [[ ! -s $out || ! -r $stamp || "$(<$stamp)" != "$key" ]]; then
    # 失败标记：同一缓存键在 24 小时内不再重试
    if [[ -r $out.failed && "$(<$out.failed)" == "$key" && -n $out.failed(#qN.mh-24) ]]; then
      return 0
    fi
    mkdir -p -- "${out:h}"
    if eval "$gen" >|"$out.tmp" 2>/dev/null && [[ -s $out.tmp ]]; then
      mv -f -- "$out.tmp" "$out"
      print -r -- "$key" >|"$stamp"
      rm -f -- "$out.failed"
      [[ $kind == comp ]] && _zcache_comp_changed=1
    else
      rm -f -- "$out.tmp"
      print -r -- "$key" >|"$out.failed"
      print -u2 "ztool: 生成 $cmd 的 $kind 失败（24 小时后重试，或执行 zcache-clear）"
      return 0
    fi
  fi
  case $kind in
    env) _zcache_env+=("$out") ;;
    init) _zcache_init+=("$out") ;;
  esac
}

# 清空缓存（下次启动时重新生成）
function zcache-clear {
  rm -rf -- "$ZCACHE_DIR" && print "已清空 $ZCACHE_DIR"
}
