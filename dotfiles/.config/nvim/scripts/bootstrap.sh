#!/bin/sh
# scripts/bootstrap.sh —— 预先安装 nvim 的插件、treesitter 语法解析器、Mason 工具与 blink.cmp 模糊匹配库（按固定版本）
#
# 用法：sh ~/.config/nvim/scripts/bootstrap.sh
#   - 适合写进 Dockerfile 或新机器初始化：一次性同步完成，之后打开 nvim 不再需要联网
#   - 每一步都会校验（scripts/bootstrap.lua）；不齐时只补装缺少的部分，最多尝试 3 次，仍失败则以非零状态码退出
#   - 需要：nvim、git、tree-sitter CLI、C 编译器、node（npm 类工具），以及能访问 GitHub 的网络：
#     GH_PROXY（GitHub 加速代理前缀）优先，失败后直连（代理或 https_proxy）
#
# NVIM_BOOTSTRAP=1 会关闭 LazyVim / Mason 的后台自动安装（lua/plugins/bootstrap.lua、lua/plugins/mason.lua），
# 避免与这里的固定版本安装同时进行。
set -eu

cfg=$(cd "$(dirname "$0")/.." && pwd)
for cmd in nvim git tree-sitter cc; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "bootstrap.sh: 缺少 $cmd" >&2
    exit 1
  }
done

export NVIM_BOOTSTRAP=1
# GitHub 加速代理（D-031）：第 1 次经 GH_PROXY，之后的尝试回退直连（有代理环境变量时即经代理）。
#   git：GIT_CONFIG_*（url.<GH_PROXY>.insteadOf），仓库中记录的 origin 仍是原始地址
#   curl：PATH 最前面放一个包装脚本，把 https://github.com/、https://raw.githubusercontent.com/ 开头的参数加上前缀
#         （treesitter 每次安装都会重新加载解析器表，无法在 Lua 中改它的地址，P-041；Mason、blink.cmp 也都用 curl 下载）
gh=${GH_PROXY:-}
real_curl=$(command -v curl)
shim=$(mktemp -d)
trap 'rm -rf "$shim"' EXIT
{
  echo '#!/bin/sh'
  echo 'for a do'
  echo "  case \"\$a\" in https://github.com/* | https://raw.githubusercontent.com/*) a=\"$gh\$a\" ;; esac"
  echo '  set -- "$@" "$a"'
  echo '  shift'
  echo 'done'
  echo "exec \"$real_curl\" \"\$@\""
} >"$shim/curl"
chmod +x "$shim/curl"
path0=$PATH
i=1
while :; do
  if [ "$i" = 1 ] && [ -n "$gh" ]; then
    echo "bootstrap.sh: 第 $i 次（GitHub 加速代理：$gh）"
    export GH_PROXY=$gh GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.${gh}https://github.com/.insteadOf" GIT_CONFIG_VALUE_0=https://github.com/
    export PATH="$shim:$path0"
  else
    [ -z "$gh" ] || echo "bootstrap.sh: WARNING: 经 GitHub 加速代理未能全部完成，第 $i 次改为直连 GitHub" >&2
    echo "bootstrap.sh: 第 $i 次（直连 GitHub）"
    export GH_PROXY= PATH="$path0"
    unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
  fi
  if nvim --headless -c "luafile $cfg/scripts/bootstrap.lua"; then
    echo "bootstrap.sh: 完成"
    exit 0
  fi
  [ "$i" -lt 3 ] || break
  i=$((i + 1))
  sleep 5
done
echo "bootstrap.sh: 3 次尝试后仍有未完成的项目" >&2
exit 1
