# 当前进度

更新时间：2026-11-03（最新提交见 `git log`；推送：GitHub `Lostrit/newsysboot`、CNB `xfengjing/lostrit/NewSysBoot`，由 Claude 负责）

## 一、各环境状态

| 环境 | 实现 | 验证 |
| --- | --- | --- |
| Debian / Ubuntu 主机（root 运行，新建用户） | ✅ 完整 | ✅ 腾讯云 Debian 13 真机（dev，22 项）；本地 systemd 容器（`tests/run-host.sh`，23 项） |
| Debian / Ubuntu 主机（已有 sudo 用户） | ✅ 完整（D-025） | ✅ 腾讯云 Ubuntu 24.04 真机（dev，`ubuntu` 用户，22 项）；`TEST_SUDO_USER=1 tests/run-host.sh` |
| Docker 容器（Debian / Ubuntu） | ✅ 完整（不装 mihomo / Docker，使用注入的宿主机代理） | ✅ debian 12 / 13、ubuntu 22.04 / 24.04；dev 上的容器（注入代理 / 无代理 / 屏蔽 GitHub） |
| `--dotfiles` 模式 | ✅ | ✅ 无 sudo 用户；dev 主机重复运行 |
| SteamOS | 🟡 第一版（D-020、D-027、D-028） | ⏳ 真机未验证，清单：[verify-steamos.md](verify-steamos.md) |
| macOS | 🟡 第一版（D-028 root LaunchDaemon + TUN、P-038） | ⏳ 真机未验证，清单：[verify-macos.md](verify-macos.md)；命令行工具等待逻辑已在容器中模拟 |
| Windows | 🟡 第一版（D-029 WinSW 系统服务 + TUN） | ⏳ 真机未验证，清单：[verify-windows.md](verify-windows.md)；PowerShell 7 语法解析通过 |
| 阿里云 / 华为云 / 火山引擎 | 🟡 内网源探测已实现（D-006） | ⏳ 未在真机验证（华为云、火山引擎的内网域名待核实） |

## 二、已完成的功能

- **入口**：`bootstrap.sh`（`curl | sh` 管道模式、root 阶段、user 阶段）、`bootstrap.ps1`（Windows）；选择 GitHub（经加速代理）或 CNB 拉取
- **选源**（D-006）：各云内网镜像探测，否则公网测速；apt、docker-ce、Docker Hub 镜像、GitHub 加速代理；7 天缓存；
  加速代理限流或失效时自动换一个重试（P-029）
- **用户与 SSH**（D-004、D-025）：root 时新建免密 sudo 用户；已有 sudo 用户时加固当前用户；确认能登录后才移走 root 公钥
- **mihomo**（D-016、D-020、D-027～D-029）：锁定版本 + sha256；节点 fnox + age 加密；三个分流场景（server / desktop / steamos）；
  Linux 主机经环境变量，本地设备默认 TUN；两次执行，代理可用后切换（含 `--dotfiles` 与容器中检测已有代理，P-028）
- **Docker**（D-005、D-013）：只在 Linux 主机安装；镜像源 + Docker Hub 镜像 + docker 组 + dockerd 代理
- **mise 工具与 dotfiles**：20 个工具；dotfiles 整目录链接；zsh 工具清单 + 缓存（启动约 0.07 秒，D-010）；非交互式 shell 经 shims（评审第 9 项）
- **nvim 预装**（D-026）：网络检测通过时默认预装，否则 WARNING 跳过；`--no-nvim` / `--nvim`
- **HOME 整理**（D-030）：清理云镜像预置配置与 bash 默认文件，历史 / terminfo / docker 配置移到 XDG 目录
- **dotconfig 评审**：15 项全部处理（[dotconfig-review.md](dotconfig-review.md)）
- **测试**：`tests/run.sh`、`run-dotfiles.sh`、`run-pipe.sh`、`run-host.sh`（含 `TEST_SUDO_USER`、`TEST_REAL_SECRETS`）、
  `mihomo-rules.sh`（63 项分流）、`run-windows-config.sh`、`run-macos-clt.sh`、`run-tidy.sh`（见 [usage.md](usage.md)）

## 三、需要用户参与

1. **dev 主机切换到新的 mihomo 配置**：dev 上运行的仍是旧版（D-027 之前）的配置；需要再放一次 age 私钥，由 Claude 完整重跑部署，
   并用真实节点验证 server 场景（GitHub 走代理、镜像源直连、国内 IP 直连）
2. **SteamOS / macOS / Windows 真机验证**：按三份验证清单执行（暂缓）
3. **其他云的真机**：阿里云、华为云（可选火山引擎）各一台全新主机跑一次（验证内网源探测与内网域名）

## 四、已知限制

- Windows 的 mihomo 服务只支持 x64；ARM64 跳过
- 主机上完整重新运行需要再次提供私钥（缺少时 mise 拒绝渲染 mihomo 配置并中止，不会覆盖现有配置）
- 云镜像预置文件的识别目前只收录腾讯云的默认内容（D-030）
- 暂不提供 mihomo 网页面板（external-controller）

## 说明

- `/root/dotconfig` 原仓库未改动；以后以本仓库的 `dotfiles/` 为准。原仓库中被 gitignore 的
  `.docker/secrets/authorized_keys` 没有被合并进来，这是预期行为。
- 开发环境：`MISE_ENV=dev mise install` 后提交会经过 lefthook 检查，提交请用 `MISE_ENV=dev mise exec -- git commit …`（P-037）。
