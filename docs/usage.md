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

各系统安装的工具与配置不同（本地系统 / 远程系统，D-036），见 [platforms.md](platforms.md)；Debian 辅助开发容器见 [container.md](container.md)。

以 root 运行时新建普通用户（`BOOTSTRAP_USER`）并切换过去；以已有的 sudo 普通用户运行时（如腾讯云 Ubuntu 的 `ubuntu`）
不新建用户，需要 root 的步骤经 sudo 执行。两种情况都会对登录用户做 SSH 加固（D-004、D-025）：
交互模式下需要确认，无人值守时设置 `BOOTSTRAP_HARDEN_SSH=1`。

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
| （默认） | 最后检测 nvim 预装所需的网络（GitHub git / Releases、npm 镜像，经当前代理；有 mihomo 时在切换代理之后）：通过则预装插件、treesitter 语法解析器、Mason 工具与 blink.cmp 库（按固定版本，首次约 2 分钟）；不通过则输出 WARNING 并跳过，不影响部署结果 |
| `--no-nvim` / `BOOTSTRAP_NVIM=0` | 不预装 nvim |
| `--nvim` / `BOOTSTRAP_NVIM=1` | 不检测网络，强制预装；失败则部署失败（适合 Dockerfile） |
| `--harden-ssh` | 单独执行 SSH 加固 |
| `BOOTSTRAP_USER` | root 运行时要创建的用户；无终端时必填（D-015） |
| `BOOTSTRAP_PASSWORD` / `BOOTSTRAP_PASSWORD_HASH` | 新用户密码（明文经 chpasswd 处理 / 已哈希）；都没有且无终端时锁定密码 |
| `BOOTSTRAP_ALLOW_ROOT=1` | root 运行时不创建用户，直接以 root 继续 |
| `BOOTSTRAP_HARDEN_SSH=1` | 无人值守时也执行 SSH 加固 |
| `BOOTSTRAP_NONINTERACTIVE=1` | 视为没有终端，不做任何询问 |
| `FNOX_AGE_KEY` | age 私钥（解密 mihomo 配置）；不设置时交互输入 |
| `BOOTSTRAP_APT_MIRROR` / `BOOTSTRAP_DOCKER_MIRROR` / `BOOTSTRAP_DOCKER_REGISTRY_MIRRORS` / `GH_PROXY` | 手动指定选源结果（GH_PROXY 设为空表示直连） |
| `BOOTSTRAP_REPO` | 仓库地址（本地测试可用路径） |
| `BOOTSTRAP_PYPI_INDEX` | 手动指定 pip / uv 的 PyPI 镜像（默认：腾讯云内网时用内网地址，否则用腾讯云公网镜像） |
| `BOOTSTRAP_NO_TIDY=1` | 不整理 HOME（D-030） |
| `BOOTSTRAP_LOCALE` / `BOOTSTRAP_LANGUAGE` | 远程系统的默认 locale（默认 `zh_CN.UTF-8` / `zh_CN:en_US`；`none` 跳过，D-038） |
| `BOOTSTRAP_TZ` | 远程系统的时区（默认 `Asia/Shanghai`；`none` 跳过） |
| `BOOTSTRAP_FONTS=0` / `BOOTSTRAP_FONT_STYLES` | 本地系统不装字体 / 要装的字重（默认 `Regular Italic Bold BoldItalic`，`all` 为全部，D-039） |
| `BS_DEBUG=1` | 显示测速明细和完整的 apt 输出 |

## Dockerfile 中使用

```dockerfile
ARG BOOTSTRAP_USER=dev
RUN BOOTSTRAP_USER=$BOOTSTRAP_USER BOOTSTRAP_NONINTERACTIVE=1 sh /path/to/bootstrap.sh
```

完整示例（SSH 登录、locale、时区、主机私钥经 fnox 注入内存）见 [container.md](container.md) 与 `files/container/`。

容器中自动只启用 `debian,container` 模块：不装 mihomo 和 Docker，使用宿主机代理（由编排注入 `http_proxy`）。
注入的代理能访问 GitHub 时直接使用（并写入 `env.sh`），不可用时回退到 `GH_PROXY`（P-028）。例如：

```sh
docker run --add-host host.docker.internal:host-gateway \
  -e http_proxy=http://host.docker.internal:7890 -e https_proxy=http://host.docker.internal:7890 ...
```

宿主机的 mihomo 需要允许 Docker 网段（server 场景默认放行 `172.16.0.0/12`）。

## mihomo 配置

按场景分流（D-027）：Linux 主机 `server`、SteamOS `steamos`、macOS `desktop`，部署时自动选择。

代理接入方式（D-028）：

| 环境 | 方式 |
| --- | --- |
| Linux 远程主机 | 不开 TUN；`env.sh` 中的 `http_proxy` 等环境变量；Docker 容器注入 `http_proxy=http://host.docker.internal:7890` |
| SteamOS | TUN（系统服务） |
| macOS | TUN；root 的 LaunchDaemon `bootstrap.mihomo`（`/opt/mihomo`），日志 `/var/log/mihomo.log`；部署时 sudo 可能要求输入登录密码 |
| Windows | TUN；`bootstrap.ps1`（以管理员身份运行）部署 WinSW 系统服务 `mihomo`：程序在 `%ProgramFiles%\mihomo`，配置与日志在 `%ProgramData%\mihomo`，开机即启动（D-029） |

```sh
# 单独导出一份配置（如给其他客户端使用）
FNOX_AGE_KEY=… sh ~/.local/share/bootstrap/scripts/render-mihomo.sh desktop ~/mihomo-desktop.yaml
# 修改模板后重新生成 Windows 用的预渲染配置（lefthook 会检查是否同步）
sh scripts/gen-windows-mihomo.sh
# 验证三个场景的分流（需要 mihomo，使用假节点）
sh tests/mihomo-rules.sh
```

导出的文件包含节点信息（明文），用完请删除，不要提交或分享。

## GitHub 加速代理（D-031）

- 部署时在选源阶段选择一次：从 `lib/gh-proxies.txt` 的候选中，先测延时，再对最快的 5 个做 release / raw / archive / clone 的真实测试，
  选出 release 下载最快的一个作为 `GH_PROXY`、第二快的作为备用代理 `GH_PROXY_BACKUP`（缓存 7 天，`--reprobe` 重新选择）；都不可用时 WARNING 并直连。
- mise 工具、zsh 插件、eza 补全、mihomo 二进制、nvim 预装（插件、语法解析器、Mason、blink.cmp）都经它获取 GitHub 内容；
  有 mihomo 时也是如此。失败时先改用备用代理，再回退直连（D-033；mise / mihomo 直连仍失败则报错；nvim 预装默认 WARNING）。
- 手动指定：`GH_PROXY=https://… [GH_PROXY_BACKUP=https://…] sh bootstrap.sh`；`GH_PROXY` 设为空表示直连。
- Windows（`bootstrap.ps1`）使用同样的规则：拉取仓库后选择，结果缓存在 `%LOCALAPPDATA%\bootstrap\gh-proxy.txt`（`-Reprobe` 重新选择）。
- 维护候选列表（在国内网络、不经代理的机器上运行，约 5 分钟）：

  ```sh
  sh scripts/update-gh-proxies.sh   # 更新 lib/gh-proxies.txt 与 bootstrap.sh / bootstrap.ps1 / lib/mirrors.sh 的内置列表
  ```

- 不想再用的代理写进 `lib/gh-proxies-exclude.txt`（D-035），更新列表时不会再加回来；同时从 `lib/gh-proxies.txt` 与三处内置列表中删除。

## HOME 整理（D-030）

部署时自动整理当前用户的 HOME，最终只保留 `.cache`、`.config`、`.local`、`.ssh` 与 `.zshenv`：

| 内容 | 处理 |
| --- | --- |
| 云镜像预置的镜像源配置（腾讯云的 `~/.pip/pip.conf`、`~/.pydistutils.cfg`、`~/.npmrc`） | 内容与已知默认值一致时删除，镜像源改由 `env.sh`（`PIP_INDEX_URL`、`NPM_CONFIG_REGISTRY` 等）提供；内容不同时保留并提示 |
| `.bashrc`、`.bash_logout`、`.profile` | 与 `/etc/skel` 完全相同时删除（登录 shell 为 zsh）；被修改过时保留并提示 |
| `.bash_history`、`.lesshst`、`.python_history`、`.docker/`、`.terminfo/` | 移到 XDG 目录（`~/.local/state/…`、`~/.config/docker`、`~/.local/share/terminfo`）；目标已存在时保留原文件并提示 |
| `.sudo_as_admin_successful` | 删除；sudoers 中加入 `Defaults !admin_flag`，以后不再生成 |

之后由 `~/.zshenv`（`LESSHISTFILE`、`PYTHON_HISTORY`、`DOCKER_CONFIG`、`TERMINFO_DIRS`）与 zsh 的 `bash` 别名（`HISTFILE`）
让这些工具继续使用 XDG 目录。`~/.ssh` 必须保留在 HOME（sshd 只认这里）。

## 重新运行与机密

- 主机上完整重新运行（`bootstrap.sh`）需要再次提供 age 私钥：缺少机密时 mise 会拒绝渲染 mihomo 配置并中止，
  不会用空节点覆盖现有配置。
- 只更新 dotfiles / 工具时用 `--dotfiles`，不需要私钥；它会沿用环境中（或本机 mihomo 的）代理。

## Windows

```powershell
# 以管理员身份运行 PowerShell（部署 mihomo 服务需要管理员；-NoMihomo 跳过）
irm https://gh-proxy.com/https://raw.githubusercontent.com/Lostrit/newsysboot/main/bootstrap.ps1 | iex
# 服务管理
& "$env:ProgramFiles\mihomo\mihomo-service.exe" status   # start / stop / restart
```

注意不要同时开启其他代理客户端或 VPN 的 TUN，避免路由冲突。

- **不装 Git**：仓库以压缩包下载到 `%USERPROFILE%\.local\share\bootstrap`，重新运行即更新，检出目录中的修改会被覆盖（D-040）。
- **PowerShell 7**：完成后打开 `pwsh`，`$PROFILE` 会加载 `~/.config/powershell/profile.ps1`（starship、atuin、PSFzf、eza 别名等）。
- **SSH**：检查 OpenSSH 客户端，并启用 ssh-agent 服务（需要管理员）。
- **字体**：Maple Mono Normal NF CN 安装到当前用户，需要在终端设置中选用。
- **其他开关**：`BOOTSTRAP_FONTS=0` 不装字体；`BOOTSTRAP_LOCAL=1`（使用 `-Dir` 中已有的文件）与 `BOOTSTRAP_NO_GH_PROXY=1`（直连 GitHub）供 CI 使用。

## 测试

```sh
tests/run.sh debian:13               # 完整流程（root → 新用户），执行两次检查幂等
tests/run.sh ubuntu:24.04 --skip tools
tests/run-dotfiles.sh debian:13      # --dotfiles 模式（无 sudo 用户）
tests/run-pipe.sh ubuntu:24.04       # 管道模式（curl | sh 入口，没有 git、没有终端）
tests/run-host.sh                    # 主机流程（systemd 特权容器：mihomo、docker、SSH 加固；测试密钥 + 假节点）
TEST_SUDO_USER=1 tests/run-host.sh   # 同上，以已有的免密 sudo 普通用户运行（D-025）
sh tests/mihomo-rules.sh             # 三个场景的分流（需要 mihomo）
sh tests/run-windows-config.sh       # Windows 预渲染配置与模板同步、mihomo -t
sh tests/run-macos-clt.sh            # macOS 管道模式等待 Xcode 命令行工具安装（容器中模拟）
sh tests/run-tidy.sh                 # HOME 整理（按腾讯云 Ubuntu 主机的预置文件模拟）
pwsh -NoProfile -File tests/ps-parse.ps1 bootstrap.ps1 dotfiles/.config/powershell/profile.ps1   # PowerShell 语法
```

`tests/run.sh` 结束时运行 `tests/container/verify.sh`（工具、locale、时区、sshd 私钥注入与登录）。
Windows 与 macOS 由 GitHub Actions 测试（`.github/workflows/local-systems.yml`，D-041）。
