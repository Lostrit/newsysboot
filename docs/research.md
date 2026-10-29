# 调研记录

每条记录写清日期与来源；超过 3 个月的结论在使用前要重新核实。

---

## R-001 mise bootstrap 的能力（2026-10-29）

来源：`jdx/mise` 仓库 main 分支 `docs/bootstrap.md`、`docs/bootstrap/*.md`、`settings.toml`；
最新版本 v2026.10.22。文档里没有标注 experimental。

- 入口：`mise bootstrap [--dry-run]`；`mise bootstrap --from <git url>` 运行一个「bootstrap 项目」
  （`mise.toml` 及其引用的文件）；`--adopt` 用于把仓库当作本机的全局配置。
- 执行顺序（节选）：accounts → files（pre-packages）→ apt.sources + packages → files → services →
  firewall → compose → repos → dotfiles → shell activate → macOS defaults/launchd → systemd user units →
  user（login shell）→ tools → task(`[tasks.bootstrap]`) → final hook。
  每个阶段都可以用 `--only` / `--skip` 单独执行，阶段之间有 hooks。
- `[bootstrap.packages]`：apt / dnf / pacman / brew / winget / scoop / flatpak 等；机器上没有的包管理器会被跳过。
- `[bootstrap.apt.sources.<name>]`：`uris`、`components`、`key`、`fingerprint`，写入
  `/etc/apt/sources.list.d/mise-<name>.sources`，变更后自动 `apt-get update`。
- `[bootstrap.users]` / `[bootstrap.groups]`：只支持 Linux，需要 root（自动 sudo）。
- `[bootstrap.files]` / `[bootstrap.directories]`：内容、属主、权限、`template = true`、
  `notify = ["服务名"]`；只支持 Unix，Windows 上会直接失败 → 要加 `os = "unix"`。
- `[bootstrap.services.<name>]`：系统服务（systemd，仅 Linux）和用户服务（systemd user /
  LaunchAgent / 计划任务）。同一次运行中写入的 unit 文件，配合 `notify` 可以被识别。
- `[bootstrap.user] login_shell = "zsh"`：自动解析路径、写 `/etc/shells`、执行 chsh。
- `[bootstrap.secrets]`：模板通过 `{{ secret(name="...") }}` 读取，值不会出现在任何输出里；可以用 `--prompt-secrets` 交互输入。
- 模块：`mise.<name>.toml`，通过 `-E a,b` 或 `miserc.local.toml` 的 `env = [...]` 选择。
- `[dotfiles]`：track / link / copy / template / 按行或按块编辑。
- `settings.url_replacements`（环境变量 `MISE_URL_REPLACEMENTS`，JSON）：在 mise 的 HTTP 客户端里改写 URL，
  可以把 `https://github.com/` 改写为 `${GH_PROXY}https://github.com/`。

**PoC 要验证**：

1. 运行中被 link 过来的全局 `~/.config/mise/config.toml`，它的 `[tools]` 会不会在同一次运行的 tools 阶段被安装？（如果不会，就在 `[tasks.bootstrap]` 里再执行一次 `mise install`）
2. `bootstrap.users` 里的 `groups` 是替换还是追加附加组？（加入 docker 组时要避免把其他组冲掉）
3. 安装 mise 本身也要走 GitHub：stage-0 通过 `GH_PROXY` 下载 release 包，并校验 sha256。

## R-002 网络探测（2026-10-29，在当前腾讯云 Debian 13 主机上）

| 目标 | 结果 |
| --- | --- |
| `mirrors.cloud.tencent.com/docker-ce/` | 200，0.03s |
| `mirrors.tencentyun.com/`（内网） | 200，0.03s |
| `mirrors.tencentcloud.com/` | **无法连接**，见 pitfalls P-001 |
| `http://metadata.tencentyun.com/latest/meta-data/instance-id` | 200，0.008s，可用来判断是否在腾讯云内网 |
| github.com / gh-proxy.com / mise.run / get.chezmoi.io | 200，1–2s（本机有 mihomo 代理） |

**结论**：
- 判断是否在腾讯云：用 1 秒超时访问 metadata 服务，能访问就是内网，用 `mirrors.tencentyun.com`。
- GitHub 代理测速：对候选列表用同一个固定的 release 资源测下载速度（`curl -w %{speed_download}`，单次超时 8 秒，取 2 次的中位数），
  再校验下载内容的 sha256，防止代理篡改。结果缓存到 `$XDG_STATE_HOME/bootstrap/gh_proxy`，设置 TTL。候选列表要定期复核（这类服务经常失效）。

## R-003 get.docker.com 脚本（2026-10-29）

- 当前 `SCRIPT_COMMIT_SHA="ada7a567e59b3935bd601bb21e422da50e80e376"`。
- 支持环境变量 `DOWNLOAD_URL`（默认是 `https://download.docker.com`），apt 源和 gpg 地址都基于它拼接：
  `$DOWNLOAD_URL/linux/<distro>/gpg`。`--mirror` 只内置了 Aliyun / AzureChinaCloud。
- 所以 `DOWNLOAD_URL=https://mirrors.cloud.tencent.com/docker-ce`（腾讯云内网用
  `https://mirrors.tencentyun.com/docker-ce`）就能得到和官方一样的安装结果。已确认内网镜像的 gpg 地址返回 200。
- 脚本不支持 SteamOS / macOS / Windows（macOS 会提示去用 Docker Desktop）。

## 待调研

- SteamOS 上的 Docker：静态二进制 + `/etc/systemd/system` unit，还是使用系统自带的 podman/distrobox？
- SteamOS 上 `/etc` overlay 在系统升级后能否保留；`/usr/local` 是否只读。
- macOS 上的 Docker 方案（OrbStack / colima / Docker Desktop）；mihomo 用 TUN 模式需要 root 的 LaunchDaemon（mise 只管理 LaunchAgent）。
- Windows：原生 PowerShell + winget/scoop，还是以 WSL2 为主？mihomo 用什么方式作为服务运行？
- 国内可用的 Docker Hub 镜像加速：腾讯云内网 `mirror.ccs.tencentyun.com`；公网现状需要再查。
- mihomo 的 geodata 镜像地址（`geox-url`）。
