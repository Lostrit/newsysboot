# 决策记录

状态：✅ 已定 / 🟡 建议，待用户确认 / ❌ 已废弃

---

## D-001 主流程使用 `mise bootstrap`，不用 chezmoi 🟡

**日期**：2026-10-29

**决策**：stage-0 小脚本（`sh` / PowerShell）负责「mise 能跑起来之前」的事情，之后全部交给
`mise bootstrap`，用一个 bootstrap 项目（本仓库的 `mise.toml` + `mise.<模块>.toml`）声明。

**原因**：

1. 需求和 `mise bootstrap` 的声明项几乎一一对应（详见 research.md R-001）：
   apt 更新 / 安装包 → `[bootstrap.packages]`；Docker 源 → `[bootstrap.apt.sources]`；
   用户与用户组 → `[bootstrap.users]`；`/etc` 下的文件 → `[bootstrap.files]`（会自动 sudo、原子写入、`notify` 重启服务）；
   mihomo 系统服务 → `[bootstrap.services]`；默认 shell → `[bootstrap.user] login_shell`；
   dotfiles → `[dotfiles]`；订阅地址 → `[bootstrap.secrets]`；按机器选模块 → `mise.<name>.toml` + `-E`。
2. chezmoi 只管理 `$HOME` 下的文件。系统级的部分（用户、apt 源、systemd、`/etc`）都得写成
   `run_once_` / `run_onchange_` 脚本，最后等于手写一套 shell 配置管理，chezmoi 只剩模板渲染。
3. dotconfig 已经全部用 mise 管理工具，再加 mise bootstrap 不需要引入新工具，少一个要从 GitHub 下载的二进制。
4. `mise bootstrap` 有 `--dry-run` / `plan` / `status`，按差异变更，天然幂等。
5. mise 的 `url_replacements` 能把它自己的全部 GitHub 下载改写到加速代理，aqua 后端仍会校验签名。

**风险与对策**：

- 这个功能很新（2026 年），迭代很快（文档里已有计划在 2027.10.4 移除的旧名字）。
  → stage-0 锁定 mise 版本，升级时先在容器里回归；系统级逻辑尽量写成声明式配置 + 小脚本，万一要换方案也能迁移。
- Windows 上不支持 `[bootstrap.files]`（会直接失败）→ 相关条目都加 `os = "unix"`，Windows 部分单独做。
- SteamOS 有 pacman，但根分区只读 → SteamOS 模块不能声明 `pacman:` 包。

**备选**：

- chezmoi：dotfiles 模板与加密很成熟，Windows 支持好；缺点见原因 2。如果 PoC（plan 阶段 1）证明
  mise bootstrap 在关键点上不可用，就退回「chezmoi 管 dotfiles + shell 脚本管系统」。
- 纯 shell 脚本：最透明，但幂等性、预览、跨平台都要自己写。

---

## D-002 dotconfig 保持独立仓库，用 link 模式部署 🟡

**决策**：用 `[bootstrap.repos]` 把 dotconfig 克隆到 `~/.local/share/dotconfig`（地址带 `GH_PROXY`），
再用 `[dotfiles]` 把 `~/.config/<tool>` 链接（link）到克隆目录里的子目录。

**原因**：在 `~/.config` 下直接改配置就是在改 git 工作区，提交方便；dotconfig 自己的
lefthook / 开发用 mise.toml / 容器 compose 工作流都不用动。

**不同环境的差异**：大部分配置跨平台通用。确实不同的少数文件（npmrc 镜像、herdr 的 shell 路径等）
改成 mise 的 `mode = "template"`，或者拆成「通用部分 + 本机 `*.local` 文件」。

**备选**：把 dotconfig 合并进本仓库。只有一个仓库，但会失去它独立的提交历史和容器挂载用法。

---

## D-003 XDG 变量写在 `~/.zshenv`，不写 `/etc/zsh/zshenv` 🟡

**决策**：`~/.zshenv` 只做引导：导出 `XDG_*`、`ZDOTDIR=$XDG_CONFIG_HOME/zsh`、`ZSH_COMPDUMP`，
把 `site-functions` 加进 `fpath`，读取 `GH_PROXY` 缓存。这些目录也一并创建。

**原因**：每个用户一份，不需要 root；macOS（`/etc/zshenv` 受系统升级影响）、SteamOS、容器都通用。
dotconfig 的 `.zshrc` 注释里写的是依赖 `/etc/zsh/zshenv`，这一点要同步修改（见 dotconfig-review）。

---

## D-004 「如果当前是 root 就创建普通用户」放在 stage-0 ✅

**原因**：后面的 mise 安装、`~/.config`、mise 工具都要以普通用户身份运行。stage-0 创建用户
（加入 sudo 组、设密码、复制 root 的 `authorized_keys`），然后 `sudo -iu <user>` 继续跑后面的流程。
用户名通过交互输入，也可以用 `BOOTSTRAP_USER` 环境变量直接给出（Dockerfile / 无人值守时用）。

---

## D-005 Docker 用官方 get-docker.sh 脚本（锁版本入库），通过 `DOWNLOAD_URL` 指定镜像 🟡

**决策**：把 `https://get.docker.com` 的脚本按 `SCRIPT_COMMIT_SHA` 锁定后提交到仓库，执行时设置
`DOWNLOAD_URL=<腾讯云镜像>`。已装好 Docker 时跳过。

**原因**：用户要求安装内容和官网一致；脚本本身支持 `DOWNLOAD_URL`（research.md R-003）；把脚本
放进仓库可以避免在新机器上访问 get.docker.com。

**备选**：用 `[bootstrap.apt.sources]` + `apt:docker-ce ...` 声明式安装，更幂等，
但包列表要自己跟着官方脚本维护。如果 PoC 中官方脚本有问题，再改用这种方式。
