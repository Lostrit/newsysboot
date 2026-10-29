# 开发计划

## 1. 目标

在全新的机器或容器上，用一条命令（国内网络、无法直连 GitHub 时也能用）完成：

1. 更新包索引，安装 `git`、`zsh`、`curl` 等基础包
2. 如果当前是 root：创建带 sudo 权限的普通用户，之后的步骤都以这个用户运行
3. 写入 `~/.zshenv`（XDG 变量 + ZDOTDIR），创建 XDG 目录，把默认 shell 设为 zsh
4. 安装 mihomo 并配置为系统服务（容器环境除外；各环境配置不同）
5. 安装 Docker（与 get.docker.com 一致，使用镜像源），把普通用户加入 `docker` 组（容器环境除外）
6. 安装 mise，按 dotconfig 的 `mise/config.toml` 安装工具
7. 部署 dotconfig 到 `~/.config`

可重复执行（幂等）；支持预览（dry-run）；支持无交互运行（Dockerfile / 无人值守）。

## 2. 总体架构

```
            ┌──────────────── stage-0：bootstrap.sh / bootstrap.ps1（无依赖） ────────────────┐
curl | sh → │ 1 检测环境（OS / 发行版 / 容器 / 腾讯云内网 / 现有代理）                         │
            │ 2 选择镜像源；对 GitHub 代理测速 → GH_PROXY                                        │
            │ 3 安装最少的依赖：curl ca-certificates git（apt update）                            │
            │ 4 如果是 root：创建普通用户 → 复制本仓库 → sudo -iu <user> 重新执行                   │
            │ 5 经 GH_PROXY 下载锁定版本的 mise 并校验 sha256 → ~/.local/bin/mise                  │
            │ 6 mise -E <模块列表> bootstrap --from <本仓库>（分两次执行，见下文）                 │
            └───────────────────────────────────────────────────────────────────────────────────┘
                                   │
            ┌──────── stage-1：mise bootstrap（本仓库的 mise.toml + mise.<模块>.toml） ────────┐
            │ packages   apt:zsh, git, …（SteamOS / macOS / Windows 有各自的模块）                 │
            │ files      ~/.zshenv、/etc/mihomo/*、mihomo.service、docker daemon.json、代理 drop-in │
            │ services   mihomo、docker                                                            │
            │ hooks      安装 mihomo 二进制、执行锁定版本的 get-docker.sh、usermod -aG docker        │
            │ repos      dotconfig → ~/.local/share/dotconfig                                      │
            │ dotfiles   ~/.config/<tool> → dotconfig 子目录（link）                                │
            │ user       login_shell = "zsh"                                                       │
            │ tools      dotconfig 的 mise/config.toml                                             │
            │ task       bat cache --build、zsh 插件预编译、检查                                    │
            └───────────────────────────────────────────────────────────────────────────────────┘
```

**分两次执行**：mise 进程启动后不会自动使用之后才起来的代理，所以

1. 第一次：`--only accounts,files,packages,services`，把 mihomo 和 Docker 装好（这一步只依赖国内镜像和 GH_PROXY）；
2. 检查 mihomo 端口可用后，导出 `http(s)_proxy`，清空 GH_PROXY，再执行完整的 `mise bootstrap`。

如果 mihomo 不可用（没有订阅 / 容器环境），继续使用 GH_PROXY。

### 环境检测与模块

| 检测依据 | 环境 | 启用的模块（`mise.<name>.toml`） |
| --- | --- | --- |
| `uname -s` = Darwin | macOS | `macos` |
| `/etc/os-release` 中 `ID=steamos` | SteamOS | `steamos` |
| `/.dockerenv` 存在，或 `systemd-detect-virt -c` 不是 none | 容器 | `debian` + `container` |
| `ID=debian/ubuntu` | Linux 服务器 / 桌面 | `debian` + `mihomo` + `docker` |
| 能访问 metadata.tencentyun.com（超时 1 秒） | 腾讯云内网（叠加） | `tencent`（只是切换镜像地址等变量） |
| PowerShell | Windows | `windows`（单独实现） |

检测结果写入 `~/.config/mise/miserc.local.toml`（`env = [...]`），之后手动执行 `mise bootstrap` 时会自动使用这些模块；也可以用 `BOOTSTRAP_ENV` 覆盖。

### 计划的仓库结构

```
bootstrap.sh              # stage-0（POSIX sh）
bootstrap.ps1             # stage-0（Windows）
lib/                      # stage-0 用到的函数：detect.sh、netprobe.sh、user.sh
mise.toml                 # 所有环境共用的部分
mise.debian.toml  mise.steamos.toml  mise.macos.toml  mise.container.toml
mise.mihomo.toml  mise.docker.toml   mise.tencent.toml
files/                    # zshenv、mihomo 配置模板、systemd unit、daemon.json …
vendor/get-docker.sh      # 锁定 SCRIPT_COMMIT_SHA，附带 sha256
scripts/                  # hooks / task 调用的小脚本（install-mihomo.sh …）
tests/                    # Docker 容器中的回归测试
docs/
```

## 3. 分阶段计划

### 阶段 0：项目初始化 ✅
- git、CLAUDE.md、docs、调研与决策

### 阶段 1：PoC（在 Debian 13 容器中验证 mise bootstrap 的关键点）
- [ ] 一个最小的 `mise.toml`：apt 包、`~/.zshenv` 文件、login_shell、repos + dotfiles link、tools
- [ ] 验证 research R-001 中的 3 个问题
- [ ] 验证 `MISE_URL_REPLACEMENTS` + GH_PROXY 下的 aqua 安装和签名校验
- 结果写入 research / decisions；如果不通过，按 D-001 的备选方案改用 chezmoi

### 阶段 2：stage-0 + Debian/Ubuntu 容器基线
- [ ] `detect.sh`、`netprobe.sh`（GitHub 代理测速 + sha256 校验 + 缓存）
- [ ] 安装 mise（锁版本、校验）
- [ ] root → 创建普通用户（交互输入 / `BOOTSTRAP_USER`，从 `/dev/tty` 读取）
- [ ] container 模块：packages、zshenv、shell、mise 工具、dotfiles
- [ ] `tests/`：在 `debian:13`、`ubuntu:24.04` 中无交互执行两遍，第二遍应该没有任何变更

### 阶段 3：Linux 服务器（腾讯云 Debian/Ubuntu，需要 systemd）
- [ ] mihomo：二进制（GH_PROXY + 校验）、`/etc/mihomo/config.yaml` 模板（secrets 提供订阅地址）、unit、geodata 镜像
- [ ] mihomo 的服务器配置：只监听本机和 docker 网桥，供容器使用
- [ ] Docker：vendor 脚本 + DOWNLOAD_URL、daemon.json（镜像加速）、dockerd 代理 drop-in、加入 docker 组
- [ ] 两次执行的流程、代理切换
- [ ] 测试：systemd 容器或一次性云服务器

### 阶段 4：dotconfig 适配多环境（与 dotconfig 仓库同步修改）
- [ ] 按 dotconfig-review 的 🔴 / 🟠 条目逐项修改
- [ ] 需要按环境区分的文件改成模板

### 阶段 5：SteamOS
- [ ] 不关闭只读：zsh/git 是否自带、chsh、`/etc` 下的 mihomo unit、二进制放在 `/var/lib` 或 `~/.local`
- [ ] Docker 方案（待调研）

### 阶段 6：macOS
- [ ] Homebrew（国内镜像）、mihomo（LaunchDaemon）、Docker 方案

### 阶段 7：Windows
- [ ] 确定范围（原生 / WSL2）、`bootstrap.ps1`、winget/scoop、mihomo 服务

## 4. 需要用户确认的问题

1. **D-001**：主流程用 mise bootstrap（建议），还是用 chezmoi？
2. **D-002**：dotconfig 保持独立仓库并用 link 部署（建议），还是合并进本仓库？
3. **托管位置**：新机器从哪里拉取本仓库？如果是 GitHub，需要是公开仓库（经代理访问，P-004）；也可以放在 CNB / Gitee。
4. **mihomo**：各环境用什么配置（订阅地址 / 本地规则 / TUN 还是系统代理）？订阅地址是运行时输入，还是加密存放？
5. **新用户**：要不要设置密码？sudo 是否免密？是否复制 root 的 `authorized_keys`？
6. **SteamOS / macOS / Windows 上的 Docker**：分别用什么方案？Windows 是原生还是 WSL2？
