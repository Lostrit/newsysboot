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
