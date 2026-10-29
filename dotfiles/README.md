个人 dotconfig 配置，目前还在测试阶段。所有工具使用 mise 进行管理，统一配置 catppuccin mocha 配色或主题方案。

## 开发环境与生产环境的工具区分

- 生产机器只部署各子目录到 `~/.config`，`mise/config.toml` 作为全局配置使用，**不含任何开发工具**
- 仓库根目录的 `mise.toml` 是 mise 项目级配置，仅在仓库检出目录内生效（且需 `mise trust`），存放开发工具：taplo / lefthook / prettier
- 开发机初始化：在仓库目录内执行 `mise trust && mise install`（安装开发工具，并自动执行 `lefthook install`）
- 注意：部署时不要把根目录的 `mise.toml` / `lefthook.yml` 同步到 `~/.config`

## Git 提交钩子（lefthook）

在仓库目录内执行 `mise install` 后会自动安装 lefthook 钩子（仅当仓库根目录存在 lefthook.yml 时）。pre-commit 钩子会对暂存的配置文件：

- **TOML**：`taplo format` 格式化 + `taplo lint --no-schema` 语法校验（schema 校验在 VSCode 里交互进行，避免提交时依赖网络）
- **JSON / YAML**：`prettier --write` 格式化（兼容带注释的 JSONC）
- **shell**（`.zshrc` / `fzfrc`）及旗标式配置（`ripgreprc` / `bat/config`）：`zsh -n` 语法检查（只解析不执行，可拦截引号不闭合；均无可靠的命令行格式化器，故只 lint，格式化在 VSCode 里用 ark-format-shell）
- **gitconfig**：`git config --file` 解析校验

手动安装 / 卸载钩子：`lefthook install` / `lefthook uninstall`；临时跳过：`LEFTHOOK=0 git commit`。
