# 决策记录

状态：✅ 已定 / 🟡 建议，待用户确认或待 PoC 验证 / ❌ 已废弃

---

## D-001 主流程使用 `mise bootstrap` ✅

**日期**：2026-10-29（用户确认：暂定使用，遇到解决不了的问题再讨论）

**决策**：stage-0 小脚本（`sh` / PowerShell）负责「mise 能跑起来之前」的事情，之后全部交给
`mise bootstrap`，用一个 bootstrap 项目（本仓库的 `mise.toml` + `mise.<模块>.toml`）声明。

**原因**：

1. 需求和 `mise bootstrap` 的声明项几乎一一对应（research R-001）。
2. chezmoi 只管理 `$HOME`，系统级的部分都得写成 `run_once_` 脚本，最后等于手写一套配置管理。
3. dotfiles 已经全部用 mise 管理工具，不需要引入新工具。
4. 有 `--dry-run` / `plan` / `status`，按差异变更，天然幂等。
5. `url_replacements` 能把 mise 自己的 GitHub 下载改写到加速代理。

**风险与对策**：这个功能很新、迭代快 → stage-0 锁定 mise 版本；Windows 上不支持 `[bootstrap.files]` → 相关条目加 `os = "unix"`；
SteamOS 不能声明 `pacman:` 包。

**备选**：chezmoi 管 dotfiles + shell 脚本管系统。

---

## D-002 dotconfig 合并进本仓库 `dotfiles/`，用 link 方式部署 ✅

**日期**：2026-10-29（用户确认合并）

**决策**：

- 用 `git subtree add --prefix=dotfiles` 合并，保留 dotconfig 原有的 11 个提交（已完成，提交 `cece9fd`）。
- 本仓库克隆到固定位置（默认 `$XDG_DATA_HOME/bootstrap`，可以用 `BOOTSTRAP_DIR` 指定），`~/.config/<tool>` 通过 `[dotfiles]` 链接到
  `dotfiles/.config/<tool>`：在 `~/.config` 中修改配置就是在修改仓库工作区，可以直接提交。
- 需要按环境区分的少数文件改用 `mode = "template"` 渲染（渲染出来的文件不是链接，要改模板源文件）。
- 阶段 4 再整理目录：`dotfiles/` 根目录下的开发工具（`mise.toml`、`lefthook.yml`、`.vscode`）挪到仓库根目录，
  `dotfiles/docs/nvim` 挪到 `docs/nvim`，`dotfiles/.docker` 挪到 `tests/` 或 `docker/`。

---

## D-003 XDG 变量写在 `~/.zshenv` ✅

`~/.zshenv` 只做引导：导出 `XDG_*`、`ZDOTDIR=$XDG_CONFIG_HOME/zsh`、`ZSH_COMPDUMP`，读取 `GH_PROXY` 缓存。
每个用户一份，不需要 root，各平台通用。目录由 `[bootstrap.directories]` 创建。

---

## D-004 「root → 创建普通用户」放在 stage-0 ✅

**日期**：2026-10-29（用户补充要求）

步骤与安全顺序：

1. 交互输入用户名和密码（从 `/dev/tty` 读取；无人值守时用 `BOOTSTRAP_USER` / `BOOTSTRAP_PASSWORD_HASH`）。
2. `useradd -m -s <zsh 或 bash>`，`chpasswd -e` 设置密码，加入 `sudo` 组。
3. 免密 sudo：写入 `/etc/sudoers.d/90-bootstrap-<user>`（权限 0440），先用 `visudo -cf` 检查。
4. 把 root 的 `authorized_keys` 复制给新用户（目录 700、文件 600、属主改为新用户）。
5. **防止把自己锁在外面**：提示用户新开一个终端，用新用户 SSH 登录并执行 `sudo true`，确认成功后输入 yes 才继续；
   无人值守时只有显式设置 `BOOTSTRAP_HARDEN_SSH=1` 才执行后面的步骤。
6. 删除 root 的 `authorized_keys`；写入 `/etc/ssh/sshd_config.d/00-bootstrap.conf`：
   `PermitRootLogin no`、`PasswordAuthentication no`、`KbdInteractiveAuthentication no`；
   用 `sshd -t` 检查语法，用 `sshd -T` 确认实际生效的值（见 pitfalls P-005），然后 reload。
7. 以新用户身份重新执行：`sudo -iu <user> sh <脚本> --continue`。

只在有 sshd 的 Linux 主机上执行第 5、6 步；容器、macOS、SteamOS 跳过。

---

## D-005 Docker：仅 Linux 主机，使用锁定版本的 get-docker.sh + `DOWNLOAD_URL` ✅

**日期**：2026-10-29（用户确认：SteamOS / macOS / Windows 暂时不装 Docker）

- 只在 Debian / Ubuntu 主机（本地或远程，非容器）安装。
- 把 `get.docker.com` 的脚本按 `SCRIPT_COMMIT_SHA` 锁定后放进 `vendor/`，同时记录 sha256；
  执行时设置 `DOWNLOAD_URL=<D-006 选出的 docker-ce 源>`。已安装时跳过。
- 把普通用户加入 `docker` 组用 `usermod -aG`（追加，不覆盖其他附加组）。
- `daemon.json`（镜像加速）和 dockerd 的代理 drop-in 用 `[bootstrap.files]` 管理，通过 `notify` 重启 docker。

---

## D-006 apt / docker-ce 镜像源：先找内网源，没有就对公网源测速 ✅

**日期**：2026-10-29（用户要求兼容腾讯云、阿里云、华为云等）

1. **内网探测**：并行请求各家云的内网镜像，`--connect-timeout 1`、`-m 2`，请求一个必然存在的小文件
   （`debian|ubuntu/dists/<codename>/Release`、`docker-ce/linux/<distro>/gpg`）。只要返回 200 就是内网可用。
   别家云的内网域名在外部要么 DNS 解析失败（很快），要么解析得到但连不上（阿里云如此，所以连接超时一定要短），见 research R-004。
2. **公网测速**：对候选公网源，用 Range 请求下载同一个约 1MB 的文件（`curl -r 0-1048575`）测 3 次。
   只要有一次失败就淘汰（保证稳定），其余按下载速度的中位数排序。
3. **apt 源和 docker-ce 源分别选**：有的镜像没有 docker-ce（火山引擎公网源返回 404）。
4. 结果写入 `$XDG_STATE_HOME/bootstrap/mirrors.env`，作为 mise 的 `[vars]` 输入；可以用 `BOOTSTRAP_APT_MIRROR` / `BOOTSTRAP_DOCKER_MIRROR` 手动指定。
5. apt 源文件：Debian 12+ / Ubuntu 24.04+ 用 deb822 格式（`/etc/apt/sources.list.d/*.sources`），旧版本用 `sources.list`。改写前先备份原文件。

GitHub 加速代理的测速逻辑相同（参见 research R-002），并额外校验下载内容的 sha256。

---

## D-007 仓库同时推送到 GitHub 和 CNB，新机器由用户选择拉取来源 ✅

**日期**：2026-10-29

- 本地仓库的 `origin` 配置两个 `pushurl`，一次 push 推到两边。
- stage-0 的两种获取方式：
  - `curl -fsSL <GH_PROXY>https://raw.githubusercontent.com/<user>/<repo>/main/bootstrap.sh | sh`
  - `curl -fsSL https://cnb.cool/<org>/<repo>/-/git/raw/main/bootstrap.sh | sh`（CNB 的 raw 地址格式待验证）
- 脚本启动时询问从哪里 clone（GitHub 经加速 / CNB），默认用拉取脚本时的那个来源；`BOOTSTRAP_SOURCE=github|cnb` 可跳过询问。
- 两边都是公开仓库，因此仓库中不能出现明文密钥（P-004）。

---

## D-008 mihomo 配置：sops + age 加密，Tera 模板分环境 🟡

**日期**：2026-10-29

**决策**：

- 机密信息（订阅地址、手写节点、`secret`、认证信息）放在 `secrets/mihomo.sops.yaml`，用 sops + age 加密。
  文件中只有值被加密，键名保留，diff 能看出改了哪一项。
- 非机密的公共部分（DNS、规则、规则集、监听）写成一个 Tera 模板 `files/mihomo/config.yaml.tera`，
  用 `{% if %}` 根据模块的 `[vars]`（`mihomo_profile = "server" | "desktop" | "steamos"`、是否开 TUN、监听地址等）区分环境。
  由 `[bootstrap.files."/etc/mihomo/config.yaml"]`（`template = true`、`mode = "0600"`）渲染，机密信息通过 `secret()` 读取。
- **解密密钥的输入**：age 私钥本身也用口令加密后放进仓库（`secrets/age-identity.age`，用 `age -p` 生成）。
  部署时只需输入一个能记住的口令：`age -d` 解出私钥到临时文件（0600）→
  `SOPS_AGE_KEY_FILE=<临时文件> sops exec-env secrets/mihomo.sops.yaml 'mise bootstrap …'` → 删除临时文件。
  默认不在机器上保存私钥，以后重新部署时再输入一次口令。
- sops / age 本身由 mise 安装（`aqua:getsops/sops`、`aqua:FiloSottile/age`，走 GH_PROXY），在 mihomo 之前安装。

**待验证**：`sops exec-env` 对嵌套 YAML 的处理（必要时 sops 文件只用扁平的键）；`secret()` 原样插入多行内容时
YAML 缩进会出问题 → 多行的节点列表改为整体解密成单独的 proxy-provider 文件。

**备选**：fnox（mise 作者开发，`fnox exec -- mise bootstrap`，支持 age），和 mise 搭配最自然，但同样很新，作为 PoC 的对照方案。
dotenv 加密（dotenvx）不适合结构化的 YAML 配置。

**需要用户提供**：各环境当前的 mihomo 配置（脱敏后的结构），才能确定公共部分和差异部分。

---

## D-009 两种入口：完整初始化 / 只应用 dotfiles ✅

**日期**：2026-10-29

| 入口 | 适用场景 | 执行内容 |
| --- | --- | --- |
| `bootstrap.sh`（默认） | 全新机器 | stage-0 全部步骤 + 完整的 `mise bootstrap` |
| `bootstrap.sh --dotfiles`，或在已有仓库中执行 `./bin/apply` | 已初始化 / 不需要初始化的环境（公司电脑、别人的容器等） | 只 clone / 更新仓库，执行 `mise bootstrap --only repos,dotfiles,tools,task`，不需要 root，不碰系统 |

两种入口共用同一份 `mise.toml`；dotfiles 相关的声明放在一个不需要 root 的模块里，以保证第二种入口可以单独运行。

---

## D-010 工具的 shell 集成：目录交给 bootstrap，补全 / init 由 zsh 按清单缓存生成 🟡

详见 [design-zsh-tools.md](design-zsh-tools.md)。要点：

- mise 只负责安装工具；去掉每个工具 postinstall 中重复的 mkdir 和补全生成代码。
- 目录由 `[bootstrap.directories]` 声明。
- `.zshrc` 中的 `(( $+commands[x] )) && …` 改为一份 `tools.zsh` 清单；补全和 init 脚本在启动时生成并缓存，
  以工具的真实路径作为缓存键，工具升级后自动重新生成。
