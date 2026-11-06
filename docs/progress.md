# 当前进度

更新时间：2026-11-06（最新提交见 `git log`；推送：GitHub `Lostrit/newsysboot`、CNB `xfengjing/lostrit/NewSysBoot`，由 Claude 负责）

## 一、各环境状态

| 环境 | 实现 | 验证 |
| --- | --- | --- |
| Debian / Ubuntu 主机（root 运行，新建用户） | ✅ 完整 | ✅ 腾讯云 Debian 13 真机（dev，22 项；2026-11-03 全新系统重新部署：新配置 22 项主机检查 + 真实节点 server 分流 23 项全部通过）；本地 systemd 容器（`tests/run-host.sh`，23 项） |
| Debian / Ubuntu 主机（已有 sudo 用户） | ✅ 完整（D-025） | ✅ 腾讯云 Ubuntu 24.04 真机（dev，`ubuntu` 用户，22 项）；✅ 腾讯云 Ubuntu 26.04 真机（2026-11-03，sudo-rs + uutils coreutils，22 项主机检查 + 真实节点分流 17 项，GitHub 下载经 GH_PROXY）；`TEST_SUDO_USER=1 tests/run-host.sh` |
| Docker 容器（Debian / Ubuntu） | ✅ 完整（不装 mihomo / Docker，使用注入的宿主机代理） | ✅ debian 12 / 13、ubuntu 22.04 / 24.04；dev 上的容器（注入代理 / 无代理 / 屏蔽 GitHub）；2026-11-06 `tests/container/verify.sh`（D-036、D-038：工具、locale、时区、sshd 私钥注入与登录、私钥只在内存中）全部通过 |
| `--dotfiles` 模式 | ✅ | ✅ 无 sudo 用户；dev 主机重复运行 |
| SteamOS | 🟡 第一版（D-020、D-027、D-028） | ⏳ 真机未验证，清单：[verify-steamos.md](verify-steamos.md) |
| macOS | 🟡 第一版（D-028 root LaunchDaemon + TUN、P-038） | ✅ GitHub Actions `macos-15-intel` / `macos-latest` 以 `--dotfiles` 测试（D-041，2026-11-06 全部通过；期间发现并修复 P-051、P-053）；⏳ 真机（13.7.8 Intel、mihomo），清单：[verify-macos.md](verify-macos.md) |
| Windows | 🟡 第一版（D-029 WinSW 系统服务 + TUN；D-040 不装 Git、PowerShell 7） | ✅ GitHub Actions `windows-latest`（D-041，2026-11-06 检查全部通过：工具分配、PowerShell 7 profile、PSFzf、字体、OpenSSH）；⏳ 真机（mihomo 与国内网络），清单：[verify-windows.md](verify-windows.md) |
| **真机版本矩阵**（D-032，R-015） | ✅ | ✅ Debian 12 / 13（root）、Ubuntu 22.04 / 24.04（ubuntu 用户）、Ubuntu 26.04（root，sudo-rs）全部通过；`sh tests/run-cloud.sh` 可随时重跑 |
| 阿里云 / 华为云 / 火山引擎 | 🟡 内网源探测已实现（D-006） | ⏳ 未在真机验证（华为云、火山引擎的内网域名待核实） |

## 二、已完成的功能

- **入口**：`bootstrap.sh`（`curl | sh` 管道模式、root 阶段、user 阶段）、`bootstrap.ps1`（Windows）；选择 GitHub（经加速代理）或 CNB 拉取
- **选源**（D-006）：各云内网镜像探测，否则公网测速；apt、docker-ce、Docker Hub 镜像、GitHub 加速代理；7 天缓存；
  GitHub 加速代理按 release / raw / archive / clone 真实测试后只选一次，保留主 / 备两个，失败时「主 → 备 → 直连」（D-031、D-033）；gh.qninq.cn 已排除（D-035）
- **用户与 SSH**（D-004、D-025）：root 时新建免密 sudo 用户；已有 sudo 用户时加固当前用户；确认能登录后才移走 root 公钥
- **mihomo**（D-016、D-020、D-027～D-029）：锁定版本 + sha256；节点 fnox + age 加密；三个分流场景（server / desktop / steamos）；
  Linux 主机经环境变量，本地设备默认 TUN；两次执行，代理可用后切换（含 `--dotfiles` 与容器中检测已有代理，P-028）
- **Docker**（D-005、D-013）：只在 Linux 主机安装；镜像源 + Docker Hub 镜像 + docker 组 + dockerd 代理
- **按环境分配工具**（D-036）：本地系统（macOS / Windows / SteamOS）与远程系统（Linux 主机 / 容器）；全局配置为 23 个工具的全集，
  各环境排除的写在 `lib/tool-roles.txt`（`MISE_DISABLE_TOOLS`）；新增 jq、gh、btop，fnox / age 改为全局工具（D-037）；差异见 [platforms.md](platforms.md)
- **远程系统**（D-038）：locale zh_CN.UTF-8、时区 Asia/Shanghai、openssh-server；容器另装 procps / iproute2，不装加解密工具，
  sshd 的主机私钥经 fnox 注入内存（[container.md](container.md)）
- **本地系统**：Maple Mono Normal NF CN 字体（D-039）；Windows 不装 Git、下载压缩包部署，PowerShell 7 profile 接近 zsh 体验（D-040）
- **mise 工具与 dotfiles**：dotfiles 整目录链接；zsh 工具清单 + 缓存（启动约 0.07 秒，D-010）；非交互式 shell 经 shims（评审第 9 项）
- **nvim 预装**（D-026）：网络检测通过时默认预装，否则 WARNING 跳过；`--no-nvim` / `--nvim`
- **终端 terminfo**（D-034）：Ghostty（`xterm-ghostty`）条目编译到 `/etc/terminfo`，安装 ncurses-term；zsh 中 TERM 无对应 terminfo 时回退
- **HOME 整理**（D-030）：清理云镜像预置配置与 bash 默认文件，历史 / terminfo / docker 配置移到 XDG 目录
- **dotconfig 评审**：15 项全部处理（[dotconfig-review.md](dotconfig-review.md)）
- **测试**：`tests/run.sh`、`run-dotfiles.sh`、`run-pipe.sh`、`run-host.sh`（含 `TEST_SUDO_USER`、`TEST_REAL_SECRETS`）、
  `mihomo-rules.sh`（63 项分流）、`run-windows-config.sh`、`run-macos-clt.sh`、`run-tidy.sh`（见 [usage.md](usage.md)）

## 三、下一步

- ✅ 真机版本矩阵测试已完成（R-015）。
- ✅ 备用 GitHub 加速代理（D-033）：主代理失败时先试备用代理，再直连。
- ✅ 本地 / 远程系统的工具分配与配置（D-036～D-041）。2026-11-06 验证：
  - `tests/run.sh debian:13`：检查全部通过。
  - `tests/run-host.sh`：27 项全部通过。
  - 真机 Ubuntu 22.04（ubuntu 用户）与 Debian 13（root → lostrit）：各 51 项全部通过。
  - GitHub Actions 三个作业全部通过。

## 四、需要用户参与

1. **SteamOS / macOS / Windows 真机验证**：按三份验证清单执行（暂缓）；新增的检查项在各清单的「1.5」节
2. **终端模拟器**：决定各本地系统使用的终端后，再把终端配置（字体、Catppuccin Mocha）纳入仓库
3. **其他云的真机**：阿里云、华为云（可选火山引擎）各一台全新主机跑一次（验证内网源探测与内网域名）

## 五、已知限制

- Windows 的 mihomo 服务只支持 x64；ARM64 跳过
- 主机上完整重新运行需要再次提供私钥（缺少时 mise 拒绝渲染 mihomo 配置并中止，不会覆盖现有配置）
- 云镜像预置文件的识别目前只收录腾讯云的默认内容（D-030）
- 暂不提供 mihomo 网页面板（external-controller）
- glibc < 2.39（Debian 12、Ubuntu 22.04）上 tree-sitter CLI 无法运行，nvim 没有 treesitter 语法解析器（P-043）
- 容器重启后需要重新注入 SSH 主机私钥（`/dev/shm` 会被清空，P-049）
- Windows 的检出目录是只读副本：重新运行会覆盖其中的修改（D-040）
- GitHub Actions 的 macOS 是 15，与你的 13.7.8 Intel 有差异；mihomo 与国内网络不在 CI 中测试（D-041）

## 说明

- `/root/dotconfig` 原仓库未改动；以后以本仓库的 `dotfiles/` 为准。原仓库中被 gitignore 的
  `.docker/secrets/authorized_keys` 没有被合并进来，这是预期行为。
- 开发环境：`MISE_ENV=dev mise install` 后提交会经过 lefthook 检查，提交请用 `MISE_ENV=dev mise exec -- git commit …`（P-037）。
