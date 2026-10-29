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

## 下一步

- 等待用户授权执行外部程序（P-008），然后：安装 mise → fnox 加密 `mihomo_proxies` → 安装 Docker → 阶段 1 PoC

## 说明

- `/root/dotconfig` 原仓库未改动；以后以本仓库的 `dotfiles/` 为准。原仓库中被 gitignore 的
  `.docker/secrets/authorized_keys` 没有被合并进来，这是预期行为。
