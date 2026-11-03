# 开发交接（新的开发机 / 新的 agent 先读这里）

更新时间：2026-11-03。本文档汇总**在仓库其他文档中不容易直接看出、但继续开发必须知道**的信息：开发环境、测试方法、工作约定与待办。
功能与架构见 [plan.md](plan.md)、[usage.md](usage.md)；状态见 [progress.md](progress.md)；每个决定的原因见 [decisions.md](decisions.md)（D-001～D-031）；
踩过的坑见 [pitfalls.md](pitfalls.md)（P-001～P-042）；调研结论见 [research.md](research.md)（R-001～R-014）。

## 1. 仓库与推送

| 项目 | 内容 |
| --- | --- |
| GitHub | `git@github.com:Lostrit/newsysboot.git`（公开；remote 名 `github`） |
| CNB | `https://cnb.cool/xfengjing/lostrit/NewSysBoot.git`（公开；remote 名 `cnb`） |
| 分支 | 只有 `main` |
| 推送 | 用户已授权 agent 自行决定推送：验证通过的提交推送到**两个** remote（`git push github main && git push cnb main`） |
| CNB 凭据 | HTTPS 访问令牌，由用户写入开发机的 `~/.git-credentials`（`credential.https://cnb.cool.helper=store`）。**不要读取、输出或记录令牌**；cnb.cool 的 SSH 22 端口从国内开发机连不上 |
| GitHub 凭据 | 开发机的 SSH 密钥（`~/.ssh/id_ed25519`）。`known_hosts` 中的 github.com 记录丢失时，用 `ssh-keyscan` 获取并与 GitHub 官方公布的指纹（ed25519 `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`）核对后再写入 |
| 提交信息 | Conventional Commits（`feat:` / `fix:` / `docs:` / `chore:`），简体中文 |

### 提交钩子（P-037）

- 开发工具在 `mise.dev.toml`（taplo、lefthook、prettier、node），只在 `MISE_ENV=dev` 时加载。首次：`MISE_ENV=dev mise install`（会自动 `lefthook install`）。
- 装了钩子后，**提交必须在开发环境中进行**：`MISE_ENV=dev mise exec -- git commit …`，否则 prettier 找不到。
- 钩子会检查 zsh 文件语法，开发机需要安装 zsh（`apt-get install zsh`）。
- `files/mihomo/windows-desktop.yaml` 是生成文件：修改 `files/mihomo/config.yaml.tera` 后必须运行 `sh scripts/gen-windows-mihomo.sh`，钩子会检查是否同步。

## 2. 机密（最重要的约束）

- 唯一的机密是 mihomo 节点，加密在 `fnox.toml`（fnox + age，D-008）。age 公钥：`age17ft09zwqg3kd3yvclzp6l3wejln9c8lzc5t68g39ydgv8a79tfdsyshnxq`。
- age **私钥**只在用户手中（原开发机上为 `/root/age_keys_sops.txt`）：agent **绝不能读取、输出、提交或写进日志**，也不要尝试绕过权限规则读取它。
- 需要私钥时请用户执行命令注入（私钥只经 ssh 标准输入传输，写入测试主机的内存文件系统）：

  ```sh
  # 测试主机重装后先删除旧的主机密钥记录；默认用户为 root 时：
  ssh-keygen -R <主机IP>; grep '^AGE-SECRET-KEY-' /root/age_keys_sops.txt | ssh -o StrictHostKeyChecking=accept-new root@<主机IP> 'umask 077; cat > /dev/shm/bootstrap-age.key'
  # 默认用户为 ubuntu 等 sudo 用户时：
  … | ssh … ubuntu@<主机IP> 'sudo sh -c "umask 077; cat > /dev/shm/bootstrap-age.key"'
  ```

  部署脚本读取后立即删除该文件。不要以普通用户身份写入 `/dev/shm`：systemd-logind 会在该用户退出登录时删除其文件。
- 本地测试默认使用临时生成的测试密钥与假节点（`tests/run-host.sh`），不需要真实私钥；用真实节点：`TEST_REAL_SECRETS=1 FNOX_AGE_KEY=… tests/run-host.sh`（由用户执行）。
- 用户曾在对话中误贴过 CNB 令牌，已作废重建：任何令牌出现在对话里都应提醒用户作废。

## 3. 机器与资源

| 机器 | 说明 |
| --- | --- |
| 开发机 | 腾讯云，**2 核 2G、无 swap**（2026-11-03 曾因测试容器中并行编译 treesitter 解析器内存耗尽而重启，P-042）。只适合编辑、提交、轻量测试；**较重的测试（完整容器流程、主机测试、PowerShell 测试）放到 dev 上跑** |
| dev（测试主机） | 腾讯云轻量应用服务器，`62.234.97.210`，2 核 7.5G；本机 `~/.ssh/config` 中 `Host dev`。用户会按需重装为不同系统，重装后要更新 `known_hosts`，`User` 随系统变化（Debian 镜像默认 root，Ubuntu 镜像默认 ubuntu） |
| dev 当前状态 | 由 `tests/run-cloud.sh` 管理（经腾讯云 API 重装，D-032）；最近一次为 Ubuntu 22.04、ubuntu 用户部署完成 |
| 计划 | 用户正在注册可以通过腾讯云 API 重装 dev 的密钥，供 agent 把 dev 重装为不同系统版本做真机测试（见第 6 节待办 1） |

在 dev 上跑重型测试的方法（不经 GitHub，直接传工作区快照）：

```sh
c=$(git stash create) && git archive "${c:-HEAD}" | gzip > snap.tgz   # 未跟踪的新文件先 git add
scp snap.tgz <user>@<dev>:~ && ssh <user>@<dev> 'mkdir -p ~/bstest && tar -C ~/bstest -xzf ~/snap.tgz && cd ~/bstest && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm snap'
ssh <user>@<dev> 'cd ~/bstest && (nohup sh tests/run.sh debian:13 > ~/bstest.log 2>&1; echo EXIT=$? >> ~/bstest.log) >/dev/null 2>&1 </dev/null &'
# 结束后：rm -rf ~/bstest ~/bstest*.log（保持 dev 的 HOME 整洁）
```

长时间命令用 `nohup` / `setsid` 放到后台并写日志，防止 SSH 断开中断（SSH 加固时 root 会被禁止登录，之后改用部署用户登录）。

## 4. 测试

| 测试 | 内容 | 在哪跑 |
| --- | --- | --- |
| `tests/run.sh <镜像>` | 容器完整流程（屏蔽 GitHub 直连），`TEST_RUNS` / `TEST_KEEP` | dev |
| `tests/run-pipe.sh <镜像> [--skip tools]` | 管道模式（`curl \| sh`，umask 077，无终端） | 加 `--skip tools` 可在开发机 |
| `tests/run-dotfiles.sh <镜像>` | `--dotfiles` 模式（无 sudo 用户） | dev |
| `tests/run-host.sh` | 带 systemd 的特权容器：mihomo、Docker、SSH 加固、HOME 整理等 23 项；`TEST_SUDO_USER=1` 以已有 sudo 用户运行 | dev |
| `tests/mihomo-rules.sh` | 三个分流场景 63 项（需要 mihomo，用假节点） | dev |
| `tests/run-windows-config.sh` | Windows 预渲染配置与模板同步、`mihomo -t` | 开发机即可 |
| `tests/run-macos-clt.sh` | macOS 管道模式等待 Xcode 命令行工具（容器中用假命令模拟） | 开发机即可 |
| `tests/run-tidy.sh` | HOME 整理（按腾讯云 Ubuntu 主机的预置文件模拟） | 开发机即可 |
| 真机 | 部署后在 dev 上跑主机检查与真实节点分流检查（脚本思路见对话记录：逐项 `check`，从 `journalctl -u mihomo` 核对实际策略） | dev |

注意：
- 测试容器屏蔽了 GitHub 直连，GitHub 内容只能经加速代理获取；公共加速代理会被频繁测试限流（P-029、P-041），连续测试时可能需要等一段时间或换代理。
- `mise` 下载失败时会自动改走 api.github.com 的资源地址（R-013），这不是 bootstrap 的回退逻辑。

## 5. 当前架构要点（细节见 decisions.md）

- 入口 `bootstrap.sh`（POSIX sh）：管道模式 → root 阶段（选源、apt、建用户 / 加固 SSH、sudoers）→ user 阶段（检出到 `~/.local/share/bootstrap`、HOME 整理、mise、`mise bootstrap` 两次执行、nvim 预装）。Windows 为 `bootstrap.ps1`。
- 模块（`mise.<名>.toml`）：debian、container、mihomo、docker、steamos、macos，由 `lib/detect.sh` 按环境选择。
- 选源（D-006）与 GitHub 加速代理（D-031）：候选在 `lib/gh-proxies.txt`，由 `scripts/update-gh-proxies.sh` 从 github.xxlab.tech 维护（需在国内网络、不经代理的机器上运行，约 5 分钟）；部署时只选一次，缓存 7 天。
- mihomo 三个场景（D-027）：server（Linux 主机，环境变量接入）、desktop（macOS root LaunchDaemon / Windows WinSW 服务，TUN）、steamos（TUN）。
- 状态文件：`~/.local/state/bootstrap/{mirrors.env,env.sh}`；`~/.zshenv` 读取 `env.sh`。

## 6. 待办（按优先级）

1. **真机版本矩阵测试**（D-032）：`sh tests/run-cloud.sh <BlueprintId> <默认用户> [--as-root]`，镜像 ID 与权限说明见 D-032。
   密钥在开发机 `~/.config/tencentcloud/dev.env`（不在仓库）；新开发机上需要用户重新提供该文件。
2. ✅ **版本矩阵测试已完成**（R-015）：5 个版本全部通过。修改部署链路后用 `tests/run-cloud.sh` 重跑（每个版本约 15 分钟）。
3. 待用户决定：是否增加「备用 GitHub 加速代理」——所选代理在部署中途被限流、且尚无 mihomo 时，回退直连在国内也会失败（P-046 遗留）。
4. SteamOS / macOS / Windows 真机验证：按 [verify-steamos.md](verify-steamos.md)、[verify-macos.md](verify-macos.md)、[verify-windows.md](verify-windows.md) 执行（用户暂缓）。
5. 阿里云 / 华为云真机测试（验证内网源探测，华为云、火山引擎的内网域名未核实）。
6. 定期运行 `scripts/update-gh-proxies.sh` 更新加速代理候选（候选质量变化快）。

## 7. 与用户协作的约定

- 始终使用简体中文回答；文档、提交信息也用简体中文。
- 没有需要用户决策的事项时，按「开发 → 更新文档 → 验证测试 → 提交推送」连续推进，不必每步停下等待确认；全部完成后汇报整体过程、当前状态和注意事项。
- 有分歧或取舍时给出推荐方案，用问题让用户选择；用户回复「按推荐执行」即按推荐方案做。
- 涉及删除、覆盖、对外发布的操作先确认（推送已获授权）。
- 不修改 `/root/dotconfig`（已合并为本仓库的 `dotfiles/`，原仓库不再维护）。
