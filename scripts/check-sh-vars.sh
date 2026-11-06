#!/bin/sh
# scripts/check-sh-vars.sh — 检查 sh 脚本中紧跟非 ASCII 字符的 $变量（lefthook 调用，P-051）
#
# macOS 的 /bin/sh（bash 3.2）会把「美元符号 + 变量名 + 全角括号」中全角字符的字节当作变量名的一部分，set -u 下报 unbound variable。
# 变量后面紧跟中文等非 ASCII 字符时必须写成 ${var}。
# 用法：sh scripts/check-sh-vars.sh <文件…>
[ $# -gt 0 ] || exit 0
if LC_ALL=C grep -nP '(?<!\\)\$[A-Za-z_][A-Za-z0-9_]*(?=[\x80-\xff])' "$@"; then
  echo "check-sh-vars: 上面的 \$变量 后面紧跟非 ASCII 字符，请改成 \${变量}（P-051）" >&2
  exit 1
fi
