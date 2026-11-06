# 开发中遇到的坑

格式：现象 / 原因 / 解决。

---

## P-001 `mirrors.tencentcloud.com` 在腾讯云内网无法连接

- **现象**：2026-10-29 在腾讯云 Debian 13 主机上 `curl https://mirrors.tencentcloud.com/` 返回 000（连接失败）。
- **原因**：腾讯云内网镜像的域名是 `mirrors.tencentyun.com`（dotconfig 的 npmrc 用的也是它）；
  `mirrors.tencentcloud.com` 应该是国际站域名（未进一步核实）。
- **解决**：内网用 `https://mirrors.tencentyun.com/docker-ce`，公网用 `https://mirrors.cloud.tencent.com/docker-ce`。

## P-002 开发机器默认没有 git

- **现象**：当前 Debian 13 环境执行 `git` 提示 command not found。
- **解决**：已用 `apt-get install git` 安装。stage-0 也要先处理这种情况：mise 的 `[bootstrap.repos]`、
  zsh 插件、lazy.nvim 都依赖 git。

## P-003 `curl | sh` 时无法交互读取输入

- **预判**：通过管道执行脚本时 stdin 是脚本本身，`read` 读不到用户输入。
- **解决**：交互输入改为从 `/dev/tty` 读取；没有 tty 时（Dockerfile 中）必须通过环境变量传入，否则报错退出。

## P-004 经 GitHub 代理访问私有仓库会泄露 token

- **预判**：`https://<proxy>/https://<token>@github.com/...` 这种写法会把 token 交给第三方代理。
- **解决**：本仓库和 dotconfig 如果要经代理拉取，必须是公开仓库且不含任何密钥；或者托管到国内平台（CNB / Gitee）。

## P-005 sshd 配置「先出现的值生效」，cloud-init 的 drop-in 会覆盖我们的设置

- **预判**：sshd 对大部分选项采用第一次读到的值；Debian / Ubuntu 的 `sshd_config` 开头就 `Include /etc/ssh/sshd_config.d/*.conf`，
  云镜像通常带有 `50-cloud-init.conf`（里面是 `PasswordAuthentication yes`）。
- **解决**：文件命名为 `00-bootstrap.conf`，保证排在最前面；改完用 `sshd -T | grep -Ei 'permitrootlogin|passwordauthentication'` 确认实际生效的值。

## P-006 mise postinstall 依赖调用方 shell 中的 XDG 变量

- **现象（代码审查发现）**：dotfiles 的 `mise/config.toml` 中，postinstall 使用了 `${XDG_DATA_HOME}`，但 mise 的 `[env]` 并没有定义它。
  新用户第一次执行时，如果没有加载 `~/.zshenv`，路径会变成 `/zsh/site-functions/...`。
- **解决**：见 D-010，不再在 postinstall 中生成补全文件。

## P-007 用 git subtree 合并本机上属主不同的仓库

- **现象**：`git subtree add ... /root/dotconfig main` 报 `Could not read from remote repository`。
- **原因**：`/root/dotconfig` 的属主是 501，git 的 safe.directory 检查拒绝访问。只把 `/root/dotconfig` 加入 safe.directory 还不够，fetch 本地路径时检查的是 `/root/dotconfig/.git`。
- **解决**：`git config --global --add safe.directory /root/dotconfig/.git`。

## P-008 开发环境中执行外部下载的脚本或二进制需要用户授权

- **现象**：2026-10-29，执行 `sh vendor/get-docker.sh --help` 被 Claude Code 的权限规则拦截（Code from External）。
- **影响**：安装 mise / fnox / Docker、在本机跑 PoC 都需要执行外部代码。
- **解决**：由用户在 Claude Code 中添加允许规则，或者用户自己执行（`! <命令>`）；不要尝试绕过这个限制。

## P-009 用户给出的文件路径有笔误

- 用户说的 age 密钥文件是 `/root/age_keys_sope.txt`，实际文件是 `/root/age_keys_sops.txt`。只读取了其中的公钥，私钥不能进入仓库和日志。

## P-010 mise.run 指定非内置版本时，校验值来自 GitHub

- **现象**：用户用 `curl https://mise.run | sh` 安装得到 2026.10.21，而脚本内置的是 2026.10.22（默认只选发布满 24h 的版本）。
  2026.10.21 的校验值是从 GitHub Releases 获取的，在本机能成功只是因为有代理。
- **解决**：D-012，锁定脚本版本，并让 `MISE_VERSION` 等于内置版本。

## P-011 Docker 安装后没有配置 Docker Hub 镜像

- **现象**：get-docker.sh 只配置了 docker-ce 的 apt 源，`/etc/docker/daemon.json` 不存在，国内拉取 Docker Hub 镜像可能失败。
- **解决**：已在本机写入 `{"registry-mirrors": ["https://mirror.ccs.tencentyun.com"]}` 并重启 docker（当时没有运行中的容器）；
  项目中由 `files/docker/daemon.json.tera` 管理（D-005）。
- **注意**：dockerd 不会读取 shell 中的 `http_proxy`，要让它走代理只能用 systemd drop-in。

## P-012 fnox 缺少私钥时只警告，不报错

- **现象**：没有 `FNOX_AGE_KEY` 时，`fnox exec -- true` 只输出 WARN（`Age identity file not found`），命令照常执行。
- **影响**：这是需要的行为。mise bootstrap 只解析选中模板实际用到的机密，容器模式不需要 mihomo 节点，不应该因此失败；
  真正需要时，mise 会因为缺少值在任何改动之前报错退出。

## P-013 本地 clone 时 `git -c safe.directory=*` 无效

- **现象**：新用户从 root 所有的检出目录 `git -c safe.directory="*" clone` 时，仍然报 `detected dubious ownership`。
- **原因**：本地 clone 时实际读取仓库的是 git 启动的 upload-pack 子进程，它不认命令行中给出的 safe.directory。
- **解决**：创建一个临时的全局配置文件（`[safe] directory = *`），用 `GIT_CONFIG_GLOBAL=<临时文件> git clone …`（lib/stage.sh）。

## P-014 基础镜像中没有 curl、wget 和 CA 证书

- **现象**：debian / ubuntu 官方镜像中都没有 curl 和 wget，`/etc/ssl/certs` 为空，不能用 https 源。
- **解决**：先把默认源的域名替换为 `http://mirrors.cloud.tencent.com`（http 不需要 CA 证书，全国各家云都能访问），装好 curl 和 ca-certificates 后再测速选源（lib/apt.sh、bootstrap.sh 的管道模式）。

## P-015 测速时没有跟随跳转，直连 GitHub 总被判为失败

- **现象**：GitHub 的 release 下载会 302 跳转到 githubusercontent，没有 `-L` 时 curl 只拿到 302。
- **解决**：`bs_speed` 加上 `-L`。

## P-016 `mise bootstrap` 不允许 `--only` 与 `--skip` 同时使用

- **现象**：`--dotfiles --skip tools` 报错 `the argument '--only' cannot be used with '--skip'`。
- **解决**：dotfiles 模式下，从 `--only` 的列表中去掉要跳过的部分（lib/stage.sh）。

## P-017 sudo 会把 `--preserve-env` 传递的变量写进系统日志

- **现象**：主机测试的泄露检查在 systemd journal 中找到了 age 私钥：
  `sudo[102]: root : … ENV=… FNOX_AGE_KEY=<私钥> ; COMMAND=/usr/bin/sh /src/bootstrap.sh --stage user`。
- **原因**：sudo 默认记录被保留的环境变量。经命令行传递同样不行（`/proc/*/cmdline` 对其他用户可见）。
- **解决**：root 阶段把私钥写入 `/dev/shm` 中权限 0600、属主为新用户的临时文件，只经 sudo 传递文件路径；
  user 阶段读取后立即删除（lib/stage.sh）。测试中以「state 目录、/var/log、/tmp、/dev/shm 中都找不到私钥」作为检查项。
- 教训：**涉及机密的每一条传递路径，都要用测试去验证它没有落盘**。

## P-018 读取真实 age 私钥被权限规则拦截

- **现象**：在测试中执行 `FNOX_AGE_KEY="$(grep … /root/age_keys_sops.txt)"` 被 Claude Code 拦截（Credential Exploration）。
- **解决**：测试默认临时生成一对**测试用** age 密钥与假节点，替换快照中的 `fnox.toml`（tests/run-host.sh）。
  需要用真实节点验证代理切换时，由用户自己执行 `TEST_REAL_SECRETS=1 FNOX_AGE_KEY=… tests/run-host.sh`。

## P-019 Tera 的 `concat` 在 mise 中已弃用

- **现象**：`mise WARN deprecated [tera-v1-concat]`。
- **解决**：daemon.json 模板改成「为空时输出 `[]`，否则 `split | json_encode`」；由 stage-0 保证列表中没有空项。

## P-020 mihomo 的 deb 包自带 `/etc/mihomo/config.yaml`（conffile）

- 用 `[bootstrap.files]` 覆盖它；安装时使用 `dpkg -i --force-confold`，以后升级 deb 时会保留我们的版本，不会弹出交互提示。

## P-021 herdr 的 claude 集成依赖 claude 的目录，工具是并行安装的

- **现象**：把 `herdr integration install claude` 改成 herdr 自己的 postinstall 后，安装失败：`claude directory not found … install claude code first`。
- **原因**：mise 并行安装工具，herdr 装完时 claude 可能还没装好。原来的写法（全局 postinstall）能成功，正是因为它在所有工具装完后才执行。
- **解决**：仍然放在全局 `[hooks] postinstall`，但只在 `MISE_INSTALLED_TOOLS` 包含 herdr 或 claude 时执行，并先 `mkdir -p` claude 的目录。

## P-022 项目级工具不能放进 zsh 的工具清单

- **现象**：`ztool fnox comp …` 在仓库目录外启动 shell 时报「生成失败」。
- **原因**：fnox 只在本仓库的 `mise.toml` 中声明，只有在仓库目录内才在 PATH 中；在不同目录启动 shell，缓存键会来回变化。
- **解决**：`tools.zsh` 只列全局工具（dotfiles 的 mise 配置中的工具）；部署时才用的工具（fnox、age）不生成补全。

## P-023 执行下载来的二进制被权限规则拦截

- **现象**：为核对 mihomo 独立二进制而执行 `./m.bin -v`，被 Claude Code 拦截（Code from External）。
- **解决**：只下载并计算 sha256，不执行（与 GitHub API 给出的 digest 一致即可）。

## P-024 mcr.microsoft.com 的镜像拉不下来

- **现象**：`docker pull mcr.microsoft.com/powershell:lts-debian-12` 超时。Docker Hub 镜像加速只覆盖 Docker Hub，不覆盖 mcr。
- **影响**：`bootstrap.ps1` 没有做语法检查。
- **解决**：以后在 Windows 上或经 mihomo 代理拉取镜像后补做检查。

## P-025 PowerShell 5.1 没有 `Invoke-WebRequest -NoProxy`

- 这个参数只有 PowerShell 7 才有；Windows 自带的 5.1 用了会报错（被 catch 吞掉，结果是所有代理都被判为不可用）。已去掉。

## P-026 `{ : </dev/tty; }` 在没有终端时让整个 shell 静默退出

- **现象**：管道模式在没有终端的容器中运行时，没有任何输出，退出码为 2（之前的测试都设置了 `BOOTSTRAP_NONINTERACTIVE=1`，所以没有发现）。
- **原因**：`:` 是 POSIX 规定的「特殊内建命令」，它的重定向失败时，非交互 shell 会直接退出（dash 如此）。
- **解决**：改为在子 shell 中尝试：`(exec </dev/tty) 2>/dev/null`（bootstrap.sh、lib/common.sh）。新增 `tests/run-pipe.sh`，不设置 NONINTERACTIVE，覆盖这个场景。

## P-027 root 的 umask 为 077 时，新用户读不到临时检出；私钥转交文件残留

- **现象**：在 dev 主机（腾讯云 Debian 13）上真实部署，切换到新用户时报
  `sh: 0: cannot open /tmp/bootstrap.*/repo/bootstrap.sh: Permission denied`，退出码 2；
  root 阶段写入 `/dev/shm/bootstrap-key.*` 的私钥文件没有被 user 阶段读取删除。
- **原因**：管道模式只把临时目录设为 755，`git clone` 出来的文件仍按当前 umask 创建（077 时为 700/600）。
  root 阶段用 `exec sudo` 切换，user 阶段没能启动时就没有人删除私钥文件。
  （本次 umask 077 来自测试启动脚本，但收紧 root umask 的主机同样会遇到；之前的测试容器 umask 都是 022。）
- **解决**：
  - 管道模式 clone 后 `chmod -R a+rX`；root 阶段切换前用 `sudo -u <用户> test -r` 检查，读不到时（如从 `/root` 下的检出运行）复制到临时目录。
  - 不再 `exec sudo`：user 阶段结束（无论成败）后由 root 阶段兜底删除私钥文件。
  - `tests/run-pipe.sh` 改为在 `umask 077` 下运行（旧代码可复现失败，新代码通过）。
- **另外**：systemd-logind 的 `RemoveIPC=yes` 会在普通用户最后一个登录会话结束时删除其在 `/dev/shm` 中的文件，
  因此需要预先放置私钥文件时，应以 root 身份写入。

## P-028 重新运行时丢失代理设置；容器中注入的宿主机代理没有被使用

- **现象**：
  - dev 主机完整部署后（`env.sh` 已切换为代理变量，`GH_PROXY=''`），以普通用户运行 `bootstrap.sh --dotfiles`，
    重新生成的 `env.sh` 里既没有代理变量，`GH_PROXY` 也是空，之后 GitHub 下载都会直连（国内不可用）。
  - dev 上的容器由编排注入了 `http_proxy=http://host.docker.internal:7890`，但 bootstrap 仍然使用 `GH_PROXY`，`env.sh` 也没有记录代理。
- **原因**：
  - `~/.zshenv` 读取 `env.sh`，于是之后的每个 shell 都继承了 `GH_PROXY=''`，选源逻辑把它当作「用户指定直连」。
  - 只有 mihomo 两次执行的流程会设置 `BS_PROXY_URL`；`--dotfiles` 与容器流程不经过这一步，环境中已有的代理被忽略。
- **解决**：
  - `env.sh` 额外写入 `BOOTSTRAP_GENERATED_GH_PROXY`；继承来的 `GH_PROXY` 与它相同时视为生成值，重新按缓存 / 测速选择。
  - 新增 `bs_detect_proxy`（user 阶段）：环境中的代理（或有 mihomo 模块时本机的 mihomo 端口）能访问 GitHub 就直接使用并写入 `env.sh`；
    不可用则清掉代理变量，回退到 `GH_PROXY`。
  - `tests/run-host.sh` 最后经 zsh 运行一次 `--dotfiles`，再检查 `env.sh`。
- **注意**：已经受影响的机器（`env.sh` 中 `GH_PROXY=''` 且没有标记）：更新代码后运行一次 `--dotfiles`，
  会检测到本机 mihomo 并恢复代理设置（dev 主机已验证）。
- 代理检测在 dev 上实测偶尔有一次请求失败（正常约 2 秒），因此 `bs_detect_proxy` 最多试 3 次。

## P-029 第三方 GitHub 加速代理临时限流（429）或测速全部超时

- **现象**：
  - 本地主机测试中，测速选中的 `ghfast.top` 在安装工具中途开始返回 `429 Too Many Requests`，3 个工具安装失败。
  - 另一次测试在多个测试并行下载时，所有代理的测速（1MiB、10 秒超时、两次取最慢）都失败，结果退回直连，在国内必然失败。
- **原因**：公共加速代理有频率限制、稳定性不可控；测速只代表那一刻的状态。
- **解决**：
  - 所有 mise 调用（含两次执行中的第一次和 fnox 安装）经 `bs_mise_retry`：失败且正在使用 `GH_PROXY` 时，排除当前代理重新测速，
    换一个代理重试一次，并更新 `mirrors.env` 与 `env.sh`（最初只覆盖最后一次执行，之后 fnox 安装也遇到了 429）。
  - `bs_select_gh_proxy` 全部失败时，放宽到 30 秒超时、只测一次再试。
  - 用一个不可用的 `GH_PROXY=https://127.0.0.1:9/` 验证：第一次失败后自动改用 `gh.qninq.cn` 完成。
- **更新（D-031）**：「换一个代理重试」已改为「关闭 GH_PROXY 直连重试一次」：部署过程中只选一次代理，不再重新测速。

## P-030 主机部署后用户家目录中的 zsh 目录属于 root

- **现象**：dev 主机部署后，用户从其他机器 SSH 登录时 zsh 报大量 `Permission denied`：
  `~/.local/share/zsh`、`~/.cache/zsh`、`~/.local/state/zsh`、`~/.local/state/node` 属于 root，补全缓存和插件都无法生成。
- **原因**：有 `/etc/mihomo` 等系统文件时，mise 以 `sudo mise … __apply-system-plan` 执行整个 files 阶段，
  `mise.toml` 中没写 owner 的用户目录也由 root 创建（最小配置已复现；`owner` 不支持模板）。
  容器测试没有系统文件，所以没有出现；主机测试中预热 zsh 的任务丢弃了所有输出，也没有发现。
- **解决**：用户目录改由 `[tasks.bootstrap]` 以当前用户创建（D-024）；root 阶段修复家目录中属于 root 的文件；
  `tests/run-host.sh` 新增「家目录中没有 root 的文件」「zsh 启动没有报错输出」两项检查。
- **另外**：没有终端时启动交互式 zsh，fzf / atuin 的 init 会报 `can't change option: zle`，真实登录不会；
  因此 zsh 启动检查用 `script` 提供伪终端（`tests/zsh-startup-check.sh`）。

## P-031 以已有普通用户运行时 chsh 要求输入密码

- **现象**：`TEST_SUDO_USER=1 tests/run-host.sh` 中，mise 的 `login shell` 步骤执行 `chsh -s /usr/bin/zsh` 报
  `Password: chsh: PAM: Authentication failure`。
- **原因**：普通用户修改自己的登录 shell 需要通过 PAM 验证自己的密码；云主机的默认用户（如 `ubuntu`）通常没有密码（只用公钥登录）。
  以 root 运行时新用户由 `useradd -s zsh` 创建，不会走到 chsh，所以之前没有发现。
- **解决**：以普通用户运行时，root 阶段末尾经 sudo 执行 `chsh -s <zsh> <当前用户>`；mise 随后判断已设置而跳过。
- **另外**：这次失败也触发了「换 GitHub 代理重试」（P-029），重试对非网络错误无害，但提示信息会误导；
  提示改为「mise 执行失败，可能是…」，不再断定原因。

## P-032 Ubuntu 上 zsh 的补全缓存写进了仓库

- **现象**：dev 主机（Ubuntu 24.04）部署后，仓库检出中多出 `dotfiles/.config/zsh/.zcompdump`；
  之后重新运行时提示「有未提交的修改，跳过更新」（本地 sudo 用户模式测试中也出现过）。
- **原因**：Ubuntu 的 `/etc/zsh/zshrc` 在 `/etc/os-release` 为 ubuntu 时先执行一次 `compinit`，dump 写到默认位置
  `$ZDOTDIR/.zcompdump`，而 `ZDOTDIR`（`~/.config/zsh`）链接到仓库。Debian 的全局 zshrc 没有这一段。每次启动还会多做一次 compinit。
- **解决**：`dotfiles/.zshenv` 设置 `skip_global_compinit=1`（该文件注释中给出的方式）；`.gitignore` 增加 `.zcompdump*` 兜底。
- **追加**：只改 `~/.zshenv` 还不够。继承了 `ZDOTDIR` 环境变量的嵌套 zsh（tmux 面板、zsh 中再启动 zsh、`script` 等）
  读取的是 `$ZDOTDIR/.zshenv`，不读 `~/.zshenv`，而 `skip_global_compinit` 没有导出、不会被继承。
  新增 `dotfiles/.config/zsh/.zshenv`，转而读取 `~/.zshenv`。
- **再追加**：在仓库目录中启动 zsh（收尾任务、tmux 面板等）时仍会生成：mise 的 hook-env 在当前目录有带补全的项目工具
  （仓库 `mise.toml` 中的 fnox）且 `compdef` 尚不存在时，会自行执行不带 `-d` 的 `compinit -i`。
  `.zshrc` 在 `mise activate` 之前定义一个只记录调用的 `compdef`，自己的 compinit 之后重放（mise 2026.10.22 的行为）。

## P-033 腾讯云 npm 镜像的根路径返回 404

- **现象**：nvim 预装的网络检测在 dev 主机上总是不通过，而实际预装可以成功。
- **原因**：检测请求的是 `NPM_CONFIG_REGISTRY` 的根路径，`https://mirrors.tencentyun.com/npm/` 根路径返回 404；
  该镜像也不支持 Range（取 1KB 会返回整个 1MB 的元数据）。
- **解决**：改为对一个包的元数据发 HEAD 请求（`${NPM_CONFIG_REGISTRY}prettier`）。

## P-034 mise 渲染文件时父目录必须已存在；`mihomo -t` 会自己生成默认配置

- **现象**：`scripts/render-mihomo.sh` 第一次在 dev 上运行时 mise 报错，但随后的 `mihomo -t` 却显示「test is successful」，
  文件只有 16 字节（`mixed-port: 7890`）。
- **原因**：mise 的 `[bootstrap.files]` 要求目标的父目录已存在（`managed file parent does not exist`）；
  `mihomo -t -d <目录>` 在目录或文件不存在时会创建并写入默认配置，于是校验了一份空配置。
- **解决**：渲染脚本先 `mkdir -p` 父目录；校验前确认渲染成功（脚本 `set -e`，测试中检查渲染的退出码）。

## P-035 测试 mihomo 分流时环境中的 no_proxy 让请求绕过了测试实例

- **现象**：`tests/mihomo-rules.sh` 中 `*.tencentyun.com` 的请求在 mihomo 日志中没有记录。
- **原因**：bootstrap 写入的 `no_proxy` 包含 `.tencentyun.com`，curl 即使指定了 `-x` 也对这些主机直连。
- **解决**：测试中 curl 加 `--noproxy ""`。另外不可达地址（如 443 端口不开放的内网镜像）要等 mihomo 拨号超时才写日志，测试中最多等 12 秒。

## P-036 fallback 组在代理与直连都不可用时选第一个成员

- **现象**：`tests/mihomo-rules.sh` 中假节点不可用，Steam 商店组却仍然经假节点拨号。
- **原因**：健康检查对组内每个成员都访问 `store.steampowered.com`；dev（国内云主机）直连 Steam 商店会超时，DIRECT 也被判为不可用。
  所有成员都不可用时，fallback 按顺序选第一个（节点）。
- **结论**：配置符合需求——家庭网络中 Steam 商店通常可以直连，代理不可用时会回退 DIRECT；两者都不通时用代理也无妨。
  测试中把健康检查地址换成可直连的地址来模拟这种情况，并核对组内实际选中的成员（`Steam商店[DIRECT]`）。

## P-037 开发环境的 prettier 缺少 node；lefthook 钩子会被自动安装

- **现象**：提交时 pre-commit 钩子报 `No version is set for shim: prettier` / `exec: node: not found`，提交被拒。
- **原因**：`mise.dev.toml` 只声明了 prettier，它依赖的 node 来自开发者的全局 mise 配置；这台开发机的全局配置没有 node。
  另外，执行 `MISE_ENV=dev mise …` 时，`mise.dev.toml` 的 postinstall 会自动 `lefthook install`（设计如此），之后所有提交都会经过钩子。
- **解决**：`mise.dev.toml` 显式声明 node（与 dotfiles 中锁定的版本一致）；提交在开发环境中进行：`MISE_ENV=dev mise exec -- git commit …`。

## P-038 macOS 的 /usr/bin/git 是占位程序，没有命令行工具时首次部署失败

- **现象**（编写 macOS 验证清单时发现，未在真机复现）：全新 macOS 上运行管道模式，`command -v git` 能找到 `/usr/bin/git`，
  于是不安装命令行工具，直接 `git clone`；没有 Xcode 命令行工具时这个占位程序只会弹出安装对话框并失败。
  `lib/macos.sh` 中检查命令行工具的逻辑要在检出仓库之后才执行。
- **解决**：管道模式在拉取仓库之前，若为 macOS 且 `xcode-select -p` 失败，执行 `xcode-select --install` 触发系统安装窗口，
  每 5 秒检查一次、最多等待 30 分钟（`BS_CLT_POLL` / `BS_CLT_TIMEOUT` 可覆盖），装好后自动继续；超时则报错退出。
  `tests/run-macos-clt.sh` 在 Linux 容器中用假的 `uname` / `xcode-select` 模拟：等待后继续、超时退出、已安装时不触发安装。

## P-039 管道模式拉取 GitHub 仓库时重复尝试直连

- **现象**：dev 主机（腾讯云 Debian 13）重新部署时，`clone https://github.com/…` 出现两次，每次都要等到超时才换下一个。
- **原因**：候选列表是 `"$GH_PROXY" "" <加速代理…>`；`GH_PROXY` 为空时第一个候选也是直连。直连在国内常常卡住，每次最多等 120 秒。
- **解决**：跳过重复的候选；直连只给 30 秒（浅克隆小仓库足够），加速代理仍为 120 秒。

## P-040 选择 GitHub 加速代理时还没有 git，clone 测试全部失败

- **现象**：主机测试（`tests/run-host.sh`，在检出目录中以 root 运行）中，所有候选都被判为不可用，GH_PROXY 为空、全部直连；
  测试容器屏蔽了 GitHub 直连，于是后续全部失败。
- **原因**：root 阶段的顺序是「选源 → apt 换源 → 安装 git 等基础包」，选源时还没有 git，`bs_gh_test` 的 clone 测试必然失败。
  经管道模式部署时会先安装 git，因此在 dev 主机上没有出现；直接在检出中运行、或系统没有 git 时会出现。
- **解决**：没有 git 时推迟选择（`BS_GH_PENDING`），装好基础包后再选（`bs_select_gh_proxy_pending`），结果补写进 `mirrors.env`；
  读取缓存时如果其中没有 GH_PROXY，也在有 git 时补选。

## P-041 在 Lua 中改写 treesitter 的下载地址无效

- **现象**：nvim 预装经 GH_PROXY 时，插件、Mason、blink.cmp 都成功，treesitter 语法解析器一个都没装上；
  单独安装时报 `curl: (7) Failed to connect to github.com port 443`（测试容器屏蔽了 GitHub 直连）。
- **原因**：`require("nvim-treesitter").install()` 每次都会调用 `reload_parsers()` 重新加载解析器表，预先改过的 `install_info.url` 被覆盖。
- **解决**：nvim 预装第 1 次尝试时，在 PATH 最前面放一个 curl 包装脚本，把以 `https://github.com/`、`https://raw.githubusercontent.com/`
  开头的参数加上 GH_PROXY 前缀（api.github.com 不改）；treesitter、Mason、blink.cmp 的下载都经 curl，一处覆盖。
  Lua 中的地址改写全部去掉；git 仍用 `GIT_CONFIG_*` 的 insteadOf。
- **另外**：测试中所选的 gh.qninq.cn 当天被我频繁访问，返回 429 与 `expected flush after ref listing`，
  说明加速代理随时可能失效，回退直连是必要的（D-031）。

## P-042 nvim 预装在小内存机器上耗尽内存

- **现象**：在开发机（2 核 2G、无 swap）的测试容器中运行 nvim 预装时，整台机器失去响应并重启，会话中断。
- **原因**：treesitter 默认按 CPU 数并行编译几十个语法解析器，单个 cc1 可占数百 MB；Mason 也会并行执行 npm 安装。
- **解决**：`bootstrap.lua` 按 min(CPU 核数, 总内存 GB / 1.5)（至少 1）限制 treesitter 的 `max_jobs` 与 Mason 的
  `max_concurrent_installers`，可用 `NVIM_BOOTSTRAP_JOBS` 覆盖。较重的测试改在 dev 主机（7.5G）上运行。

## P-043 Debian 12 / Ubuntu 22.04 上 atuin 与 tree-sitter 无法运行（glibc 版本）；预装时加速代理大量 429

- **现象**（真机矩阵测试，Debian 12，glibc 2.36）：
  - nvim 预装的语法解析器全部失败：`tree-sitter: /lib/x86_64-linux-gnu/libc.so.6: version 'GLIBC_2.39' not found`；
  - `atuin --version` 同样报 glibc 版本不足；zsh 启动时生成 atuin 初始化脚本失败只记了失败标记，没有报错，atuin 静默失效；
  - 第 1 次预装经 gh.qninq.cn 时，lazy.nvim 同时 clone 几十个插件，大量返回 429，部分插件「clone 成功但 checkout 失败」，
    并且 lazy.nvim 改写了 `lazy-lock.json`（仓库检出变脏）。
- **原因**：
  - tree-sitter CLI 0.26.x / 0.27.x 的官方 Linux 预编译版（`.gz` 与 `.zip`）都链接了 glibc 2.39，没有 musl 版；
    nvim-treesitter（锁定版本）要求 tree-sitter CLI ≥ 0.26.1。glibc 2.39 对应 Ubuntu 24.04+、Debian 13+。
  - aqua 为 atuin 选择 gnu 版（同样需要较新的 glibc），而 atuin 也发布了 musl 静态版。
  - 公共加速代理有频率限制，并发 clone 很快触发。
- **解决**：
  - atuin 改用 mise 的 github 后端，Linux 上指定 musl 资源（`platforms.linux-x64.asset_pattern`），GitHub API digest 校验；
  - nvim 预装检测到 tree-sitter CLI 无法运行时跳过语法解析器并输出 WARNING（不算失败；nvim 回退为正则高亮）；
  - 预装时 lazy.nvim 的 `concurrency = 4`；每次尝试前恢复 `lazy-lock.json`，结束后也恢复；
  - `tests/cloud/verify-host.zsh` 检查全部 mise 工具都能运行，sshd 改用绝对路径（该镜像中 sudo 的 PATH 不含 /usr/sbin）。
- **以后**：如需在旧系统上使用 treesitter，可考虑从源码构建 tree-sitter CLI（需要 Rust 工具链，编译耗内存），暂不做。

## P-044 Ubuntu 镜像上以 root 运行：新用户没有公钥，SSH 加固被跳过；sudo -i 下 zsh 报 terminfo 警告

- **现象**（真机矩阵测试，Ubuntu 26.04，由 ubuntu 用户 `sudo` 成 root 运行）：日志「lostrit 没有 SSH 公钥…跳过 SSH 加固」；
  新用户的 HOME 中没有 `.ssh`；`sudo -u lostrit -i` 启动 zsh 时报 `.zshenv:29: can't find terminal definition for unknown`。
- **原因**：
  - Ubuntu 云镜像中 root 的 `authorized_keys` 为空，公钥在 ubuntu 用户下；bootstrap 只复制 root 的公钥。
  - zsh 在 `TERMINFO_DIRS` 被赋值时重新初始化终端，`TERM` 没有对应的 terminfo 时警告（sudo-rs 的 `-i` 设置 `TERM=unknown`；
    真实场景如 Ghostty 首次登录、远端还没有 `xterm-ghostty` 的 terminfo）。
- **解决**：root 没有公钥且经 sudo 运行时，复制 `SUDO_USER` 的公钥；`.zshenv` 中赋值 `TERMINFO_DIRS` 时屏蔽该警告。

## P-045 Ubuntu 22.04 上 git 报 `unknown style 'zdiff3'`，lazy.nvim 无法安装

- **现象**（真机矩阵测试，Ubuntu 22.04，git 2.34.1）：nvim 预装 3 次都失败，`Failed to clone lazy.nvim: fatal: unknown style 'zdiff3' given for 'merge.conflictstyle'`。
- **原因**：dotfiles 的 git 配置写死了 `merge.conflictstyle = zdiff3`（git 2.35+ 才支持）。普通的提交、clone、log 不读这个设置，
  但部分克隆（`--filter=blob:none`）后 checkout、切换分支、合并时会读取并直接报错；lazy.nvim 正是先部分克隆再 checkout 锁定的提交。
- **解决**：git 配置改为 include `~/.local/state/bootstrap/gitconfig`，由 `scripts/gen-gitconfig.sh`（`[tasks.bootstrap]` 中运行）
  按本机 git 版本写入 `zdiff3` 或 `diff3`；文件不存在时 git 忽略该 include。在 ubuntu:22.04 容器中按 lazy.lua 的方式复现并验证。

## P-046 mise 安装 fnox 时下载 skill 文件，加速代理 429 时整个部署失败

- **现象**（真机矩阵测试，Ubuntu 22.04 重跑）：第一次 `mise bootstrap`（还没有 mihomo）失败：
  `fnox@1.43.0: declared skill(s) fnox are not installed`；日志中 `raw.githubusercontent.com/jdx/fnox/<提交>/skills/fnox/SKILL.md`
  经 gh.qninq.cn 返回 429，回退直连又超时（国内无法直连 raw），bootstrap 报错退出。
- **原因**：mise 2026.10 的 `skills.fetch` 默认开启，安装声明了 agent skill 的工具（fnox）时会从源码仓库下载 skill 文件；
  这也是 R-014 中那次「来源未定位」的 raw 请求。所选加速代理当天被同一 IP 的大量测试请求限流。
- **解决**：bootstrap 运行期间设置 `MISE_SKILLS_FETCH=false`（不写入 env.sh，日常使用不受影响）；在 dev 上验证 fnox 可正常安装。
- **遗留**：所选加速代理在部署中途被限流、且尚无 mihomo 时，回退直连在国内同样失败 → 已增加备用加速代理（D-033）。

## P-047 Ghostty 经 SSH 登录：`xterm-ghostty` 没有 terminfo

- **现象**：用 Ghostty 登录 dev 的 lostrit（Debian 13）后行编辑、nvim、tmux 显示异常；`tput colors` 报 `unknown terminal "xterm-ghostty"`。
- **原因**：Ghostty 默认 `TERM=xterm-ghostty`。各发行版 ncurses 都没有这个名字；ncurses 6.5 起只有 `ghostty` 条目
  （Debian 13、Ubuntu 26.04 有；Debian 12 的 6.4、Ubuntu 22.04 的 6.3、Ubuntu 24.04 的 6.4 都没有，2026-11-04 实测）。
  用户自建镜像的做法（`infocmp -x ghostty` 改名后 `tic`）依赖系统已有 `ghostty` 条目，在旧版本上会失败；
  回退脚本放在 `/etc/profile.d` 与 `/etc/bash.bashrc`，登录 shell 为 zsh 时不生效。
- **解决**：D-034——仓库自带 terminfo 源，root 阶段编译到 `/etc/terminfo`；`.zshrc` 中 TERM 无对应 terminfo 时回退。

## P-048 Mason 的 curl 失败后改用 wget：绕过加速代理，并在 HOME 中生成 `.wget-hsts`

- **现象**：Ubuntu 22.04 真机测试（2026-11-04）中 HOME 多出 `.wget-hsts`，「home tidy」检查失败。
- **原因**：主加速代理 gh.qninq.cn 对 dev 的 IP 返回 429，Mason 用 curl 下载失败后按 `curl():or_else(wget)` 改用 wget；
  nvim 预装只包装了 curl，wget 直接访问 GitHub（经 mihomo），并写入 `~/.wget-hsts`。Ubuntu 云镜像自带 wget，Debian 镜像没有，所以只在 Ubuntu 上出现。
  这次第 2 次尝试已改用备用代理 gh.padao.fun 并全部完成（D-033 在真实限流中生效）。
- **解决**：nvim 预装同时包装 curl 和 wget；`dotfiles/.config/wget/wgetrc` 设置 `hsts-file = ~/.cache/wget-hsts`，
  `.zshenv` 与部署期间都设置 `WGETRC`；HOME 整理把已有的 `~/.wget-hsts` 移到 `~/.cache/wget-hsts`。

## P-049 compose 的 secrets 会让明文落在主机磁盘上

- **现象**：设计容器 sshd 的主机私钥注入（2026-11-06）时，在 dev 上实测 Docker Compose v5.7.0，有三点：
  - `secrets: k: environment: SECRET_K` 注入后，主机上 `/var/lib/docker/rootfs/overlayfs/<容器>/run/secrets/k` 能搜到明文。
  - 容器内这个文件的权限是 0444，并且不是挂载点。
  - 在 `/run/secrets` 加 `tmpfs` 后容器内看不到文件，但磁盘上的明文仍在；`mode: 0400` 被忽略（not supported outside Swarm mode）。
- **原因**：
  - Swarm 之外，Compose 只是模拟 secrets：环境变量来源的内容会在创建容器时复制进容器的可写层。
  - 文件来源则是绑定挂载主机上的明文文件。
  - 另外，容器的 `/dev/shm` 在 `docker restart` 后会被清空，内存中的数据不能跨重启保留。
- **解决**：D-038。主机私钥由 fnox 解密，经 `docker exec -i … bootstrap-sshd load-key` 的管道写入容器的 `/dev/shm`，每次启动后重新注入。
  授权公钥是公开信息，仍用文件来源的 secret。

## P-050 Windows PowerShell 5.1 用 `-File` 运行无 BOM 的 UTF-8 脚本时，中文会破坏语法

- **现象**：GitHub Actions 的 `windows-latest` 上，Windows PowerShell 5.1 执行 `./bootstrap.ps1`（2026-11-06）：脚本一行都没有执行，步骤就失败了，`Tee-Object` 的日志文件也没有生成。
- **原因**：
  - 5.1 读取不带 BOM 的 .ps1 时按系统 ANSI 代码页解码，例如 cp1252 / GBK。
  - UTF-8 中文的某些字节在 cp1252 中是弯引号（0x93 / 0x94），PowerShell 把它们当作字符串定界符，解析因此出错。
  - 另一方面，文件也不能加 BOM：`irm … | iex` 时 BOM 字符（U+FEFF）会被当作第一条命令（dev 上 pwsh 7.5 实测「The term '﻿#' is not recognized」），`param()` 不再是第一条语句。
- **解决**：
  - 保持无 BOM。
  - 文档中的入口统一为 `irm … | iex`（按响应的 UTF-8 解码）。
  - 本地文件用 `& ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 .\bootstrap.ps1))) [参数]`，可以传参数。CI 也这样运行。
  - pwsh 7 默认按 UTF-8 读取，不受影响（`tests/ps-parse.ps1`、`verify-windows.ps1` 在 pwsh 中运行）。


## P-051 macOS 的 /bin/sh（bash 3.2）把 `$var（` 中全角字符的字节当作变量名

- **现象**：GitHub Actions 的 macOS runner（2026-11-06）上，`bootstrap.sh --dotfiles` 在安装 mise 前退出：
  `lib/stage.sh: line 261: _want�: unbound variable`，对应的代码是 `bs_log "安装 mise $_want（CDN：mise.jdx.dev）"`。
- **原因**：macOS 的 `/bin/sh` 是 bash 3.2。它把紧跟在变量名后的非 ASCII 字节（这里是「（」的首字节）也当作变量名的一部分，`set -u` 下就报错退出。
  Linux 上的 dash、bash 5 不会这样，所以容器和真机测试一直没有发现。全仓库共有 34 处这样的写法，例如选源缓存提示中的 `$_cache（`，macOS 第二次运行时就会触发。
- **解决**：
  - 全部改成 `${var}（`。
  - 新增 `scripts/check-sh-vars.sh`，lefthook 的 `sh-var-nonascii` 在提交时检查所有 .sh 文件。

## P-052 Windows PowerShell 5.1：原生命令的标准错误被重定向时，会在 `$ErrorActionPreference = 'Stop'` 下中止脚本

- **现象**：GitHub Actions 中 `bootstrap.ps1 *>&1 | Tee-Object …` 执行到 `mise bootstrap` 时立即失败（2026-11-06）：
  `mise : mise bootstrap: dotfiles … NativeCommandError`，而这一行只是 mise 写到标准错误的进度信息。
- **原因**：5.1 中原生命令的标准错误被重定向时（`2>&1`、`*>&1`、管道），每一行都会变成 ErrorRecord。脚本设置了 `$ErrorActionPreference = 'Stop'`，于是第一行就抛出异常。
  直接在终端中运行时没有重定向，不会触发，所以真机上未必能发现。
- **解决**：
  - `bootstrap.ps1` 新增 `Invoke-Native`：调用原生命令（mise、curl、git、pwsh）时临时改为 `Continue`，成败只看 `$LASTEXITCODE`。
  - 同一轮 CI 还发现另外两处 Windows 问题，一并修复：
    - 全局 mise 配置的 postinstall 钩子是 sh 语法，cmd 报「'case' is not recognized」。改用 `[hooks.postinstall]` 的 `run_windows = "exit /b 0"`。
    - 字体文件注册后被系统占用，重复运行时覆盖失败。改为内容相同时不再复制。

## P-053 mise 的 `[bootstrap.packages] "brew:…"` 只支持 Apple 芯片：Intel Mac 上会直接跳过

- **现象**：GitHub Actions 的 `macos-15-intel` 上执行 `mise -E macos bootstrap packages apply`（2026-11-06），输出
  `brew eza skipped (only available on arm64 macos and x86_64/arm64 linux)`，`git-delta` 也被跳过，退出码为 0。`macos-latest`（Apple 芯片）上正常安装。
- **原因**：mise 2026.10 内置的 Homebrew 软件包实现只支持 arm64 macOS 与 Linux。用户的 Mac 是 Intel 芯片，正好在不支持之列。
- **解决**：改用 `scripts/macos-brew-packages.sh` 直接调用 `brew install`（Intel 与 Apple 芯片都适用），在 mise bootstrap 之后执行；
  Homebrew 的镜像变量沿用 `lib/macos.sh` 的设置。
