-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- 当前环境判断：用于下面的剪贴板和“用系统程序打开”
local function has(cmd)
  return vim.fn.executable(cmd) == 1
end
-- 通过 ssh 连接（例如 Ghostty → ssh → 容器）：nvim 所在机器不是你面前的这台电脑
local is_remote = vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil or vim.env.SSH_CLIENT ~= nil
-- 本机有可用的剪贴板工具（桌面 Linux / macOS / WSL）
local has_native_clipboard = (vim.env.WAYLAND_DISPLAY and has("wl-copy"))
  or (vim.env.DISPLAY and (has("xclip") or has("xsel")))
  or has("pbcopy")
  or has("win32yank.exe")

-- ---------------------------------------------------------------------------
-- 剪贴板
-- * 远程（ssh）或没有剪贴板工具时（例如本容器）：通过 OSC 52 把复制内容发送到你本机的终端剪贴板
--   链路：nvim → tmux（set-clipboard on）→ ssh → Ghostty → 系统剪贴板
--   - 复制（y、d 等）：写入系统剪贴板，可在本机任意程序中粘贴
--   - 粘贴（p）：只读取 nvim 自己记住的内容，不去读本机剪贴板，
--     避免 Ghostty 每次弹窗询问“是否允许读取剪贴板”。
--     需要粘贴本机剪贴板内容时，在插入模式下用 Ghostty 的粘贴快捷键（Cmd/Ctrl+Shift+V）。
-- * 在桌面 Linux 本地运行时：沿用 nvim 自动检测到的剪贴板工具（wl-copy / xclip 等），复制粘贴都走系统剪贴板
-- ---------------------------------------------------------------------------
if is_remote or not has_native_clipboard then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste_from_register()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end
  vim.g.clipboard = {
    name = "OSC 52（仅复制）",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste_from_register, ["*"] = paste_from_register },
  }
end
-- LazyVim 在 SSH 环境中默认关闭系统剪贴板同步，这里始终打开
vim.opt.clipboard = "unnamedplus"

-- bun 的锁文件 bun.lock 是带注释/尾逗号的 JSON（JSONC），按 jsonc 高亮与校验
-- （放在 options.lua 而非 autocmds.lua：后者加载较晚，直接 `nvim bun.lock` 时会来不及生效）
vim.filetype.add({ filename = { ["bun.lock"] = "jsonc" } })

-- docker compose 文件使用专门的文件类型，这样会额外启用 docker-compose 语言服务（校验服务、镜像等字段）；
-- 同时仍按 yaml 做语法高亮
vim.filetype.add({
  pattern = {
    ["compose%.ya?ml"] = "yaml.docker-compose",
    ["docker%-compose.*%.ya?ml"] = "yaml.docker-compose",
  },
})
vim.treesitter.language.register("yaml", "yaml.docker-compose")

-- 关闭用不到的“远程插件”语言支持（Node / Perl / Python / Ruby）。
-- 它们只服务于极少数用这些语言编写的旧式插件，本配置中没有；关闭后启动更快，
-- :checkhealth 也不会再提示缺少 neovim npm 包、Python 模块等。
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0

-- “用系统程序打开”（gx 打开光标处链接、Git 在浏览器中打开等）：
-- 远程（ssh）或当前环境没有“打开”程序时（例如本容器），无法在你面前的电脑上打开浏览器，
-- 这里改为把链接复制到剪贴板（经 OSC 52 到达本机），再到本机浏览器里粘贴即可。
-- 在桌面 Linux 本地运行时保持 nvim 默认行为（用 xdg-open 等直接打开）。
local has_opener = has("xdg-open") or has("wslview") or has("explorer.exe") or has("lemonade") or has("open")
if is_remote or not has_opener then
  vim.ui.open = function(path)
    vim.fn.setreg("+", path) -- 发送到本机剪贴板
    vim.fn.setreg("\"", path) -- 同时放进 nvim 默认寄存器，在 nvim 里按 p 也能粘贴
    vim.notify("当前环境无法直接打开，已复制到剪贴板：\n" .. path, vim.log.levels.INFO)
    return nil, nil
  end
end
