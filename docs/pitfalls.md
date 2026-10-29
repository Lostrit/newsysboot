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
