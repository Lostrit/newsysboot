# 💤 LazyVim（容器开发定制版）

基于 [LazyVim starter](https://github.com/LazyVim/starter) 的 Neovim 配置，在 Ghostty → ssh → tmux 的容器环境中使用，也可以直接用于其他 Linux 环境。

- **技术栈**：node / bun / TypeScript / React / Vue，以及 JSON、YAML、TOML、Dockerfile、docker-compose
- **版本锁定**：插件按 `lazy-lock.json`、Mason 工具按 `lua/config/mason-tools.lua` 安装固定版本
- **新手友好**：按 `空格` 弹出的快捷键菜单全部为简体中文

## 安装

### 前提：系统中需要有的程序

| 程序 | 用途 | 必需 |
| --- | --- | --- |
| Neovim ≥ 0.12（已在 0.12.2 上验证；锁定版本的 nvim-treesitter 要求 0.12） | 编辑器本身 | ✅ |
| git | 下载插件 | ✅ |
| curl、tar、gzip | 下载 Mason 工具、语法解析器、补全库 | ✅ |
| C 编译器（gcc / cc） | 编译 treesitter 语法解析器 | ✅ |
| tree-sitter CLI ≥ 0.26.1（用系统包管理器或 mise 安装，**不要**用 npm 版） | 编译 treesitter 语法解析器 | ✅ |
| node + npm | 大部分语言服务器、prettier 是 npm 包 | ✅ |
| ripgrep（rg）、fd | 全文搜索、文件查找 | 推荐 |
| lazygit | `空格 g g` 打开的 Git 界面 | 推荐 |
| unzip | 以后添加 zip 格式发布的 Mason 工具时需要 | 可选 |

### 方式一：直接启动（任何 Linux 环境）

把本目录放到（或挂载到）`~/.config/nvim`，然后运行 `nvim` 即可。首次启动会自动完成全部安装，无需其他设置或脚本：

1. 按锁定版本下载 lazy.nvim 和 LazyVim，再由 lazy.nvim 按 `lazy-lock.json` 安装其余插件（会弹出 Lazy 安装窗口，装完按 `q` 关闭）
2. 后台编译 treesitter 语法解析器，按 `mason-tools.lua` 安装语言服务器等工具（屏幕右上角会有进度提示，约需几分钟）
3. 首次进入插入模式时，下载补全插件的模糊匹配库

装完后打开代码文件，语言服务器会自动启动。

### 方式二：预先安装（镜像构建 / 离线使用）

```bash
bash ~/.config/nvim/scripts/bootstrap.sh
```

与方式一的安装结果完全相同，区别在于：一次性同步完成，逐项校验版本，失败时以非零状态码退出。适合写进 Dockerfile，让容器运行时不再需要联网。详见 [docs/03-容器镜像构建.md](docs/03-容器镜像构建.md)。

## 文档

| 文档 | 内容 |
| --- | --- |
| [docs/01-配置说明.md](docs/01-配置说明.md) | 每个文件改了什么、为什么改、有什么效果；体检（`:LazyHealth`）结果说明 |
| [docs/02-新手上手.md](docs/02-新手上手.md) | 从未用过 vim 的人如何开始使用 |
| [docs/03-容器镜像构建.md](docs/03-容器镜像构建.md) | Dockerfile 片段、持久化卷、升级流程、tmux 建议 |
