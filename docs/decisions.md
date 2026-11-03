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
每个用户一份，不需要 root，各平台通用。目录由 `[tasks.bootstrap]` 创建（原为 `[bootstrap.directories]`，见 D-024）。

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

## D-005 Docker：仅 Linux 主机（非容器），get-docker.sh + 镜像源 + Docker Hub 镜像 ✅

**日期**：2026-10-29（用户确认：SteamOS / macOS / Windows 不装；容器中不装，不做 Docker in Docker）

- **何时安装**：只在 Debian / Ubuntu **主机**上安装。`lib/detect.sh` 检测到容器（`/.dockerenv`、`/run/.containerenv`、
  `systemd-detect-virt -c`、cgroup）时，模块中不包含 `docker` 和 `mihomo`。已在 debian:13 / ubuntu:24.04 容器中验证。
- **安装**：`vendor/get-docker.sh`（锁定 SCRIPT_COMMIT_SHA，校验 sha256），执行时设置 `DOWNLOAD_URL=<D-006 选出的 docker-ce 源>`。
  已安装时跳过。用户已在本机用 `DOWNLOAD_URL=https://mirrors.tencentyun.com/docker-ce` 安装成功（Docker 29.9.2）。
- **Docker Hub 镜像加速**：`[bootstrap.files."/etc/docker/daemon.json"]` 由 `files/docker/daemon.json.tera` 渲染，`notify = ["docker"]`。
  镜像地址 `vars.docker_registry_mirrors` 的选择方式：
  1. 内网：腾讯云 `https://mirror.ccs.tencentyun.com`（探测 `/v2/` 返回 200 即可用）；
  2. 阿里云、华为云的镜像加速器地址是每个账号专属的，无法自动探测 → 通过 `BOOTSTRAP_DOCKER_REGISTRY_MIRRORS` 手动指定；
  3. 都没有时，对公网第三方镜像测速（research R-009），只作为辅助手段，不保证长期可用。
- **回源兜底**：启用 mihomo 模块时，额外写入 `/etc/systemd/system/docker.service.d/http-proxy.conf`
  （`files/docker/http-proxy.conf.tera`），镜像不可用时 dockerd 经本机 mihomo 访问 Docker Hub；镜像域名加入 `NO_PROXY`。
- **docker 组**：用 `usermod -aG docker <user>` 追加，不覆盖其他附加组。

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

## D-008 机密信息：fnox + age（备选 sops），mihomo 用 Tera 模板分环境 ✅

**日期**：2026-10-29（用户确认：部署时直接输入 age 私钥；fnox 已实测可以加密和解密）

**决策**：

- 用 fnox 的 age provider，在仓库根目录的 `fnox.toml` 中保存密文（每个机密一个条目，可以安全提交）；
  recipient 使用用户提供的公钥 `age17ft09zwqg3kd3yvclzp6l3wejln9c8lzc5t68g39ydgv8a79tfdsyshnxq`。
- 部署时 stage-0 从 `/dev/tty` 读取 age 私钥（不回显），以 `FNOX_AGE_KEY` 传给 `fnox exec -- mise bootstrap …`，
  不写入磁盘；无人值守时直接设置 `FNOX_AGE_KEY` 环境变量。
- mise 一侧只声明 `[bootstrap.secrets] mihomo_proxies = "MIHOMO_PROXIES"`，模板中用 `{{ secret(name="mihomo_proxies") }}` 读取。
  **加密工具对 mise 来说只是「提供环境变量」**，以后换成 sops，只需要改 stage-0 里的一行命令。
- mihomo 模板 `files/mihomo/config.yaml.tera`：由当前主机的配置生成。机密的 `proxies:` 段整体作为一个机密，
  放在模板第 0 列插入（避免多行内容的缩进问题）；监听相关设置改为 `[vars]`；策略组改为
  「节点（`include-all-proxies`）→ PROXY [节点, DIRECT]」，模板不再依赖具体节点名。已用 `mihomo -t` 验证渲染结果。

**和 sops 的对比**：见 research R-006。

---

## D-009 两种入口：完整初始化 / 只应用 dotfiles ✅

**日期**：2026-10-29

| 入口 | 适用场景 | 执行内容 |
| --- | --- | --- |
| `bootstrap.sh`（默认） | 全新机器 | stage-0 全部步骤 + 完整的 `mise bootstrap` |
| `bootstrap.sh --dotfiles`，或在已有仓库中执行 `./bin/apply` | 已初始化 / 不需要初始化的环境（公司电脑、别人的容器等） | 只 clone / 更新仓库，执行 `mise bootstrap --only repos,dotfiles,tools,task`，不需要 root，不碰系统 |

两种入口共用同一份 `mise.toml`；dotfiles 相关的声明放在一个不需要 root 的模块里，以保证第二种入口可以单独运行。

---

## D-010 工具的 shell 集成：目录交给 bootstrap，补全 / init 由 zsh 按清单缓存生成 ✅

详见 [design-zsh-tools.md](design-zsh-tools.md)。要点：

- mise 只负责安装工具；去掉每个工具 postinstall 中重复的 mkdir 和补全生成代码。
- 目录由 bootstrap 声明（现为 `[tasks.bootstrap]`，见 D-024）。
- `.zshrc` 中的 `(( $+commands[x] )) && …` 改为一份 `tools.zsh` 清单；补全和 init 脚本在启动时生成并缓存，
  以工具的真实路径作为缓存键，工具升级后自动重新生成。

---

## D-011 本地开发不依赖远程仓库 ✅

**日期**：2026-10-29

仓库名称只在两个地方用到：`curl | sh` 一行命令中的下载地址，以及 stage-0 中 `git clone` 的地址。
这两处都做成变量（`BOOTSTRAP_REPO_GITHUB`、`BOOTSTRAP_REPO_CNB`，附带默认值）；本地测试时用 `BOOTSTRAP_REPO=file:///…`
或把工作区挂载进容器。远程仓库创建后再填默认值、配置 git remote。

---

## D-012 用锁定版本的 mise.run 安装脚本安装 mise ✅

**日期**：2026-10-29

**决策**：把 `https://mise.run` 的脚本放进 `vendor/mise-install.sh`（记录 sha256），执行时设置
`MISE_VERSION=<脚本内置的版本>`（当前为 2026.10.22）。

**原因**（research R-008）：脚本从 CDN `mise.jdx.dev` 下载安装包，但**只有脚本内置的那个版本使用内嵌的校验值**；
指定其他版本时，校验值要从 GitHub Releases 下载，在国内可能失败。把脚本锁定后，版本和校验值都固定下来，
整个安装过程都不需要访问 GitHub。升级 mise = 更新 vendor 中的脚本 + 修改版本号，并在容器中回归测试。

已经装好 mise 的机器（例如当前主机上的 2026.10.21）不受影响；stage-0 只在 `mise` 不存在，或版本低于要求时才安装。

---

## D-013 仓库根目录 `mise.toml` 中固定 fnox / age 的版本 ✅

**日期**：2026-10-29

`fnox = "1.43.0"`、`age = "1.3.2"`。fnox 部署时就需要；age CLI 只用来生成和查看密钥。
mise 默认不选择刚发布不久的版本（1.44.0 因此被跳过），这正符合「锁定版本」的原则。

---

## D-014 容器测试：屏蔽 GitHub 直连，并使用工作区快照 ✅

**日期**：2026-10-29

- 当前主机直连 GitHub 时好时坏，不能代表国内网络。`tests/run.sh` 用 `--add-host` 把 github.com、api.github.com、
  raw / objects / release-assets.githubusercontent.com、codeload.github.com 都指向 0.0.0.0，强制所有 GitHub 下载经由 GH_PROXY。
- user 阶段用 `git clone` 复制仓库，只会带上已提交的内容；测试脚本先把工作区（含未提交、未跟踪但没被忽略的文件）提交到临时仓库，再挂载进容器。

## D-015 root 用户在无人值守时必须指定用户名 ✅

**日期**：2026-10-29

以 root 运行且没有终端时，必须设置 `BOOTSTRAP_USER`（否则报错退出）；确实要以 root 继续（例如一次性的构建容器）时设置 `BOOTSTRAP_ALLOW_ROOT=1`。
没有提供密码时锁定密码：仍然可以用 SSH 公钥登录，sudo 免密。

---

## D-016 mihomo 用官方 deb 包安装，版本与 sha256 固定在脚本中 ✅

**日期**：2026-10-29

`scripts/install-mihomo.sh` 固定 v1.19.33（与当前主机一致），经 GH_PROXY 下载并校验 sha256，然后 `dpkg -i --force-confold`。
deb 包自带 systemd unit，不需要我们维护 unit 文件。升级 = 修改脚本中的版本号和 sha256。
SteamOS / macOS 不能用 deb 包，到第 5、6 阶段再单独处理。

## D-017 有 mihomo 时分两次执行，mihomo 可用后改为经本机代理 ✅

**日期**：2026-10-29

第一次 `--only accounts,files,packages,services`，然后最多等 20 秒，经 `http://127.0.0.1:7890` 访问 GitHub：
- 能访问：在 `env.sh` 中写入 `http_proxy` / `https_proxy` / `all_proxy` / `no_proxy`（以后由 `~/.zshenv` 加载），清空 GH_PROXY，再执行完整流程；
- 不能访问（节点不可用等）：给出警告，继续使用 GH_PROXY。

`no_proxy` 包含本机、各家云的内网域名，以及选中的 apt / docker 镜像。

---

## D-018 npm / bun 的 registry 由 bootstrap 按环境注入 ✅

**日期**：2026-10-29

dotfiles 中的 npmrc、`.bunfig.toml` 不再写 registry（原来写死了腾讯云内网地址，离开腾讯云就无法使用）。
stage-0 在 `env.sh` 中写入 `NPM_CONFIG_REGISTRY` 和 `BUN_CONFIG_REGISTRY`：apt 源选中腾讯云内网时用
`https://mirrors.tencentyun.com/npm/`，否则用 `https://mirrors.cloud.tencent.com/npm/`；可以用 `BOOTSTRAP_NPM_REGISTRY` 覆盖。
2026-10-29 实测：两个地址都可用（0.2s），npmmirror 1.6s，阿里云内网 npm 在腾讯云上不可访问。
链接方式部署的目录（如 `~/.config/npm`）里的文件不能做模板，所以统一改用环境变量来区分环境。

## D-019 开发工具放在 `mise.dev.toml` ✅

**日期**：2026-10-29

原 dotconfig 根目录的 `mise.toml`（taplo / lefthook / prettier）移到本仓库根目录的 `mise.dev.toml`：只有 `MISE_ENV=dev` 时才加载，
部署的机器不会安装这些工具。`lefthook.yml` 移到仓库根目录（lefthook 要求放在 git 根目录），glob 改为 `dotfiles/.config/...`。

---

## D-020 SteamOS：mihomo 用独立二进制，放在 /var/lib/mihomo 🟡（未在真机验证）

> 真机验证清单：verify-steamos.md

**日期**：2026-10-29

SteamOS 的根分区只读，不能用 pacman，也不能写 `/usr`。二进制装在 `/var/lib/mihomo/bin`（`/var` 可写，系统升级后保留），
unit 文件写入 `/etc/systemd/system/mihomo.service`（`/etc` 是 overlay，升级后保留），其余与 Linux 主机的 mihomo 模块共用。
SteamOS 不声明任何包；git / curl / zsh 依赖系统自带（待在真机核实）。

## D-021 macOS：mihomo 以用户 LaunchAgent 运行 ⛔（已被 D-028 取代）

**日期**：2026-10-29

mise 的系统服务只支持 Linux，所以 macOS 不加载 `mise.mihomo.toml`，而是在 `mise.macos.toml` 中：`brew:mihomo` 安装、
`[dotfiles]` 模板把配置渲染到 `~/.config/mihomo/config.yaml`（0600，与 Linux 共用模板和机密）、`[bootstrap.macos.launchd.agents.mihomo]` 运行。
只监听本机（系统代理 / 环境变量方式）；TUN 模式需要 root 的 LaunchDaemon，暂不支持。
Homebrew 由 stage-0 经清华大学镜像安装（`lib/macos.sh`）。

## D-022 Windows 第一版只部署 dotfiles 与工具 ⛔（mihomo 部分已被 D-029 取代）

**日期**：2026-10-29

`bootstrap.ps1`：winget 安装 Git 与 mise → GitHub 代理测速 → 检出仓库 → `mise bootstrap --only dotfiles,tools`。
mise 的 `[bootstrap.files]` 在 Windows 上不可用；mihomo 与 Docker 在 Windows 上暂不处理。
dotfiles 的 mise 全局配置中有些工具（如 tmux）没有 Windows 版本，实际使用前需要按 `os` 过滤。

## D-023 mihomo 的监听设置按场景传入 ✅

**日期**：2026-10-29

`mise.mihomo.toml` 的 `[vars]` 从环境变量取值（`BOOTSTRAP_MIHOMO_PORT / _ALLOW_LAN / _BIND / _LAN_IPS`），由 stage-0 的 `bs_mihomo_profile` 设置：
Linux 主机为 server（`allow-lan: true`，只放行本机和 Docker 网段），SteamOS / macOS 为 desktop（只监听 127.0.0.1）。
用环境变量而不是在多个模块里重复定义 `[vars]`，避免依赖 mise 多个环境文件之间的优先级。

## D-024 用户目录改由收尾任务创建 ✅

**日期**：2026-11-02

- **决策**：`~/.config`、`~/.local/bin`、zsh 与 node 的目录不再写在 `[bootstrap.directories]`，改为 `[tasks.bootstrap]` 第一步以当前用户 `mkdir -p`；
  root 阶段切换用户前，把用户家目录中属于 root 的文件改回用户所有。
- **原因**：有系统模块时 mise 以 sudo 执行整个 files 阶段，没写 owner 的目录归 root 所有（P-030）；
  `owner` / `group` 不支持模板，而用户名因机器而异，不能写死。
- **备选方案**：
  - stage-0 生成一份带 owner 的本地 mise 配置：多一层生成逻辑，`mise bootstrap` 单独使用时又会缺失。
  - 在 stage-0 的 shell 中创建：只在经 `bootstrap.sh` 运行时生效；收尾任务对任何 `mise bootstrap` 都生效。

## D-025 以已有的 sudo 普通用户运行时，同样执行 SSH 加固 ✅

**日期**：2026-11-02

- **决策**：以普通用户运行 `bootstrap.sh`（如腾讯云 Ubuntu 的 `ubuntu` 用户）时不新建用户，但在非容器的 Linux 主机上
  经 sudo 对**当前用户**执行 SSH 加固（禁止 root 登录与密码登录，移走 root 的公钥）。手动 `--harden-ssh` 以普通用户运行时也默认加固当前用户。
- **原因**：用户要求（2026-11-02）。这类主机虽然 root 通常没有公钥，但 `PermitRootLogin` 仍为 yes，加固后行为与 root 场景一致。
- **防锁死**：条件与 root 场景相同（D-004）：当前用户必须已有 `authorized_keys`；交互模式需要确认；无人值守需要 `BOOTSTRAP_HARDEN_SSH=1`。
- **测试**：`TEST_SUDO_USER=1 tests/run-host.sh`（预先创建免密 sudo 的用户，全程以该用户运行）。

## D-026 nvim 预装：网络可用时默认执行 ✅

**日期**：2026-11-02

- **决策**：补写 dotfiles 中 nvim 引用的 `scripts/bootstrap.sh` / `bootstrap.lua`（dotconfig 评审第 6 项）。按用户规则（2026-11-02）：
  - 默认在部署最后检测预装所需的网络（有 mihomo 时即在安装并切换代理之后；没有 mihomo 时直接检测），通过则预装；
  - 网络检测不通过时不执行预装脚本，输出 WARNING，部署照常成功；预装中途失败同样只给出 WARNING；
  - `--no-nvim`（`BOOTSTRAP_NVIM=0`）不预装；`--nvim`（`BOOTSTRAP_NVIM=1`）不检测、强制预装，失败则部署失败。
- **网络检测**：git 的 HTTP 接口（插件克隆）、GitHub Releases 下载（语法解析器、Mason 工具、blink.cmp 库）、npm 镜像中一个包的元数据（HEAD）；
  都经当前环境的代理，不经 `GH_PROXY`（lazy.nvim / Mason 不使用它）。
- **原因**：首次打开 nvim 时，插件、语法解析器、Mason 工具都直接从 GitHub 下载，国内无代理时会失败；预装后离线可用，也适合镜像构建。
- **备选方案**：删除相关引用，只保留首次启动自动安装（用户选择补写）；默认不执行、只在 `--nvim` 时执行（第一版，用户改为默认执行）。

## D-027 mihomo 按场景分流：server / desktop / steamos ✅

**日期**：2026-11-03

- **决策**：`files/mihomo/config.yaml.tera` 一个模板按 `vars.mihomo_profile` 分支（Linux 主机 server、macOS / Windows desktop、SteamOS steamos），
  规则集统一改用 MetaCubeX/meta-rules-dat 的 geosite / geoip（mrs 格式，经 jsDelivr），本仓库维护的名单以 inline 规则集写在模板中。
  按用户需求（2026-11-03）：
  - **server**：加速线路（各云内网 / 公网镜像、GitHub 加速、Docker 加速、goproxy.cn、npmmirror）与国内 IP 必须直连，放在最前；
    开发网站原站（GitHub、HuggingFace、AI 平台、npm、Go、Docker、PyPI、crates 等）必须走代理（「开发」组不含 DIRECT）；不屏蔽广告；使用系统 DNS（云内网 DNS）。
  - **desktop**：国区 App Store / 微软商店直连（apple、microsoft 规则集）；国内服务直连；视频、直播、聊天、社交、搜索走「海外服务」组；
    开发网站与 AI 平台必须走代理；广告默认 REJECT（AD 组可切 DIRECT）；海外域名经代理向海外 DoH 查询。
    `microsoft` 规则集包含 GitHub，因此「开发」规则放在国区商店之前。
  - **steamos**：Steam 商店 / 社区走 `fallback` 组 [节点, DIRECT]（健康检查 store.steampowered.com，5 秒超时即回退直连）；
    游戏下载（steam@cn 国内 CDN + 海外 steamcontent / steampipe）与 Steam 中继（steamserver.net）直连，放在商店规则之前；
    TUN 模式（Steam 客户端不读系统代理），局域网与国内 IP 段通过 `route-exclude-address(-set)` 不进入 TUN，
    局域网串流与国内远程串流 / 联机不经过 mihomo；其他 UDP 直连；未知流量默认直连。
    代理与直连的健康检查都失败时，fallback 选第一个成员（代理，P-036）。
- **Windows**：（已被 D-029 取代）最初为导出配置导入客户端；现由 bootstrap.ps1 部署 WinSW 系统服务，配置为预渲染的 desktop 场景。
- **原因**：三类机器的用途不同；旧模板（移植自 rules.ini）各环境共用一套规则，无法满足「加速站直连 / 原站代理」「Steam 商店回退直连 / 下载直连」等要求。
  blackmatrix7 的 Steam 列表把商店与下载 CDN 混在一起，meta-rules-dat 拆得更细（steam@cn、category-ai-!cn、apple-cn、microsoft@cn）。
- **验证**：`tests/mihomo-rules.sh` 用假节点渲染三个场景、启动临时实例，按清单访问并从日志核对实际使用的策略（dev 主机上全部通过）。
- **备选方案**：三份独立模板（重复太多）；继续使用 ACL4SSR / blackmatrix7 文本规则（体积大、分类粗）。

## D-028 代理接入方式：Linux 主机用环境变量，本地个人设备默认 TUN 🟡（macOS / Windows / SteamOS 未在真机验证）

> 真机验证清单：verify-macos.md、verify-steamos.md、verify-windows.md

**日期**：2026-11-03

- **决策**（用户确认）：
  - **Linux 远程主机（server）**：不开 TUN，经环境变量使用代理——bootstrap 在 mihomo 可用后把 `http_proxy` 等写入 `env.sh`，
    dockerd 经 systemd drop-in 使用代理，Docker 容器由编排注入 `http_proxy=http://host.docker.internal:7890`（mihomo 放行 Docker 网段）。
  - **本地个人设备默认 TUN**：
    - SteamOS：已是 TUN（D-027）。
    - Windows：desktop 配置中 `tun.enable: true`；客户端（如 Clash Verge Rev）需开启服务模式。
    - macOS：mihomo 改为 **root 的 LaunchDaemon**（`/Library/LaunchDaemons/bootstrap.mihomo.plist`），取代 D-021 的用户 LaunchAgent；
      二进制为官方独立文件（锁定版本 + sha256，与 GitHub Release digest 核对）装到 root 所有的 `/opt/mihomo/bin`，
      配置在 `/opt/mihomo/config`（root 0700 / 0600）；mise 只管理用户 LaunchAgent，因此由 post-dotfiles hook
      （`scripts/macos-mihomo-daemon.sh`）加载，配置 / plist / 二进制变化时 `kickstart -k` 重启。
  - desktop 的 TUN 排除局域网段；不排除国内 IP 段（部分国内广告域名解析到国内 IP，绕过 TUN 就无法拦截）。
- **原因**：远程主机上 TUN 会接管整机路由，影响 SSH、内网与容器网络，环境变量方式影响面可控；
  本地设备上很多程序（Steam、游戏、部分桌面应用）不读系统代理，TUN 才能完整接管。
- **不用 Homebrew 的 mihomo**：Homebrew 目录当前用户可写，以 root 运行用户可改写的程序等于把 root 权限交给任何能以该用户身份运行代码的程序。
- **备选方案**：macOS 继续用户 LaunchAgent + 系统代理（无法 TUN）；Homebrew mihomo + LaunchDaemon（上述提权风险）。

## D-029 Windows：bootstrap 部署 mihomo 系统服务（WinSW） 🟡（未在真机验证）

> 真机验证清单：[verify-windows.md](verify-windows.md)

**日期**：2026-11-03

- **决策**（用户确认）：`bootstrap.ps1` 以管理员身份运行时部署 mihomo 系统服务，取代「导出配置、导入 GUI 客户端」的做法（D-027 中的 Windows 部分）：
  - 程序：mihomo 官方 `windows-amd64-compatible` 包（锁定 v1.19.33，sha256 与 GitHub digest 一致）与 **WinSW v2.12.0**（`WinSW-x64.exe`，
    发布时 GitHub 尚无 digest，经两个加速代理下载核对，大小与 API 记录一致），装到 `%ProgramFiles%\mihomo`；
  - 配置：`%ProgramData%\mihomo\config`，ACL 只允许 SYSTEM 与 Administrators（包含节点）；
    内容为预渲染的 `files/mihomo/windows-desktop.yaml`（desktop 场景，TUN），节点占位行由 fnox 解密的节点替换（私钥只在本进程环境变量中，用完即删）；
  - 服务：WinSW 以 LocalSystem 运行，**普通自动启动**（不用延迟启动），依赖 Tcpip / Dnscache，崩溃 5 秒 / 15 秒后重启；
    配置、服务定义或程序有变化时重启；`-NoMihomo` / `BOOTSTRAP_NO_MIHOMO=1` 跳过；非管理员时给出警告并跳过。
  - 暂不开放网页面板（external-controller）。
- **原因**：
  - 「登录后要等一段时间代理才生效」：「自动（延迟启动）」的服务会在开机后约 2 分钟才启动；GUI 客户端的服务模式也要等客户端随登录自启后才拉起内核。
    普通自动启动在登录前就运行。
  - 配置由 bootstrap 统一管理，与 Linux（systemd）、macOS（LaunchDaemon）一致；不依赖 GUI 客户端覆盖配置。
- **Windows 上不渲染模板**：mise 的 `[bootstrap.files]` 在 Windows 上不可用；预渲染文件由 `scripts/gen-windows-mihomo.sh` 生成，
  `--check` 检查与模板一致（lefthook 与 `tests/run-windows-config.sh`）。
- **WinSW 的维护状态**：最后一个稳定版 v2.12.0（2023-01），v3 一直是 alpha；v2.12.0 稳定、使用广泛，锁定该版本。
- **备选方案**：GUI 客户端服务模式（有启动延迟、配置不受管）；NSSM（多年未发布新版）；Windows 上用 tera CLI 渲染模板（多一个工具，且需改造 `secret()`）。

## D-030 保持 HOME 整洁：清理预置文件、其余放进 XDG 目录 ✅

**日期**：2026-11-03

- **决策**（用户确认）：部署时整理当前用户的 HOME（`lib/tidy.sh`，user 阶段执行，`--dotfiles` 也执行；`BOOTSTRAP_NO_TIDY=1` 跳过）：
  - 腾讯云镜像预置的 `~/.pip/pip.conf`、`~/.pydistutils.cfg`、`~/.npmrc`：内容与已知默认值完全一致时删除；
    镜像源改由 `env.sh` 提供（新增 `PIP_INDEX_URL` / `UV_DEFAULT_INDEX`，内网 http 镜像同时设置 `PIP_TRUSTED_HOST` / `UV_INSECURE_HOST`）；
  - `.bashrc`、`.bash_logout`、`.profile`：与 `/etc/skel` 完全相同时删除（用户选择一并删除；登录 shell 为 zsh）；
  - `.bash_history`、`.lesshst`、`.python_history`、`.docker`、`.terminfo`：移到 XDG 目录；
    `~/.zshenv` 设置 `LESSHISTFILE`、`PYTHON_HISTORY`、`DOCKER_CONFIG`、`TERMINFO_DIRS`，zsh 的 `bash` 别名设置 `HISTFILE`；
  - `.sudo_as_admin_successful`：删除，并在 root 阶段写入 `/etc/sudoers.d/00-bootstrap-no-admin-flag`（`Defaults !admin_flag`，visudo 校验通过才写入）。
- **不误删**：只删除内容可确认的文件；内容不同的保留并提示；移动时目标已存在则保留原文件并提示。
- **为什么 bash 的 HISTFILE 用别名而不是在 .zshenv 中导出**：zsh 也读取 `HISTFILE`；导出后 zsh 启动时会去加载 bash 的历史文件。
  zsh 本身不设置 `HISTFILE`（历史由 atuin 管理），因此只对启动的 bash 进程设置。
- **来源核实**（dev 主机，腾讯云 Ubuntu 24.04）：`.pip`、`.npmrc`、`.pydistutils.cfg` 与 `.ssh` 同为实例创建时写入（早于部署）；
  bash 三个文件与 `/etc/skel` 相同；`.terminfo` 来自 Ghostty 终端的 SSH 集成（登录时的「Setting up xterm-ghostty terminfo」）；
  `.sudo_as_admin_successful` 来自 Ubuntu 的 sudo；`bs-run*`、`ct-*` 是测试时手动留下的文件，不是 bootstrap 生成的。
- **备选方案**：只清理不移动（会丢失历史）；用 `/etc/zsh/zshenv` 设置 `ZDOTDIR` 以去掉 `~/.zshenv`（需要 root，且 macOS / SteamOS 不适用，维持 D-003）。
