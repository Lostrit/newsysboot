# 设计：工具的 shell 集成（补全 / init 脚本 / 目录）与 zshrc 解耦

状态：🟡 方案，待在阶段 4 实现

## 1. 现状的问题

### mise `postinstall` 负责建目录、生成补全

- **依赖安装时的环境**：postinstall 用到 `${XDG_DATA_HOME}`，但 mise 的 `[env]` 没有定义它，这个值只能来自调用方的 shell。
  bootstrap 以新用户第一次运行时，如果还没有加载 `~/.zshenv`，`f="/zsh/site-functions/_bat"` 会写到根目录（见 pitfalls P-006）。
- **只在「安装」时触发**：补全目录被清掉、换了终端环境、工具改由 brew/apt 安装时都不会重新生成；而且每个工具的 postinstall 都重复了同样的 7 行模板代码。
- **职责混在一起**：「工具装好」「目录存在」「shell 能用上这个工具」是三件事，现在全放在工具定义里。
- 部分 init 脚本（atuin、fzf、starship）在 `.zshrc` 中每次启动都 `eval "$(xxx init zsh)"`，每个都要多起一个子进程。

### `.zshrc` 中大量 `(( $+commands[x] )) && …`

工具清单在两个地方维护（mise `config.toml` 和 `.zshrc`），加一个工具要改两处；判断代码的顺序和插件加载顺序混在一起。

## 2. 方案

一句话：**mise 只负责安装工具；目录由 bootstrap 声明；shell 集成由 zsh 在启动时按一份清单生成并缓存，工具升级时自动失效重新生成。**

### 2.1 目录 → `[bootstrap.directories]`

XDG 根目录和 `zsh/{site-functions,plugins}`、`$XDG_CACHE_HOME/zsh`、`$XDG_STATE_HOME/zsh` 在本仓库的 `mise.toml` 中声明。
工具各自的数据目录（bat cache、npm prefix 等）大多会由工具自己按需创建，不再预先创建；个别不会自己创建的，单独声明。

### 2.2 补全与 init 脚本 → 声明式清单 + 启动时缓存

```
$ZDOTDIR/
├── .zshrc            # 只保留框架：选项 → fpath 插件 → compinit → 工具 init → 其余插件 → 提示符
├── tools.zsh         # 工具清单（唯一需要随工具增减修改的地方）
├── lib/zcache.zsh    # 缓存生成器（约 30 行）
└── conf.d/*.zsh      # 只有需要额外 zstyle / alias 的工具才放一个文件，按文件名排序加载
```

`tools.zsh` 示例：

```zsh
#     命令      类型   生成命令
ztool mise      comp  'mise completion zsh'
ztool bat       comp  'bat --completion zsh'
ztool rg        comp  'rg --generate complete-zsh'
ztool fd        comp  'fd --gen-completions zsh'
ztool atuin     comp  'atuin gen-completions --shell zsh'
ztool atuin     init  'atuin init zsh'
ztool fzf       init  'fzf --zsh'
ztool zoxide    init  'zoxide init zsh'
ztool starship  init  'starship init zsh'   # 提示符，最后加载
```

`ztool <cmd> <comp|init> <生成命令>` 的逻辑：

1. `(( $+commands[$cmd] )) || return`：机器上没有这个工具就直接跳过，不再需要逐个写判断；
2. 用 `${commands[$cmd]:A}`（解析符号链接后的真实路径）作为缓存键。mise 的安装路径里带版本号，工具升级后路径变化，缓存自动失效；
3. 缓存键和 stamp 文件中记录的不同时，执行生成命令，写入 `.tmp` 后再 `mv`（失败不会留下空文件）：
   - `comp` → `$XDG_CACHE_HOME/zsh/completions/_<cmd>`（这个目录在 compinit 之前加入 fpath）
   - `init` → `$XDG_CACHE_HOME/zsh/init/<cmd>.zsh`，在 compinit 之后按清单顺序 source
4. 缓存命中时，每个工具只多一次 stat，不起子进程，启动反而比现在更快。

要点：

- 缓存放在 `XDG_CACHE_HOME`，可以随时删除；不再写 `XDG_DATA_HOME/zsh/site-functions`（那里只放手写或第三方的补全文件）。
- `.zshrc` 里继续使用 `mise activate zsh`（不用 shims），因为 `:A` 需要解析到带版本号的真实路径。
- bootstrap 的 `[tasks.bootstrap]` 最后执行一次 `zsh -i -c exit` 预热缓存；镜像构建时也同样预热。
- 发布包里不带补全、需要下载静态文件的工具（如 eza）：清单支持 `ztool eza file <url>`，URL 锁定到对应版本的 tag，并加上 `GH_PROXY` 前缀。
- 加工具：mise `config.toml` 中加一行 + `tools.zsh` 中加一行；删工具时 `tools.zsh` 不改也不会报错。

### 2.3 mise `[hooks]` 中保留的部分

只保留确实属于「安装动作」本身的事情（如 `herdr integration install claude`），并且改为依据
`MISE_INSTALLED_TOOLS`（全局 postinstall 能拿到的 JSON 数组）判断：只在 herdr 被安装 / 升级时执行，而不是每次 `mise install` 都执行。

## 3. 考虑过的其他方案

| 方案 | 不采用的原因 |
| --- | --- |
| 保留 postinstall，提取成公共函数 | 仍然只在安装时触发，且依赖安装时的环境变量 |
| 一个全局 postinstall hook 读取 `MISE_INSTALLED_TOOLS` 生成补全 | 解决了重复代码，但「补全目录被清掉 / 工具不由 mise 安装」的情况仍然不会重新生成；可以作为缓存预热的补充 |
| carapace（一个程序提供上千个命令的补全） | 可以作为补充，但工具自带的补全更准确，而且 init 脚本的问题它解决不了 |
| zinit / sheldon 等插件管理器 | 现有的 zsh_unplugged 已经足够；问题出在工具集成上，与插件管理器无关 |
