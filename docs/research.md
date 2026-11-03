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
  只要有一项需要 root，整个 files 阶段都以 sudo 执行，没写 `owner` 的项归 root；`owner` / `group` 不支持模板
  （2026-11-02 用 mise 2026.10.21 实测，P-030）。
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
2. ~~`bootstrap.users` 的 `groups` 是替换还是追加~~ → 已绕过：改用 `usermod -aG`（D-005）
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

## R-004 各云 apt / docker-ce 镜像探测（2026-10-29，在腾讯云内网主机上，`--noproxy`）

| 域名 | 类型 | Debian Release | docker-ce gpg | 在腾讯云上的表现 |
| --- | --- | --- | --- | --- |
| mirrors.tencentyun.com | 腾讯云内网 | 200 | 200 | 可用 |
| mirrors.cloud.aliyuncs.com | 阿里云 VPC 内网 | 超时 | 超时 | **能解析但连不上，要靠短连接超时排除** |
| mirrors.myhuaweicloud.com / repo.myhuaweicloud.com | 华为云内网（域名待核实） | DNS 失败 | DNS 失败 | 很快就排除了 |
| mirrors.ivolces.com | 火山引擎内网（域名待核实） | DNS 失败 | DNS 失败 | 很快就排除了 |
| mirrors.cloud.tencent.com | 腾讯云公网 | 200 0.21s | 200 | |
| mirrors.aliyun.com | 阿里云公网 | 200 0.09s | 200 | |
| mirrors.huaweicloud.com / repo.huaweicloud.com | 华为云公网 | 200 | 200 | |
| mirrors.volces.com | 火山引擎公网 | 200 | **404** | 没有 docker-ce |
| mirrors.ustc.edu.cn / mirrors.tuna.tsinghua.edu.cn | 高校镜像 | 200 | 200 | 较慢 |

元数据服务：腾讯云 `metadata.tencentyun.com` 可以访问；阿里云 `100.100.100.200`、通用的 `169.254.169.254` 超时。
内网源的判断直接探测镜像本身，不依赖元数据服务（元数据只用作日志信息）。

**待核实**：华为云、火山引擎内网镜像的准确域名（需要在对应云上测试，或查官方文档）。

## R-005 mise hooks 与 secrets（2026-10-29）

- 全局 `[hooks] postinstall` 会收到 `MISE_INSTALLED_TOOLS`（JSON 数组），可以据此只在特定工具被安装时执行操作。
- 从 hook 中调用的 mise 命令会带上 `MISE_NO_HOOKS=1`，不会递归触发 hooks。
- `[bootstrap.secrets]` 只从环境变量读取值；`--prompt-secrets` 可以交互输入；官方推荐用 fnox 注入，
  其他任何能设置环境变量的方式（如 `sops exec-env`）都可以。`secret()` 原样插入，不做转义。

## R-006 fnox 与 sops 的对比（2026-10-29）

来源：`jdx/fnox` 仓库文档（v1.44.0，2025-10 创建，MIT 协议，约 2.3k star）；sops v3.13.3。

fnox 是 mise 作者开发的机密管理工具：在 `fnox.toml` 中声明机密，每个机密的值可以来自不同的 provider
（age 加密存放在配置文件中，或 1Password、Bitwarden、macOS 钥匙串、各家云的 KMS/Secret Manager 等）；
用 `fnox exec -- <命令>` 把解密后的值作为环境变量交给命令。mise bootstrap 的 secrets 文档直接以 `fnox exec -- mise bootstrap` 作为示例。

| | fnox（age provider） | sops + age |
| --- | --- | --- |
| 成熟度 | 新（1 年），迭代快 | 成熟（CNCF 项目，2015 年起） |
| 存储方式 | 每个机密一个条目，值是 base64 密文；键名可见 | 加密整份 YAML/JSON/ENV 文件，结构和键名可见，只加密值 |
| 交给 mise bootstrap | `fnox exec --`，一个机密对应一个环境变量，直接对上 `[bootstrap.secrets]` | `sops exec-env` 只适合扁平的键；嵌套结构要先解密成文件 |
| 输入私钥 | `FNOX_AGE_KEY`（直接放私钥内容） | `SOPS_AGE_KEY`（同样支持私钥内容） |
| 编辑 | `fnox set NAME`（隐藏输入）/ `--from-file`；大段 YAML 不太方便 | `sops edit` 在编辑器中编辑明文，体验最好 |
| 分环境 | profiles（`--profile server`），可继承 | 每个环境一个文件 |
| 以后扩展 | 可以改为从钥匙串 / 密码管理器读取私钥，不用每次输入 | 只支持 age / PGP / KMS |
| 安装 | `mise use fnox` | `aqua:getsops/sops` |

**结论**：选 fnox。和 mise bootstrap 的对接最直接（一个机密对应一个环境变量），也是 mise 官方文档推荐的方式。
主要风险是 fnox 和 mise bootstrap 都很新、出自同一作者，风险会叠加；但两者之间的接口只是环境变量，
换成 sops 的成本很低。PoC 中如果 fnox 有问题，就改用 sops。

## R-007 mihomo 策略组的排序（2026-10-29）

来源：MetaCubeX/Meta-Docs `docs/config/proxy-groups/index.md`。`include-all-proxies` 引入的节点按名称排序，文档没有说明它们与显式写在
`proxies` 中的项（如 `DIRECT`）谁先谁后。为了保证默认选中项确定，模板里用两层策略组，不把两者混在同一组中。

## R-008 mise.run 安装脚本（2026-10-29）

来源：`https://mise.run` 当前内容（内置版本 v2026.10.22，482 行，已放入 `vendor/mise-install.sh`）。

- 支持固定版本：`MISE_VERSION=2026.10.22`。不指定时，从 `https://mise.jdx.dev/releases.tsv` 中选择发布满
  `MISE_MINIMUM_RELEASE_AGE`（默认 24h）的最新版本；已安装的版本更新时保留现有的（除非指定了 `MISE_VERSION`）。
- 下载顺序：先 CDN `https://mise.jdx.dev/v<版本>/<文件>`，失败时退回 GitHub Releases；`MISE_INSTALL_FROM_GITHUB=1` 强制使用 GitHub。
- **校验值**：脚本内置版本使用内嵌的 sha256；**其他版本从 GitHub Releases 获取校验值**（CDN 上虽然也有 `SHASUMS256.txt`，但脚本故意不用它）。
  因此，要在国内固定一个「非内置」版本，校验这一步就要访问 GitHub → 改为锁定脚本本身（D-012）。
- 其他变量：`MISE_INSTALL_PATH`（默认 `~/.local/bin/mise`）、`MISE_INSTALL_SKIP_IF_EXISTS=1`、`MISE_INSTALL_MUSL`、`MISE_QUIET`。

## R-012 mihomo 分流规则集与相关特性（2026-11-03，mihomo v1.19.33）

- MetaCubeX/meta-rules-dat（`meta` 分支 `geo/geosite/*.mrs`、`geo/geoip/*.mrs`）经 jsDelivr 可直接访问（dev 主机直连 200）。
  已确认存在：private、cn、geolocation-!cn、gfw、category-ads-all、github、gitlab、huggingface、docker、npmjs、golang、python、rust、jetbrains、
  category-ai-!cn、openai、anthropic、google-gemini、apple、apple-cn、microsoft、microsoft@cn、google、youtube、netflix、disney、twitch、spotify、
  tiktok、telegram、discord、twitter、facebook、instagram、reddit、category-social-media-!cn、steam、steam@cn、geoip cn / private / telegram。
  不存在：category-news-!cn（404）；bitbucket 返回 403。
- 内容要点：`microsoft` 包含 31 条 GitHub 相关条目与 bing；`steam` 同时包含商店与下载 CDN（steamcontent、steampipe）；
  `steam@cn` 只有国内下载 CDN 与 steamserver.net；`docker` 覆盖 docker.io / docker.com，不含 quay.io、gcr.io、mcr.microsoft.com。
- mihomo v1.19.33 支持 `type: inline` 规则集、`tun.route-exclude-address-set`（ipcidr 规则集）、`dns.respect-rules`、
  `fake-ip-filter` 中的 `rule-set:`、`fallback` 组（二进制中字段均存在，并经 `mihomo -t` 与实际分流测试验证）。
- 腾讯云 npm 镜像根路径返回 404、不支持 Range（P-033）。

## R-013 GitHub 加速代理候选（2026-11-03，开发机：腾讯云，国内网络，不经代理）

- 来源 https://github.xxlab.tech/：页面「加速源」下拉框中共 75 个前缀（含该站自身）；页面没有标注各地址支持哪些获取方式，
  说明文字称该站自身「支持 release、archive 以及文件……文件会跳转至 jsDelivr……clone 加速：在原始链接前加上本站地址」。
- 3 轮完整测试（release / raw / archive / clone）：39 个全部通过；未通过的原因以连接失败与 release 失败为主，
  也有只在部分轮次失败的（如 `gh.dpik.top` 第 2 轮 raw、`github-proxy.lixxing.top` 第 3 轮 clone），说明多轮测试有意义。
- `gh-proxy.com` 第 1 轮 release 即失败（当天该机器访问频繁，疑似限流，P-029），未进入列表；`ghfast.top` 通过但速度一般。
- 速度最快的前几个：gh.qninq.cn（最慢一轮 866 KB/s）、github.cnxiaobai.com、git.yylx.win、gh.padao.fun。
- 结论：候选质量变化快，需要定期运行 `scripts/update-gh-proxies.sh`；部署时仍要在本机重新测试。
- mise 2026.10.22 自身的回退（dev 主机实测）：`MISE_URL_REPLACEMENTS` 指向不可用的代理时，release 下载的 HEAD 请求重试 3 次失败后，
  mise 自动改用 GitHub API 的资源地址（`api.github.com/repos/<o>/<r>/releases/assets/<id>`）下载，即直连（有 mihomo 时经 mihomo），安装成功。
  因此 bootstrap 的「关闭 GH_PROXY 重试一次」（`bs_mise_retry`）只在 mise 内部回退也失败时才会触发。
- 资源占用（P-042）：nvim 预装的并发上限按 min(CPU, 内存 GB / 1.5) 计算；dev（2 核 7.5G）为 2，开发机（2 核 2G）为 1。

## R-014 Ubuntu 26.04 LTS 真机部署（2026-11-03，dev 主机，腾讯云）

- Ubuntu 26.04 默认的 sudo 是 **sudo-rs 0.2.13**，coreutils 是 **uutils 0.8.0**（Rust 实现）。部署全部正常；
  sudo-rs 的 visudo 不接受 `Defaults !admin_flag`，`bs_sudo_no_admin_flag` 按设计跳过（sudo-rs 也不创建 `.sudo_as_admin_successful`）。
- 腾讯云内网 docker-ce 源已有 `resolute`（26.04 代号），get-docker.sh 安装 Docker 29.9.2 成功。
- mihomo 生效后 GitHub 下载仍经 GH_PROXY：mihomo 日志中整个部署期间只有 2 次 github.com（代理可用性检查与手动测试）
  与 1 次 raw.githubusercontent.com（来源未定位：mise 的 aqua / claude / bun 安装、herdr 集成都已确认经 GH_PROXY 或不访问 raw）。

## R-009 Docker Hub 镜像加速（2026-10-29，在腾讯云内网主机上，`--noproxy`，请求 `/v2/`）

| 地址 | 结果 | 说明 |
| --- | --- | --- |
| https://mirror.ccs.tencentyun.com | 200，0.02s | 腾讯云内网，**已在本机配置**；拉取 debian:13 + ubuntu:24.04 共 97s |
| https://docker.1ms.run | 401，0.18s | 第三方公网镜像（401 是正常的 registry 认证质询） |
| https://docker.m.daocloud.io | 401，0.12s | DaoCloud 公网镜像 |
| https://dockerproxy.net | 200，1.46s | 第三方 |
| https://hub.rat.dev | 302 | 第三方 |
| https://docker.xuanyuan.me | 401，2.6s | 第三方 |

- 判断可用：`/v2/` 返回 200 或 401 都说明 registry 在线；测速时应该实际拉取一个小镜像的 manifest，而不是只看 `/v2/`。
- 阿里云（`https://<id>.mirror.aliyuncs.com`）、华为云的加速器地址都和账号绑定，只能手动配置。
- 第三方公网镜像经常失效（2024 年起大量公共镜像关闭），只作为辅助手段；主要依靠 mihomo 代理回源。

## R-010 mise bootstrap PoC 结论（2026-10-29，mise 2026.10.22，容器内屏蔽 GitHub 直连）

- **R-001 的问题 1 已验证**：运行过程中通过 `[dotfiles]` 链接过来的 `~/.config/mise/config.toml`，它的 `[tools]` 会在**同一次运行**的 tools 阶段被安装，不需要再补一次 `mise install`。
- **`MISE_URL_REPLACEMENTS` 可行**：只改写 `https://github.com/` 和 `https://raw.githubusercontent.com/` 两个前缀，20 个工具（aqua / node / bun / claude）26 秒全部装好，签名校验通过，没有警告。
  node 走 `MISE_NODE_MIRROR_URL=https://mirrors.cloud.tencent.com/nodejs-release/`。
- **`[vars]` 不支持数组**（报错 `cannot be an array`）：列表用逗号分隔的字符串，模板中用 `split(pat=",")`；空字符串 split 后是 `[""]`，使用前要先判断。
  `{{ env.X | default(value='') }}`、`json_encode()` 都可以用。
- **幂等**：第二次运行时，packages / files / dotfiles / login shell / tools 全部显示已收敛或已安装。
- `mise bootstrap` 不允许 `--only` 和 `--skip` 同时使用。
- 测试矩阵：debian:12、debian:13、ubuntu:22.04、ubuntu:24.04 全部通过（各执行两次）。
- 本机直连 GitHub 的 release 下载会超时（`curl -L` 跟随跳转到 githubusercontent 后卡住），与国内的真实情况一致；测速时 GitHub 代理中 `gh.qninq.cn`、`github.cnxiaobai.com` 较快，`ghproxy.net` 不可用。

## R-011 主机流程测试结论（2026-10-29，带 systemd 的 debian:13 特权容器）

- `[bootstrap.services.docker]` 声明的 unit 在运行开始时还不存在（Docker 由 post-packages hook 安装），**不会导致校验失败**：
  services 阶段在 hook 之后执行，unit 已经就位。
- `remove_empty = true` + `vars.mihomo_mixed_port | default(value="")`：不启用 mihomo 模块时 dockerd 代理 drop-in 不会被写入。
- 第二次运行时 files / services / dotfiles / user / tools 全部显示已收敛；hooks 每次都会执行（脚本自身保证幂等）。
- 容器内运行 dockerd：`/var/lib/docker` 必须挂载卷（overlay 上不能再叠 overlay）。
- mihomo v1.19.33 的 deb 包：`/usr/bin/mihomo`、`/usr/lib/systemd/system/mihomo{,@}.service`、`/etc/mihomo/config.yaml`（conffile）。
  amd64 sha256 `3f6f31f3…`（已下载核对，与 GitHub API 给出的值一致），arm64 `c01af414…`（取自 GitHub API，未下载核对）。

## 待调研

- SteamOS：`/etc` overlay 在系统升级后能否保留；`/usr/local` 是否只读；系统是否自带 zsh / git / curl / sudo（deck 用户需要先用 passwd 设置密码才能 sudo）。
- mihomo 独立二进制的 sha256（v1.19.33）：linux-amd64 `.gz` `132f6f3e…`（已下载核对），linux-arm64 `ba408b31…`、darwin-arm64 `060b64b0…`、darwin-amd64 `551ae54e…`、windows-amd64 `.zip` `6ab21808…`（取自 GitHub API，未下载核对）。
- macOS：mihomo 用 TUN 模式需要 root 的 LaunchDaemon（mise 只管理 LaunchAgent）；Homebrew 的国内镜像。
- Windows：原生 PowerShell + winget/scoop；mihomo 用什么方式作为服务运行。
- 国内可用的 Docker Hub 镜像加速：腾讯云内网 `mirror.ccs.tencentyun.com`；公网现状需要再查。
- CNB 的 raw 文件地址格式；sops `exec-env` 对嵌套键的处理；mise `[bootstrap.files]` 的 `source` + `template = true` 能否和 Tera 的 `include` 一起用。
- mihomo 的 geodata 镜像地址（`geox-url`）。
