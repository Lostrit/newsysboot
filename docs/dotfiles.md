# dotfiles

`dotfiles/` 原为独立仓库 dotconfig，已通过 git subtree 合并进本仓库（D-002）。所有工具使用 mise 进行管理，统一配置 catppuccin mocha 配色或主题方案。
部署方式：bootstrap 把 `~/.config/<tool>` 链接到 `dotfiles/.config/<tool>`，`~/.zshenv` 链接到 `dotfiles/.zshenv`。

> 以下为原 README，已按合并后的目录调整：开发工具配置为仓库根目录的 `mise.dev.toml`，提交钩子为根目录的 `lefthook.yml`。

## 开发环境与生产环境的工具区分

- 生产机器只部署各子目录到 `~/.config`，`mise/config.toml` 作为全局配置使用，**不含任何开发工具**
- 仓库根目录的 `mise.dev.toml` 存放开发工具（taplo / lefthook / prettier），只有 `MISE_ENV=dev` 时才加载
- 开发机初始化：在仓库根目录执行 `mise trust mise.dev.toml && MISE_ENV=dev mise install`（安装开发工具，并自动执行 `lefthook install`）

## Git 提交钩子（lefthook）

在仓库根目录执行 `MISE_ENV=dev mise install` 后会自动安装 lefthook 钩子（仅当仓库根目录存在 lefthook.yml 时）。pre-commit 钩子会对暂存的配置文件：

- **TOML**：`taplo format` 格式化 + `taplo lint --no-schema` 语法校验（schema 校验在 VSCode 里交互进行，避免提交时依赖网络）
- **JSON / YAML**：`prettier --write` 格式化（兼容带注释的 JSONC）
- **shell**（`.zshrc` / `fzfrc`）及旗标式配置（`ripgreprc` / `bat/config`）：`zsh -n` 语法检查（只解析不执行，可拦截引号不闭合；均无可靠的命令行格式化器，故只 lint，格式化在 VSCode 里用 ark-format-shell）
- **gitconfig**：`git config --file` 解析校验

手动安装 / 卸载钩子：`lefthook install` / `lefthook uninstall`；临时跳过：`LEFTHOOK=0 git commit`。
