# .themes — Catppuccin 主题（只保留实际使用的文件）

各工具的 Catppuccin 官方主题，原先整仓库复制（约 4.9MB，含截图、测试、CI 和 4 种配色）；
2026-11-02 精简为只保留 **Mocha** 配色中实际使用的文件与各自的 LICENSE（dotconfig 评审第 7 项）。

| 目录 | 上游仓库 | 保留的文件 | 使用方 |
| --- | --- | --- | --- |
| `atuin/` | <https://github.com/catppuccin/atuin> | `themes/mocha/catppuccin-mocha-mauve.toml` | `atuin/themes` 链接到这里的 `themes/`，`config.toml` 中 `[theme] name` |
| `bat/` | <https://github.com/catppuccin/bat> | `themes/Catppuccin Mocha.tmTheme` | `bat/themes` 链接；`bat cache --build` 后生效 |
| `delta/` | <https://github.com/catppuccin/delta> | `catppuccin.gitconfig` | `git/config` 的 `[include]` |
| `eza/` | <https://github.com/catppuccin/eza> | `themes/mocha/catppuccin-mocha-mauve.yml` | `eza/theme.yml` 链接 |
| `lazygit/` | <https://github.com/catppuccin/lazygit> | `themes/mocha/mauve.yml` | `lazygit/config.yml` 链接 |
| `micro/` | <https://github.com/catppuccin/micro> | `themes/catppuccin-mocha-transparent.micro` | `micro/colorschemes` 链接，`settings.json` 中 `colorscheme` |
| `tmux/` | <https://github.com/catppuccin/tmux> | 插件运行所需：`catppuccin.tmux`、两个 `catppuccin_*_tmux.conf`、`status/`、`utils/`、`themes/catppuccin_mocha_tmux.conf` | `tmux.conf` 中 `run` |

更换配色或强调色时，从上游仓库取对应文件放到相同的相对路径，并修改使用方的引用。
tmux 插件会无条件加载 `status/` 下的全部模块，因此整个目录保留；换配色时还需补上 `themes/catppuccin_<flavor>_tmux.conf`。
