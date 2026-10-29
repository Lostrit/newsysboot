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
