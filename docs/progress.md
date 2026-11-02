# 当前进度

更新时间：2026-10-29

## 已完成

- 阶段 0：git、CLAUDE.md、docs
- 评审 dotconfig（dotconfig-review.md）
- 调研：mise bootstrap、get-docker.sh、本机网络、各云 apt / docker-ce 镜像（research R-001 ~ R-005）
- 用户确认：D-001（mise bootstrap）、D-002（合并 dotconfig）、D-004（用户与 SSH）、D-005（只在 Linux 装 Docker）、
  D-006（选源）、D-007（GitHub + CNB）、D-009（两种入口）
- 用 subtree 把 dotconfig 合并到 `dotfiles/`，保留了历史（提交 `cece9fd`）
- 设计：工具的 shell 集成与 zshrc 解耦（design-zsh-tools.md，D-010）

- `vendor/get-docker.sh`（锁定 SCRIPT_COMMIT_SHA `ada7a56`，sha256 `7f966774…`），**尚未执行**
- mihomo 模板 `files/mihomo/config.yaml.tera`（由本机配置去掉机密后生成，已用 `mihomo -t` 验证）
- 机密方案选定 fnox + age（D-008、research R-006）；zsh 清单 + 缓存方案已被接受（D-010）
- 本机：用户安装了 mise 2026.10.21 和 Docker 29.9.2；已配置 Docker Hub 内网镜像（P-011）
- 根目录 `mise.toml`（fnox 1.43.0、age 1.3.2）；`fnox.toml` 中已加密 `MIHOMO_PROXIES`，加密后解密的结果与原文一致
- `vendor/mise-install.sh`（锁定 mise 2026.10.22，D-012）
- `lib/detect.sh`：环境检测 + 「容器中不装 Docker / mihomo」规则，已在主机、debian:13、ubuntu:24.04 中验证
- `files/docker/{daemon.json,http-proxy.conf}.tera`（草稿，未经 mise 渲染验证）
- 阶段 1 PoC ✅（research R-010）
- 阶段 2 ✅：`bootstrap.sh`（管道模式 / root 阶段 / user 阶段）、`lib/{common,mirrors,apt,user,ssh,stage}.sh`、
  `mise.toml` / `mise.debian.toml` / `mise.container.toml`、`dotfiles/.zshenv`、`tests/run.sh`、`tests/run-dotfiles.sh`；
  debian:12 / 13、ubuntu:22.04 / 24.04 完整流程各执行两次通过，`--dotfiles` 模式在没有 sudo 的用户下通过
- 阶段 3 ✅：`mise.mihomo.toml`、`mise.docker.toml`、`scripts/install-{mihomo,docker}.sh`、两次执行与代理切换、
  SSH 加固；`tests/run-host.sh`（带 systemd 的特权容器）18 项检查，两次运行均通过（使用测试密钥与假节点）
- 阶段 4 ✅：目录整理（D-002、D-019）、npm / bun 的 registry 由环境注入（D-018）、zsh 工具清单 + 缓存（D-010）、
  评审中 15 项里的 10 项（dotconfig-review.md）
- 阶段 5–7（第一版，**均未在真机测试**）：SteamOS（D-020）、macOS（D-021）、Windows（D-022）；mihomo 场景化（D-023）
- 回归：容器（debian:13 ×2）、`--dotfiles`（ubuntu:24.04）、主机（18 项检查 ×2）、管道模式（ubuntu:24.04、debian:13）全部通过

## 下一步（需要用户参与）

1. ✅ 仓库已创建并推送（2026-11-02，GitHub `Lostrit/newsysboot` 公开、匿名可 clone；地址已填入 `bootstrap.sh` / `bootstrap.ps1`）。
   ✅ CNB `xfengjing/lostrit/NewSysBoot` 已设为公开（2026-11-02），匿名 clone 与 raw 地址均可访问。
   推送由 Claude 负责；本机推送 CNB 需要 HTTPS 访问令牌（cnb.cool 的 SSH 22 端口在本机连不上）
2. ✅ 用真实节点验证代理切换（2026-11-02，用户执行 `TEST_REAL_SECRETS=1 FNOX_AGE_KEY=… tests/run-host.sh`）：
   真实 `fnox.toml` 解密 → mihomo 连通 → `env.sh` 切换为代理变量并清空 `GH_PROXY` → 第二次 bootstrap 经代理安装工具；
   18 项检查两次运行全部通过，第二次运行无改动，日志与临时目录中无私钥
3. 真实云主机测试：
   - ✅ 腾讯云 Debian 13（root，2026-11-02，dev 主机）：从 CNB 一键安装 → 内网源探测、建用户、SSH 加固、mihomo（真实节点）
     代理切换、Docker（内网镜像 + Docker Hub 镜像）、20 个工具；22 项检查通过，日志中无私钥。
     主机上的容器：debian:13（注入宿主机代理）与 ubuntu:24.04（无代理）从 GitHub 一键安装，各执行两次通过。
     过程中发现并修复 P-027、P-028、P-029、P-030（用户的 zsh 目录属于 root，从其他机器登录时报错）。
   - ✅ 腾讯云 Ubuntu 24.04 + 已有免密 sudo 用户 `ubuntu`（2026-11-02，dev 主机）：以 `ubuntu` 从 GitHub 一键安装 →
     不新建用户、对 `ubuntu` 执行 SSH 加固（D-025）、mihomo 真实节点代理切换、Docker、20 个工具；22 项检查通过；
     `--dotfiles` 重新运行无改动、检出保持干净。主机上的容器 debian:13（注入宿主机代理）与 ubuntu:24.04（无代理）各执行两次通过。
     过程中发现并修复 P-031（chsh 要求密码）、P-032（Ubuntu 上补全缓存写进仓库）。
     本地对应测试：`TEST_SUDO_USER=1 tests/run-host.sh`。
   - ⏳ 阿里云 / 华为云（验证内网源探测，以及华为云、火山引擎的内网域名）
4. SteamOS / macOS / Windows 真机测试
5. 整理各环境的 mihomo 配置（目前只有 server 场景的模板）
6. ✅ dotconfig 评审剩余 5 项已全部处理（2026-11-02）：herdr 配置、nvim 预装脚本（`--nvim`，D-026）、.themes 精简、
   非交互式 shell 的 mise 工具与 EDITOR、tmux 路径

## 说明

- `/root/dotconfig` 原仓库未改动；以后以本仓库的 `dotfiles/` 为准。原仓库中被 gitignore 的
  `.docker/secrets/authorized_keys` 没有被合并进来，这是预期行为。
