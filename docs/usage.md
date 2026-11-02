# 使用说明

## 全新机器

```sh
# GitHub（经加速代理，D-011）
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/Lostrit/newsysboot/main/bootstrap.sh | sh
# CNB（⚠️ 仓库目前未公开，匿名访问返回 404，见 progress.md）
curl -fsSL https://cnb.cool/xfengjing/lostrit/NewSysBoot/-/git/raw/main/bootstrap.sh | sh
```

仓库：GitHub `https://github.com/Lostrit/newsysboot`、CNB `https://cnb.cool/xfengjing/lostrit/NewSysBoot`。

流程：检测环境 → 选源测速 → apt 换源与基础包 → （root 时）创建普通用户、SSH 加固 → 以普通用户检出仓库到
`~/.local/share/bootstrap` → 安装 mise → `mise bootstrap`（包、文件、服务、dotfiles、登录 shell、工具）。

## 已初始化的环境：只部署 dotfiles

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/Lostrit/newsysboot/main/bootstrap.sh | sh -s -- --dotfiles
# 或在已有的检出中
sh ~/.local/share/bootstrap/bootstrap.sh --dotfiles
```

不需要 root / sudo，不改系统、不改登录 shell，只创建用户目录、链接 dotfiles、安装 mise 工具。

## 日常

- 修改 `~/.config/<tool>` 中的配置就是在修改 `~/.local/share/bootstrap/dotfiles/.config/<tool>`，在仓库中提交即可。
- 重新应用：`sh ~/.local/share/bootstrap/bootstrap.sh`（幂等）。
- 只重新测速：加 `--reprobe`。

## 选项与环境变量

| 选项 / 变量 | 说明 |
| --- | --- |
| `--dotfiles` | 只部署 dotfiles 与工具 |
| `--source github\|cnb` / `BOOTSTRAP_SOURCE` | 拉取来源（管道模式） |
| `--dir` / `BOOTSTRAP_DIR` | 检出目录，默认 `$XDG_DATA_HOME/bootstrap` |
| `--env a,b` / `BOOTSTRAP_ENV` | 覆盖自动检测的模块（debian、container、mihomo、docker、steamos、macos） |
| `--skip <parts>` / `BOOTSTRAP_SKIP` | 传给 `mise bootstrap --skip`，如 `tools` |
| `--dry-run` | `mise bootstrap` 只预览 |
| `--reprobe` / `BOOTSTRAP_REPROBE=1` | 忽略选源缓存（默认有效期 7 天） |
| `--harden-ssh` | 单独执行 SSH 加固 |
| `BOOTSTRAP_USER` | root 运行时要创建的用户；无终端时必填（D-015） |
| `BOOTSTRAP_PASSWORD` / `BOOTSTRAP_PASSWORD_HASH` | 新用户密码（明文经 chpasswd 处理 / 已哈希）；都没有且无终端时锁定密码 |
| `BOOTSTRAP_ALLOW_ROOT=1` | root 运行时不创建用户，直接以 root 继续 |
| `BOOTSTRAP_HARDEN_SSH=1` | 无人值守时也执行 SSH 加固 |
| `BOOTSTRAP_NONINTERACTIVE=1` | 视为没有终端，不做任何询问 |
| `FNOX_AGE_KEY` | age 私钥（解密 mihomo 配置）；不设置时交互输入 |
| `BOOTSTRAP_APT_MIRROR` / `BOOTSTRAP_DOCKER_MIRROR` / `BOOTSTRAP_DOCKER_REGISTRY_MIRRORS` / `GH_PROXY` | 手动指定选源结果（GH_PROXY 设为空表示直连） |
| `BOOTSTRAP_REPO` | 仓库地址（本地测试可用路径） |
| `BS_DEBUG=1` | 显示测速明细和完整的 apt 输出 |

## Dockerfile 中使用

```dockerfile
ARG BOOTSTRAP_USER=dev
RUN BOOTSTRAP_USER=$BOOTSTRAP_USER BOOTSTRAP_NONINTERACTIVE=1 sh /path/to/bootstrap.sh
```

容器中自动只启用 `debian,container` 模块：不装 mihomo 和 Docker，使用宿主机代理（由编排注入 `http_proxy`）。

## 测试

```sh
tests/run.sh debian:13               # 完整流程（root → 新用户），执行两次检查幂等
tests/run.sh ubuntu:24.04 --skip tools
tests/run-dotfiles.sh debian:13      # --dotfiles 模式（无 sudo 用户）
tests/run-pipe.sh ubuntu:24.04       # 管道模式（curl | sh 入口，没有 git、没有终端）
tests/run-host.sh                    # 主机流程（systemd 特权容器：mihomo、docker、SSH 加固；测试密钥 + 假节点）
```
