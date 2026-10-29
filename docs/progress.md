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

1. 创建 GitHub / CNB 仓库，把地址填入 `bootstrap.sh` 与 `bootstrap.ps1` 中的 `CHANGE_ME`（D-011），配置 git remote 并推送
2. 用真实节点验证代理切换：`TEST_REAL_SECRETS=1 FNOX_AGE_KEY=… tests/run-host.sh`（P-018）
3. 在真实的腾讯云 / 阿里云 / 华为云新机器上各跑一次（验证内网源探测，以及华为云、火山引擎的内网域名）
4. SteamOS / macOS / Windows 真机测试
5. 整理各环境的 mihomo 配置（目前只有 server 场景的模板）
6. dotconfig 评审中剩余的 ⏳ 项：herdr 配置、nvim 的 scripts/bootstrap.sh、.themes 精简、tmux 路径

## 说明

- `/root/dotconfig` 原仓库未改动；以后以本仓库的 `dotfiles/` 为准。原仓库中被 gitignore 的
  `.docker/secrets/authorized_keys` 没有被合并进来，这是预期行为。
