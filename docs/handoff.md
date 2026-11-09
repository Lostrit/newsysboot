# 开发交接（新的开发机 / 新的 agent 先读这里）

更新时间：2026-11-09。本文档汇总**在仓库其他文档中不容易直接看出、但继续开发必须知道**的信息：开发环境、测试方法、工作约定与待办。
功能与架构见 [plan.md](plan.md)、[usage.md](usage.md)；状态见 [progress.md](progress.md)；每个决定的原因见 [decisions.md](decisions.md)（D-001～D-043）；
踩过的坑见 [pitfalls.md](pitfalls.md)（P-001～P-054）；调研结论见 [research.md](research.md)（R-001～R-016）。

## 1. 仓库与推送

| 项目 | 内容 |
| --- | --- |
| GitHub | `https://github.com/Lostrit/newsysboot.git`（公开；remote 名 `github`） |
| CNB | `https://cnb.cool/xfengjing/lostrit/NewSysBoot.git`（公开；remote 名 `cnb`） |
| 分支 | 只有 `main` |
| 推送 | 用户曾授权 agent 自行决定推送：验证通过的提交推送到**两个** remote（`git push github main && git push cnb main`）。迁移到 dev 后由 dev 主会话请用户再确认一次（D-042） |
| CNB 凭据 | 开发检出的仓库级 credential helper `cnb git-credential`（cnb-cli 经 OAuth 设备授权登录）。**不要读取、输出或记录令牌**；cnb.cool 的 SSH 22 端口从国内主机连不上 |
| GitHub 凭据 | 开发检出的仓库级 credential helper `gh auth git-credential`（gh 已登录 Lostrit 账号）。不复制旧开发机的令牌或 SSH 密钥 |
| 提交信息 | Conventional Commits（`feat:` / `fix:` / `docs:` / `chore:`），简体中文 |

### 提交钩子（P-037）

- 开发工具在 `mise.dev.toml`（taplo、lefthook、prettier、node），只在 `MISE_ENV=dev` 时加载。首次：`MISE_ENV=dev mise install`（会自动 `lefthook install`）。
- 装了钩子后，**提交必须在开发环境中进行**：`MISE_ENV=dev mise exec -- git commit …`，否则 prettier 找不到。
- 钩子会检查 zsh 文件语法（dev 已有 zsh）。
- `files/mihomo/windows-desktop.yaml` 是生成文件：修改 `files/mihomo/config.yaml.tera` 后必须运行 `sh scripts/gen-windows-mihomo.sh`，钩子会检查是否同步。

## 2. 机密（最重要的约束）

- 仓库中唯一的机密是 mihomo 节点，加密在 `fnox.toml`（fnox + age，D-008），同时对两把公钥加密（D-042）：
  - 用户的 age 密钥 `age17ft09zwqg3kd3yvclzp6l3wejln9c8lzc5t68g39ydgv8a79tfdsyshnxq`：私钥由用户离线保管，部署新主机时注入。
  - dev 密钥库的密钥 `age1k79xtae5calfxnf9s42lw7kqrkcjjgmk8775lt39sdr5tczwkfdqfvjmwp`：私钥只在 dev 的 `~/secrets` 中，由 dev 主会话管理。
- age **私钥**：agent **绝不能读取、输出、提交或写进日志**，也不要尝试绕过权限规则读取它。需要用私钥的操作（如 `fnox reencrypt`）请用户执行。
- 在 dev 上需要解密仓库的 `fnox.toml` 时，用 dev 主会话提供的 `with-vault-key`（`~/.local/bin`，在仓库目录中运行），不要把私钥放进 `FNOX_AGE_KEY`：
  - `with-vault-key -- <命令>`：用 dev 密钥库的私钥解密，以环境变量注入命令（`fnox exec --redact`）；
  - `with-vault-key check`：只检查能否解密，不输出值。
- 腾讯云 API 凭据（`scripts/tccloud.py`、`tests/run-cloud.sh` 用）存在 dev 密钥库的 `tencentcloud` profile 中，
  用 `with-secrets -P tencentcloud -- <命令>` 以环境变量注入；不再使用 `~/.config/tencentcloud/dev.env`。
- 需要私钥时请用户执行命令注入（私钥只经 ssh 标准输入传输，写入测试主机的内存文件系统）：

  ```sh
  # 测试主机重装后先删除旧的主机密钥记录；默认用户为 root 时：
  ssh-keygen -R <主机IP>; grep '^AGE-SECRET-KEY-' <用户的私钥文件> | ssh -o StrictHostKeyChecking=accept-new root@<主机IP> 'umask 077; cat > /dev/shm/bootstrap-age.key'
  # 默认用户为 ubuntu 等 sudo 用户时：
  … | ssh … ubuntu@<主机IP> 'sudo sh -c "umask 077; cat > /dev/shm/bootstrap-age.key"'
  ```

  部署脚本读取后立即删除该文件。不要以普通用户身份写入 `/dev/shm`：systemd-logind 会在该用户退出登录时删除其文件。
- 本地测试默认使用临时生成的测试密钥与假节点（`tests/run-host.sh`），不需要真实私钥；用真实节点：`TEST_REAL_SECRETS=1 FNOX_AGE_KEY=… tests/run-host.sh`（由用户执行）。
- 用户曾在对话中误贴过 CNB 令牌，已作废重建：任何令牌出现在对话里都应提醒用户作废。

## 3. 机器与资源

| 机器 | 说明 |
| --- | --- |
| dev（开发主机，正式开发环境） | 腾讯云轻量应用服务器，`62.234.97.210`，2 核 7.5G，Debian 13，用户 `lostrit`（角色 host）。**2026-11-09 起本项目在 dev 上开发**（D-042），原 2G 开发机随后重装、不再使用 |
| 开发检出 | `~/projects/bootstrap`：开发、测试、提交、推送都在这里 |
| 部署副本 | `~/.local/share/bootstrap`：dev 自身的部署（dotfiles 从这里链接）。改动走「开发检出提交推送 → dev 主会话在部署副本 `git pull --ff-only` 和 `mise install`」，**不要在部署副本里开发或运行 `mise upgrade --bump`** |
| 分工 | **dev 主会话**（herdr 中的主 Claude 会话）管理整台机器：部署副本、密钥库 `~/secrets`、herdr 队友窗格。bootstrap 的开发由它开的 `bootstrap` 队友（或它自己）在开发检出中进行 |
| 禁止 | **不得对 dev 运行 `tests/run-cloud.sh` / `scripts/tccloud.py reset`**：会经腾讯云 API 重装系统。两个脚本都会拒绝以 dev 为目标（按公网 IP 判断）。真机版本矩阵测试要另开临时测试主机 |

在 dev 上跑测试：直接在开发检出中运行（测试脚本会把工作区快照打包进测试容器）。长时间测试用 `nohup` 放到后台并写日志：

```sh
cd ~/projects/bootstrap
(nohup sh tests/run.sh debian:13 > /tmp/bstest.log 2>&1; echo EXIT=$? >> /tmp/bstest.log) >/dev/null 2>&1 </dev/null &
```

dev 是正式环境：测试结束后**必须清理**测试容器、测试镜像和临时目录（`docker ps -a`、`docker images` 核对），不要影响用户正在使用的容器与服务。

## 4. 测试

| 测试 | 内容 | 在哪跑 |
| --- | --- | --- |
| `tests/run.sh <镜像>` | 容器完整流程（屏蔽 GitHub 直连），`TEST_RUNS` / `TEST_KEEP` | dev |
| `tests/run-pipe.sh <镜像> [--skip tools]` | 管道模式（`curl \| sh`，umask 077，无终端） | dev |
| `tests/run-dotfiles.sh <镜像>` | `--dotfiles` 模式（无 sudo 用户） | dev |
| `tests/run-host.sh` | 带 systemd 的特权容器：mihomo、Docker、SSH 加固、HOME 整理等 23 项；`TEST_SUDO_USER=1` 以已有 sudo 用户运行 | dev |
| `tests/mihomo-rules.sh` | 三个分流场景 63 项（需要 mihomo，用假节点） | dev |
| `tests/run-windows-config.sh` | Windows 预渲染配置与模板同步、`mihomo -t` | dev |
| `tests/run-macos-clt.sh` | macOS 管道模式等待 Xcode 命令行工具（容器中用假命令模拟） | dev |
| `tests/run-tidy.sh` | HOME 整理（按腾讯云 Ubuntu 主机的预置文件模拟） | dev |
| GitHub Actions `local-systems` | Windows（`windows-latest`）与 macOS（`macos-15-intel`、`macos-latest`）的部署与检查（D-041）；推送到 GitHub 后自动运行，用 `gh run list` 查看 | GitHub |
| `tests/ps-parse.ps1` | PowerShell 语法；dev 上用 `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 mise x aqua:PowerShell/PowerShell@7.5.4 -- pwsh -NoProfile -File tests/ps-parse.ps1 …`（dev 没有 libicu） | dev |
| 真机 | `tests/run-cloud.sh` 重装**临时测试主机**并部署、检查（`tests/cloud/verify-{host,route}.zsh`） | 临时测试主机（不能是 dev） |

注意：
- 测试容器屏蔽了 GitHub 直连，GitHub 内容只能经加速代理获取；公共加速代理会被频繁测试限流（P-029、P-041），连续测试时可能需要等一段时间或换代理。
- `mise` 下载失败时会自动改走 api.github.com 的资源地址（R-013），这不是 bootstrap 的回退逻辑。

## 5. 当前架构要点（细节见 decisions.md）

- 入口 `bootstrap.sh`（POSIX sh）：管道模式 → root 阶段（选源、apt、建用户 / 加固 SSH、sudoers）→ user 阶段（检出到 `~/.local/share/bootstrap`、HOME 整理、mise、`mise bootstrap` 两次执行、nvim 预装）。Windows 为 `bootstrap.ps1`。
- 模块（`mise.<名>.toml`）：debian、container、mihomo、docker、steamos、macos，由 `lib/detect.sh` 按环境选择。
- 选源（D-006）与 GitHub 加速代理（D-031）：候选在 `lib/gh-proxies.txt`，由 `scripts/update-gh-proxies.sh` 从 github.xxlab.tech 维护（需在国内网络、不经代理的机器上运行，约 5 分钟）；部署时只选一次（主代理 + 备用代理，D-033），缓存 7 天。
- mihomo 三个场景（D-027）：server（Linux 主机，环境变量接入）、desktop（macOS root LaunchDaemon / Windows WinSW 服务，TUN）、steamos（TUN）。
- 状态文件：`~/.local/state/bootstrap/{mirrors.env,env.sh}`；`~/.zshenv` 读取 `env.sh`。
- 环境（D-036）：本地系统 macOS / Windows / SteamOS，远程系统 Linux 主机 / 容器；工具全集在 `dotfiles/.config/mise/config.toml`，
  各环境排除的在 `lib/tool-roles.txt`（**改工具名时两边一起改**，必须是完整名，如 `aqua:jqlang/jq`）。差异见 [platforms.md](platforms.md)。

## 6. 待办（按优先级）

1. **真机版本矩阵测试**（D-032）：`DEV_IP=<临时主机 IP> with-secrets -P tencentcloud -- sh tests/run-cloud.sh <BlueprintId> <默认用户> [--as-root]`，镜像 ID 与权限说明见 D-032。
   凭据中的 `INSTANCE_ID` 目前指向 dev，需要用户另开一台临时轻量服务器并更新凭据后才能再跑（D-042）。
2. ✅ **版本矩阵测试已完成**（R-015）：5 个版本全部通过。修改部署链路后用 `tests/run-cloud.sh` 重跑（每个版本约 15 分钟）。
3. ✅ 备用 GitHub 加速代理（D-033）：失败链路为「主代理 → 备用代理 → 直连」。
4. SteamOS / macOS / Windows 真机验证：按 [verify-steamos.md](verify-steamos.md)、[verify-macos.md](verify-macos.md)、[verify-windows.md](verify-windows.md) 执行（用户暂缓）。
5. 阿里云 / 华为云真机测试（验证内网源探测，华为云、火山引擎的内网域名未核实）。
6. 定期运行 `scripts/update-gh-proxies.sh` 更新加速代理候选（候选质量变化快）。

## 7. 与用户协作的约定

- 始终使用简体中文回答；文档、提交信息也用简体中文。
- 没有需要用户决策的事项时，按「开发 → 更新文档 → 验证测试 → 提交推送」连续推进，不必每步停下等待确认；全部完成后汇报整体过程、当前状态和注意事项。
- 有分歧或取舍时给出推荐方案，用问题让用户选择；用户回复「按推荐执行」即按推荐方案做。
- 涉及删除、覆盖、对外发布的操作先确认（推送已获授权）。
- 不修改 `/root/dotconfig`（已合并为本仓库的 `dotfiles/`，原仓库不再维护）。
