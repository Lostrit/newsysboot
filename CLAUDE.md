# CLAUDE.md

个人新系统初始化仓库：在 macOS / SteamOS / Debian·Ubuntu（含腾讯云）/ Windows / Docker 容器中，
一条命令完成基础系统配置、代理、Docker、mise 工具与 dotfiles 部署。

## 必读

- 开始任何工作前先读 `docs/README.md`，再按需读 `docs/plan.md`（计划与架构）、`docs/progress.md`（当前进度）。
- 所有项目文档放在 `docs/` 下，使用简体中文。
- 每次工作结束前更新文档：
  - 进度变化 → `docs/progress.md`
  - 做了取舍 → `docs/decisions.md`（追加编号条目，写清「决策 / 原因 / 备选方案」）
  - 踩坑 → `docs/pitfalls.md`（现象 / 原因 / 解决）
  - 调研结论 → `docs/research.md`（结论 + 来源 + 调研日期，便于判断是否过时）

## 关键约束

- **默认国内网络**：mihomo 生效前不能假定能访问 GitHub / Docker 官网。GitHub 下载一律经由测速选出的
  `GH_PROXY` 前缀，Docker 走腾讯云镜像（内网 `mirrors.tencentyun.com`，公网 `mirrors.cloud.tencent.com`）。
- **SteamOS**：不得执行 `steamos-readonly disable`，不得用 pacman 改根分区；系统级改动只落在 `/etc`、`/var`、`/home`。
- **Docker 只装在 Linux 主机上**（SteamOS / macOS / Windows 不装）。
- **容器环境**：不装 mihomo、不装 Docker，使用宿主机代理（`host.docker.internal:7890`）；必须能在 Dockerfile 里无交互运行。
- **幂等**：所有步骤可重复执行；交互输入（用户名等）都要有环境变量 / 参数的无交互等价方式。
- **SSH 加固必须防止把自己锁在外面**：确认新用户能登录之后，才能删除 root 的公钥、禁止 root 登录（D-004）。
- 经第三方 GitHub 代理下载的脚本/二进制必须校验 sha256（或依赖 mise/aqua 的签名校验）。

## 仓库内容

- `dotfiles/`：原 `/root/dotconfig`（通过 git subtree 合并，保留了历史），以 link 方式部署到 `~/.config`。
  `/root/dotconfig` 已不再维护，不要修改它。
- 远程仓库：GitHub（公开）与 CNB 同时推送，因此**任何明文密钥都不能提交**；机密信息用 sops + age 加密后放在 `secrets/`。

## 约定

- shell 脚本：stage-0 入口用 POSIX `sh`（macOS 自带 bash 3.2、Debian 最小镜像只有 dash），Windows 用 PowerShell。
- 缩进与换行遵循 `.editorconfig`（2 空格、LF）。
- 提交信息使用 Conventional Commits（`feat:` / `fix:` / `docs:` / `chore:`），与 dotconfig 仓库保持一致。
