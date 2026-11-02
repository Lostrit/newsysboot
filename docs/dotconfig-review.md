# dotconfig 评审（2026-10-29，提交 `803608f`）

> **处理状态（2026-10-29 更新）**：✅ 已处理 / ⏳ 未处理。dotconfig 已合并到 `dotfiles/`，下文的路径以原仓库为准。

以下只是建议，**没有修改** `/root/dotconfig`。优先级：🔴 会导致某个环境装不上 / 用不了，🟠 会影响多环境复用，🟢 小问题。

## 🔴 必须处理

✅ 1. **`.zshrc` 依赖的 `/etc/zsh/zshenv` 不在仓库里**
   `.zshrc` 开头写着依赖它导出 `XDG_*`、`ZDOTDIR`、`ZSH_COMPDUMP`、`fpath`，但仓库中没有这个文件，新机器上什么都没设置。
   → 由本项目提供 `~/.zshenv`（D-003），并把 `.zshrc` 的注释改成「依赖 `~/.zshenv`」。
   另外 `fpath` 里要加上 `$XDG_DATA_HOME/zsh/site-functions`，否则 mise postinstall 生成的补全文件不会被加载。

✅ 2. **npmrc / `.bunfig.toml` 写死了腾讯云内网镜像 `mirrors.tencentyun.com`**
   离开腾讯云内网（macOS、SteamOS、其他云）后，npm/bun 安装会全部失败；mise 的 `npm:` 后端和 Mason 的 npm 工具也会受影响。
   → 按环境渲染：内网用 `mirrors.tencentyun.com/npm/`，公网用 `mirrors.cloud.tencent.com/npm/`，有代理时也可以直接用官方源。

✅ 3. **mise 在国内的下载源**
   - aqua 工具和 eza 补全都从 GitHub 下载 → 通过 `MISE_URL_REPLACEMENTS` 加上 `GH_PROXY` 前缀（research R-001）。
   - node 从 nodejs.org 下载 → 设置 `MISE_NODE_MIRROR_URL=https://mirrors.cloud.tencent.com/nodejs-release/`（地址待验证）。
   - 这些变量应该由 bootstrap 在 mihomo 生效前注入，不建议写死在 dotconfig 里。

## 🟠 影响多环境

✅ 4. **`.gitignore` / `lefthook.yml` 里的路径过时**：仓库根目录以前是 `~/.config`，现在配置都在 `.config/` 下。
   - `.gitignore` 中的 `/herdr/**`、`!/herdr/config.toml`、`/zsh/.zshrc.zwc` 已经匹配不到任何文件。
   - `lefthook.yml` 的 `zsh/.zshrc`、`fzf/fzfrc`、`ripgrep/ripgreprc`、`bat/config`、`git/config`、`delta/**` 等 glob
     应该都匹配不到了（lefthook 按仓库根目录的相对路径匹配），所以 shell 语法检查和 gitconfig 检查很可能一直没有执行。→ 前面加上 `.config/`。
✅ 5. **`herdr/config.toml` 只适用于容器**：`default_shell = "/bin/zsh"`（SteamOS 和 Homebrew 的 zsh 路径不一样）、
   `worktrees.directory = "/workspace/worktrees"`。→ 用模板渲染，或者 herdr 支持的话改成读环境变量。
   → 已处理（2026-11-02）：删除 `default_shell`（herdr 使用 `$SHELL`），`worktrees.directory = "~/worktrees"`；
   herdr 0.9.1 在 dev 上实测会展开 `~`，面板使用登录 shell。
⏳ 6. **nvim 引用了不存在的脚本**：`README.md`、`mason.lua`、`mason-tools.lua`、`bootstrap.lua` 都提到
   `scripts/bootstrap.sh` / `scripts/bootstrap.lua`，但 `.config/nvim/scripts/` 不存在。→ 补上这个脚本，或者删掉相关说明。
✅ 7. **`.themes/` 把主题仓库整个复制进来了**（7 个仓库，约 5MB，包括 tests、assets、`.github`、CI 配置）。
   → 二选一：只保留实际用到的主题文件；或者改用 `[bootstrap.repos]` 按 tag 克隆到 `$XDG_DATA_HOME/themes`。
   → 已处理（2026-11-02）：只保留 Mocha 配色中实际使用的文件与 LICENSE（4.9MB → 约 290KB），来源见 `.themes/README.md`。
✅ 8. **版本锁定不一致**：其他工具都锁了具体版本，但 `claude = "latest"`、`bun = "1.4"` 没有锁；eza 补全从 `main` 分支下载。
   → 统一锁版本（eza 补全改用 `v0.23.5` tag），升级时走 dotconfig 的提交流程。
✅ 9. **mise `[env]` 只在交互式 shell 中生效**：只有 `.zshrc` 执行了 `mise activate`，所以 `EDITOR`、`*_CONFIG_PATH` 等变量
   在 `ssh host cmd`、cron、systemd 用户服务里都不存在。→ 非交互场景也需要的变量（如 `EDITOR`）挪到 `~/.zshenv`，
   或者使用 mise 的 `zprofile = "shims"`。
   → 已处理（2026-11-02）：`~/.zshenv` 把 mise shims 加入 PATH（shim 运行时带上 `[env]`），并导出 `EDITOR` / `VISUAL`；
   dev 上实测 `ssh dev rg`、`bat` 读取配置均正常，交互式 shell 仍使用真实路径。
✅ 10. **docker-compose 使用宿主机代理**：`host.docker.internal:7890` 要求宿主机的 mihomo 监听 docker 网桥地址（`allow-lan`）。
    在云服务器上要避免把 7890 暴露到公网（`bind-address`、认证、安全组都要考虑）；`2224:22` 也映射到了 0.0.0.0。
    这一点和 mihomo 的「服务器」配置一起设计。

## 🟢 小问题

✅ 11. `tmux.conf` 里 `run ~/.config/.themes/...` 和 `source-file ~/.config/tmux/tmux.conf` 写死了 `~/.config`，
    没有用 `$XDG_CONFIG_HOME`（tmux 3.6 的配置文件里可以展开环境变量）。
    → 已改为 `#{d:current_file}`（相对 tmux.conf 自身）与解析时记录的 `@bootstrap_tmux_conf`，tmux 3.6a 实测（2026-11-02）。
✅ 12. bat 自定义主题需要执行 `bat cache --build` 才会生效，但 bat 的 postinstall 里没有这一步；而且 postinstall 可能在 dotfiles 部署之前执行。
    → 放到 bootstrap 最后统一执行（Catppuccin 是否已是 bat 内置主题，需要验证）。
✅ 13. `git/config` 里没有 `user.name` / `user.email`，也没有本机覆盖的入口。→ 加上 `[include] path = config.local`（并 gitignore 它）。
✅ 14. 文件属主是 `501:staff`（从 macOS 复制过来的），用 copy 方式部署时要注意 chown；用 link 方式没有影响。
✅ 15. `no_proxy` 用逗号加空格分隔，个别工具不会去掉空格，建议改成不带空格。
