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

## 下一步

- 阶段 5–7：SteamOS / macOS / Windows（只能先写出配置，当前环境无法测试）
- 用真实节点验证代理切换（需要用户执行，见 pitfalls P-018）

## 说明

- `/root/dotconfig` 原仓库未改动；以后以本仓库的 `dotfiles/` 为准。原仓库中被 gitignore 的
  `.docker/secrets/authorized_keys` 没有被合并进来，这是预期行为。
