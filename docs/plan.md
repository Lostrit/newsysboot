# 开发计划

## 1. 目标

在全新的机器或容器上，用一条命令（国内网络、无法直连 GitHub 时也能用）完成：

1. 选择 apt 源（D-006），更新包索引，安装 `git`、`zsh`、`curl` 等基础包
2. 如果当前是 root：创建普通用户（密码、免密 sudo、迁移 SSH 公钥、禁止 root 登录和密码登录，D-004）
3. 写入 `~/.zshenv`（XDG 变量 + ZDOTDIR），创建 XDG 目录，把默认 shell 设为 zsh
4. 安装 mihomo 并配置为系统服务（容器除外；配置加密存放并用模板区分环境，D-008）
5. 只在 Linux 主机上安装 Docker（镜像源，与 get.docker.com 一致），把普通用户加入 `docker` 组（D-005）
6. 安装 mise，按 `dotfiles/.config/mise/config.toml` 安装工具
7. 部署 `dotfiles/` 到 `~/.config`（link 方式，D-002）

另外提供「只应用 dotfiles」的入口，用于已初始化的环境（D-009）。
所有步骤可重复执行（幂等），可以预览（dry-run），可以无交互运行。

## 2. 总体架构

```
            ┌──────────────── stage-0：bootstrap.sh / bootstrap.ps1（无依赖） ────────────────┐
curl | sh → │ 1 检测环境：OS / 发行版 / 容器 / 现有代理                                          │
            │ 2 选源：apt、docker-ce（先内网后测速，D-006）；GitHub 加速代理测速 → GH_PROXY        │
            │ 3 换源，apt update，安装 curl ca-certificates git sudo                              │
            │ 4 如果是 root：创建用户、迁移 SSH、加固 → sudo -iu <user> 重新执行（D-004）           │
            │ 5 选择拉取来源 GitHub(加速) / CNB → clone 到 $XDG_DATA_HOME/bootstrap（D-007）        │
            │ 6 用 vendor/mise-install.sh 安装锁定版本的 mise（只走 CDN，D-012）                   │
            │ 7 输入 age 私钥 → FNOX_AGE_KEY → fnox exec -- mise bootstrap（分两次执行）           │
            └───────────────────────────────────────────────────────────────────────────────────┘
                                   │
            ┌──────── stage-1：mise bootstrap（本仓库的 mise.toml + mise.<模块>.toml） ────────┐
            │ packages     apt:zsh, git, …                                                        │
            │ directories  XDG 目录、zsh 缓存目录                                                  │
            │ files        ~/.zshenv、/etc/mihomo/config.yaml(模板+secret)、mihomo.service、       │
            │              docker daemon.json、dockerd 代理 drop-in                                │
            │ services     mihomo、docker                                                          │
            │ hooks        安装 mihomo 二进制、执行 vendor/get-docker.sh、usermod -aG docker        │
            │ dotfiles     ~/.config/<tool> → 仓库 dotfiles/.config/<tool>（link）                   │
            │ user         login_shell = "zsh"                                                     │
            │ tools        dotfiles/.config/mise/config.toml                                       │
            │ task         预热 zsh 缓存（D-010）、bat cache --build、自检                         │
            └───────────────────────────────────────────────────────────────────────────────────┘
```

**分两次执行**：mise 进程不会自动用上之后才启动的代理。
第一次 `--only accounts,files,packages,services`，装好 mihomo 和 Docker（只依赖国内镜像和 GH_PROXY）；
确认 mihomo 端口可用后，导出 `http(s)_proxy`、清空 GH_PROXY，再执行完整的 `mise bootstrap`。mihomo 不可用时继续使用 GH_PROXY。

### 环境检测与模块

| 检测依据 | 环境 | 启用的模块（`mise.<name>.toml`） |
| --- | --- | --- |
| `uname -s` = Darwin | macOS | `macos` + `mihomo` |
| `/etc/os-release` 中 `ID=steamos` | SteamOS | `steamos` + `mihomo` |
| `/.dockerenv` 存在，或 `systemd-detect-virt -c` 不是 none | 容器 | `debian` + `container` |
| `ID=debian/ubuntu`（非容器） | Linux 主机 | `debian` + `mihomo` + `docker` |
| PowerShell | Windows | `windows`（单独实现） |
| 任何环境 + `--dotfiles` | 只应用 dotfiles | `dotfiles`（不需要 root） |

镜像源的选择结果通过 `[vars]` 传入，不单独做云厂商模块。检测结果写入 `~/.config/mise/miserc.local.toml`（`env = [...]`），
之后手动执行 `mise bootstrap` 时会沿用这些模块；可以用 `BOOTSTRAP_ENV` 覆盖。

### 计划的仓库结构

```
bootstrap.sh  bootstrap.ps1     # stage-0 入口
bin/apply                       # 在已有仓库中只应用 dotfiles（D-009）
lib/                            # detect.sh、mirrors.sh（apt/docker/GitHub 选源）、user.sh、ssh.sh、secrets.sh
mise.toml                       # 共用部分（含 dotfiles 模块，D-009）
mise.debian.toml  mise.steamos.toml  mise.macos.toml  mise.container.toml
mise.mihomo.toml  mise.docker.toml
files/                          # zshenv、mihomo/config.yaml.tera、systemd unit、daemon.json …
fnox.toml                       # 机密信息（age 加密后的密文，D-008）
vendor/get-docker.sh            # 锁定 SCRIPT_COMMIT_SHA + sha256
dotfiles/                       # 原 dotconfig（subtree，D-002）
tests/                          # 容器中的回归测试
docs/
```

## 3. 分阶段计划

### 阶段 0：项目初始化 ✅
- git、CLAUDE.md、docs、调研与决策；合并 dotconfig（subtree）

### 阶段 1：PoC（在 Debian 13 容器中验证 mise bootstrap 的关键点）✅
- [x] 最小的 `mise.toml`：apt 包、directories、`~/.zshenv`、login_shell、dotfiles link、tools
- [x] 验证 research R-001 中尚未解决的问题（同一次运行中链接过来的全局 config 的 tools 是否会被安装）
- [x] `MISE_URL_REPLACEMENTS` + GH_PROXY 下 aqua 的安装和签名校验
- [ ] `fnox exec` + `[bootstrap.secrets]` + `template = true` 渲染 mihomo 配置（模板已用 `mihomo -t` 验证过）
- 结果写入 research / decisions；不通过的话重新讨论 D-001

### 阶段 2：stage-0 + 容器基线 ✅
- [x] `lib/detect.sh`（含容器规则）
- [x] `lib/mirrors.sh`（内网探测 → 公网测速 → 缓存；GitHub 代理测速 + sha256 校验）
- [x] apt 换源（deb822 / sources.list，先备份）
- [x] 安装 mise（`vendor/mise-install.sh` + `MISE_VERSION`）
- [x] 拉取来源选择（GitHub / CNB）
- [x] container 模块 + dotfiles 模块（`bootstrap.sh --dotfiles` 代替 `bin/apply`）
- [x] `tests/`：在 `debian:12`、`debian:13`、`ubuntu:22.04`、`ubuntu:24.04` 中无交互执行两遍，第二遍应该没有任何变更

### 阶段 3：Linux 主机（需要 systemd）✅
- [x] root → 普通用户：密码、免密 sudo、SSH 公钥迁移、确认后再加固 sshd（D-004）
- [x] mihomo：二进制、Tera 模板（✅ 已生成）、fnox 机密、unit、geodata 镜像；服务器上只监听本机和 docker 网桥
- [x] Docker：vendor 脚本 + DOWNLOAD_URL、daemon.json（Docker Hub 镜像，模板草稿 ✅）、dockerd 代理、加入 docker 组
- [x] 两次执行与代理切换
- [x] 测试：systemd 容器（tests/run-host.sh）
- [ ] 一次性云服务器（腾讯云 / 阿里云 / 华为云各测一次内网源探测）— 需要用户提供机器

### 阶段 4：dotfiles 整理与解耦
- [ ] 目录整理（D-002 中所列）
- [ ] 按 dotconfig-review 的 🔴 / 🟠 条目逐项修改
- [ ] zsh：`tools.zsh` + `zcache`，去掉 mise postinstall 中的重复代码（D-010、design-zsh-tools.md）
- [ ] 需要按环境区分的文件改成模板（npmrc、bunfig、herdr）

### 阶段 5：SteamOS（不装 Docker）
- [ ] 不关闭只读：zsh/git 是否自带、chsh、`/etc` 下的 mihomo unit、二进制放在 `/var/lib` 或 `~/.local`

### 阶段 6：macOS（不装 Docker）
- [ ] Homebrew（国内镜像）、mihomo（LaunchDaemon）

### 阶段 7：Windows（不装 Docker）
- [ ] `bootstrap.ps1`、winget/scoop、mihomo 服务

## 4. 需要用户提供 / 确认

1. 远程仓库创建后告知地址（D-011，不影响本地开发）。
2. 各环境的 mihomo 配置以后再整理；目前的模板只覆盖「服务器」场景。
