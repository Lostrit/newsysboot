# 各平台差异

更新时间：2026-11-06。说明各系统的定位、安装的工具与配置，以及它们之间的差异。
取舍的原因见 [decisions.md](decisions.md) 的 D-036～D-041；容器的使用与机密注入见 [container.md](container.md)。

## 1. 定位

| 分类 | 系统 | 用途 | 使用方式 |
| --- | --- | --- | --- |
| 本地系统 | macOS | 本地开发主力机（Intel MacBook Pro，macOS 13.7.8） | 图形界面，作为客户端 |
| 本地系统 | Windows | Windows 相关的开发调试 | 图形界面，作为客户端 |
| 本地系统 | SteamOS | 外出时的便携设备，主要用来连接远程系统 | 图形界面（桌面模式），作为客户端 |
| 远程系统 | Linux 主机（Debian / Ubuntu） | 远程开发机：代码仓库管理、主 AI Agent、主要的编写与查看工作 | 经 SSH 使用终端 |
| 远程系统 | Debian 容器（运行在 Linux 主机上） | 辅助开发环境：环境隔离、实验性开发与验证、临时任务 | 经 SSH 使用终端 |

部署时由 `lib/roles.sh` 的 `bs_role` 判断环境（`macos` / `steamos` / `host` / `container`；Windows 由 `bootstrap.ps1` 固定为 `windows`），
结果写入 `~/.local/state/bootstrap/env.sh` 的 `BOOTSTRAP_ROLE`。

## 2. 工具

全部工具声明在 `dotfiles/.config/mise/config.toml`（版本锁定）。各环境不需要的写在 `lib/tool-roles.txt`，
部署时写入 `MISE_DISABLE_TOOLS`（mise 的 `disable_tools`：不安装、不激活）。Windows 写在用户环境变量里，其他系统写在 `env.sh` 里。

| 工具 | macOS | Windows | SteamOS | Linux 主机 | 容器 |
| --- | :-: | :-: | :-: | :-: | :-: |
| Shell 相关：starship、atuin、fzf、vivid | ✅ | ✅（PowerShell） | ✅ | ✅ | ✅ |
| 文件与搜索：eza、bat、fd、ripgrep、jq | ✅ | ✅ | ✅ | ✅ | ✅ |
| micro（默认编辑器 `EDITOR`） | ✅ | ✅ | ✅ | ✅ | ✅ |
| neovim、tree-sitter | ✅ | — | — | ✅ | ✅ |
| git | 系统自带 | — | 系统自带 | apt | apt |
| lazygit | ✅ | — | — | ✅ | ✅ |
| delta（git 的 pager） | ✅ | — | ✅ | ✅ | ✅ |
| node、bun | ✅ | — | — | ✅ | ✅ |
| tmux、herdr（终端复用） | — | — | — | ✅ | ✅ |
| claude（Claude Code CLI） | —（用桌面版） | —（用桌面版） | — | ✅ | ✅ |
| gh（GitHub CLI） | ✅ | — | — | ✅ | — |
| cnb-cli（CNB CLI，npm 包） | ✅ | — | — | ✅ | — |
| fnox（机密管理） | ✅ | 仅部署时 | 仅部署时 | ✅ | — |
| age（生成密钥） | ✅ | — | — | ✅ | — |
| btop（进程监控） | — | — | — | ✅ | — |
| PowerShell 7、PSFzf | — | ✅ | — | — | — |
| 字体 Maple Mono Normal NF CN | ✅ | ✅ | ✅ | — | — |

说明：

- **本地系统不装终端复用**：tmux / herdr 在远程系统上运行，断线后重新连接即可恢复会话。
- **Windows、SteamOS 不做重度开发**：没有运行时、nvim 和 git 相关工具，经 `ssh` 登录后用远程的 nvim 打开仓库。
  本地 nvim 也可以经 SSH 编辑远程文件（`nvim scp://…`、`--remote-ui`、remote-nvim.nvim 等），但都比不上直接用远程 nvim，所以不装（R-016）。
- **macOS 的 eza 与 delta 由 Homebrew 安装**（`scripts/macos-brew-packages.sh`，每次部署时在 mise bootstrap 之后执行）：
  - eza 没有发布 macOS 二进制，aqua 注册表要求 cargo 编译，mise 的 aqua 后端不支持。
  - delta 的 aqua 注册表不支持 Intel Mac。
  - 没有用 mise 的 `[bootstrap.packages] "brew:…"`，因为它只支持 Apple 芯片，Intel Mac 上会直接跳过（P-053）。
  - Homebrew 已不再为 macOS 13 提供预编译包时，会从源码编译，耗时较长（需在真机上确认）。
- **SteamOS 保留 delta**：系统自带 git，而 git 配置中的 pager 写死为 delta。
- **fnox「仅部署时」**：重新部署时用它解密 mihomo 节点。它不在排除清单里，所以也会出现在 PATH 中。
- **容器中没有任何加解密工具、gh 和 cnb-cli**：容器内不落盘机密（D-038）。gh 登录后会把凭据写进 `hosts.yml`，cnb-cli 同理（D-043）。
- **加解密方案**：日常开发统一用 fnox（age）。sops 与 dotenvx 都不依赖 age CLI；需要加密结构化配置文件时可以加 sops，它和 fnox 共用同一把 age 密钥（D-037）。

## 3. 配置（XDG 与 Catppuccin Mocha）

| 工具 | 配置 | 说明 |
| --- | --- | --- |
| jq | `JQ_COLORS`（mise `[env]`） | Catppuccin Mocha 的 24 位色，jq ≥ 1.7.1 |
| btop | `~/.config/btop`（整目录链接） | `btop.conf` 是 btop 1.4.8 的完整默认配置，只改了 `color_theme`；btop 退出时会改写配置，内容相同所以仓库不会出现改动。主题来自 catppuccin/btop |
| gh | `~/.config/gh/config.yml`（只链接这一个文件） | `git_protocol: ssh`、`color_labels: enabled`。登录凭据 `hosts.yml` 留在本机目录，绝不进仓库（D-037） |
| PowerShell | `~/.config/powershell/profile.ps1` | `$PROFILE` 中写入一行加载它（D-040） |

## 4. SSH

| 系统 | 客户端 | 服务端 |
| --- | --- | --- |
| macOS | 系统自带 | — |
| Windows | 系统自带 OpenSSH，缺失时以管理员身份安装（可选功能）；启用 ssh-agent 服务 | — |
| SteamOS | 系统自带（只读根分区，不能另装） | — |
| Linux 主机 | openssh-client | openssh-server，root 阶段安装并加固（D-004、D-025） |
| 容器 | openssh-client | openssh-server：主机私钥启动后注入内存，授权公钥来自 docker secrets（[container.md](container.md)） |

## 5. locale 与时区（远程系统）

- **locale**：Linux 主机与容器都生成 `en_US.UTF-8` 和 `zh_CN.UTF-8`，系统默认 `LANG=zh_CN.UTF-8`、`LANGUAGE=zh_CN:en_US`；不设置 `LC_ALL`。
  - 主机同时生成两种 locale，是因为 ssh 客户端默认会传来本地的 `LANG`（Debian 的 `SendEnv LANG LC_*`）。
  - `.zshenv` 在 `LANG` 为空时读取 `/etc/default/locale`，覆盖 `docker exec` 等不经 PAM 的场景。
- **时区**：`Asia/Shanghai`，有 systemd 时用 `timedatectl`，否则直接改 `/etc/localtime`。
- **覆盖方式**：环境变量 `BOOTSTRAP_LOCALE`、`BOOTSTRAP_LANGUAGE`、`BOOTSTRAP_TZ`；设为 `none` 时跳过。

## 6. 字体（本地系统，D-039）

Maple Mono 的 `MapleMonoNormal-NF-CN.zip`，v7.9，锁定 sha256。

- **字形**：Normal 字形，带连字，含 Nerd Font 图标和中文，hinted 版。
- **默认只装 4 个字重**：Regular、Italic、Bold、BoldItalic。压缩包里共 16 个字重，解压后约 330 MB；`BOOTSTRAP_FONT_STYLES=all` 安装全部。

| 系统 | 安装位置 |
| --- | --- |
| macOS | `~/Library/Fonts` |
| Windows | `%LOCALAPPDATA%\Microsoft\Windows\Fonts`，并在 `HKCU` 注册（不需要管理员） |
| SteamOS | `~/.local/share/fonts/MapleMono`，安装后执行 `fc-cache` |

终端模拟器的配置暂不纳入仓库，安装后请在终端设置中选用「Maple Mono Normal NF CN」。

## 7. Windows 的特殊之处（D-040）

- **不装 Git**：仓库以压缩包下载，CNB 直连，或 GitHub 经加速代理。重新运行脚本即更新，检出目录中的修改会被覆盖。
  旧版本用 git clone 检出、且本机有 Git 时，仍用 `git pull` 更新。
- **PowerShell 7**（`pwsh`）尽量接近 zsh 的体验：

  | zsh | PowerShell |
  | --- | --- |
  | mise activate | `mise activate pwsh` |
  | autosuggestions、语法高亮 | PSReadLine 的历史预测与 Catppuccin Mocha 着色 |
  | fzf-tab | PSFzf：Tab 补全用 fzf 选择，Ctrl+T 选文件，Alt+C 进入目录 |
  | atuin | `atuin init powershell` |
  | starship | `starship init powershell` |
  | zsh-eza | 同名函数 `ls`、`l`、`ll`、`llm`、`la`、`lt`、`tree` |
  | 补全缓存 | 同样按工具路径缓存到 `$XDG_CACHE_HOME\powershell` |

  系统自带的 Windows PowerShell 5.1 不加载这份配置。
- **XDG 目录**：写入用户环境变量（`XDG_CONFIG_HOME=%USERPROFILE%\.config` 等），工具配置与其他系统放在相同位置。

## 8. 测试覆盖

| 环境 | 自动测试 | 真机 |
| --- | --- | --- |
| Linux 主机 | `tests/run-host.sh`（带 systemd 的容器）、`tests/run-cloud.sh`（腾讯云 5 个版本） | ✅ dev |
| 容器 | `tests/run.sh`（含 `tests/container/verify.sh`：工具、locale、时区、sshd 注入与登录、私钥只在内存中） | ✅ dev |
| Windows | GitHub Actions `windows-latest`（`.github/workflows/local-systems.yml`） | ⏳ [verify-windows.md](verify-windows.md) |
| macOS | GitHub Actions `macos-15-intel`、`macos-latest`（`--dotfiles` 模式） | ⏳ [verify-macos.md](verify-macos.md) |
| SteamOS | 无对应 runner | ⏳ [verify-steamos.md](verify-steamos.md) |

GitHub Actions 的局限：

- **网络**：runner 在海外，直连 GitHub，不测国内网络和加速代理。
- **mihomo 服务**：需要 age 私钥，不在 CI 中测试。
- **macOS 版本**：GitHub 已停用 macOS 13 runner，用的是 macOS 15（Intel 与 Apple 芯片各一个），比你的 13.7.8 新，系统自带工具的版本可能不同。
