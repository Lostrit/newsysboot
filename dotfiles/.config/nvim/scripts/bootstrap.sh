#!/bin/sh
# scripts/bootstrap.sh —— 预先安装 nvim 的插件、treesitter 语法解析器、Mason 工具与 blink.cmp 模糊匹配库（按固定版本）
#
# 用法：sh ~/.config/nvim/scripts/bootstrap.sh
#   - 适合写进 Dockerfile 或新机器初始化：一次性同步完成，之后打开 nvim 不再需要联网
#   - 每一步都会校验（scripts/bootstrap.lua）；不齐时只补装缺少的部分，最多尝试 3 次，仍失败则以非零状态码退出
#   - 需要：nvim、git、tree-sitter CLI、C 编译器、node（npm 类工具），以及能访问 GitHub 的网络：
#     GH_PROXY（GitHub 加速代理前缀）优先，其次备用代理 GH_PROXY_BACKUP，最后直连（代理或 https_proxy）
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
# GitHub 加速代理（D-031、D-033）：第 1 次经 GH_PROXY，第 2 次经 GH_PROXY_BACKUP（没有就直连），
# 之后回退直连（有代理环境变量时即经代理）。
#   git：GIT_CONFIG_*（url.<GH_PROXY>.insteadOf），仓库中记录的 origin 仍是原始地址
#   curl / wget：PATH 最前面放包装脚本，把 https://github.com/、https://raw.githubusercontent.com/ 开头的参数加上前缀
#         （treesitter 每次安装都会重新加载解析器表，无法在 Lua 中改它的地址，P-041；Mason、blink.cmp 也都用 curl 下载）
gh=${GH_PROXY:-}
ghb=${GH_PROXY_BACKUP:-}
shim=$(mktemp -d)
trap 'rm -rf "$shim"' EXIT
# 包装脚本从 BS_NVIM_GH 读取前缀（每次尝试可以换不同的加速代理）。
# wget 也包装：Mason 用 curl 下载失败时会改用 wget（P-048），否则它会绕过加速代理
for tool in curl wget; do
  real=$(command -v "$tool") || continue
  {
    echo '#!/bin/sh'
    echo 'for a do'
    echo '  case "$a" in https://github.com/* | https://raw.githubusercontent.com/*) a="${BS_NVIM_GH:-}$a" ;; esac'
    echo '  set -- "$@" "$a"'
    echo '  shift'
    echo 'done'
    echo "exec \"$real\" \"\$@\""
  } >"$shim/$tool"
  chmod +x "$shim/$tool"
done
path0=$PATH
# 失败的尝试中 lazy.nvim 可能改写 lazy-lock.json（部分插件 clone 失败时按最新提交记录），
# 每次尝试前恢复原文件，保证始终按锁定的版本安装（P-043）
lock=$cfg/lazy-lock.json
cp "$lock" "$shim/lazy-lock.json.orig"
trap 'cp "$shim/lazy-lock.json.orig" "$lock"; rm -rf "$shim"' EXIT
i=1
while :; do
  p=
  case "$i" in 1) p=$gh ;; 2) p=$ghb ;; esac
  if [ -n "$p" ]; then
    [ "$i" = 1 ] || echo "bootstrap.sh: WARNING: 经 GitHub 加速代理 $gh 未能全部完成，第 $i 次改用备用加速代理" >&2
    echo "bootstrap.sh: 第 $i 次（GitHub 加速代理：$p）"
    export GH_PROXY=$p BS_NVIM_GH=$p GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.${p}https://github.com/.insteadOf" GIT_CONFIG_VALUE_0=https://github.com/
    export PATH="$shim:$path0"
  else
    [ -z "$gh$ghb" ] || echo "bootstrap.sh: WARNING: 经 GitHub 加速代理未能全部完成，第 $i 次改为直连 GitHub" >&2
    echo "bootstrap.sh: 第 $i 次（直连 GitHub）"
    export GH_PROXY= PATH="$path0"
    unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 BS_NVIM_GH
  fi
  cp "$shim/lazy-lock.json.orig" "$lock"
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
