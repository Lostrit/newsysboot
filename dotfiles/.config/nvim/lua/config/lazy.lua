-- ---------------------------------------------------------------------------
-- 首次启动：预先按 lazy-lock.json 克隆 lazy.nvim 与 LazyVim
--
-- 为什么 LazyVim 也要预先克隆：LazyVim 带来了大部分插件的清单（spec）。
-- 如果只装 lazy.nvim，首次启动时它只认识本配置直接写出的几个插件，装完后会按“当前已知插件”
-- 重写 lazy-lock.json，把其余插件的锁定记录删掉，导致它们被装成最新版。
-- 预先装好锁定版本的 LazyVim，lazy.nvim 一开始就能看到全部插件，全部按锁文件安装。
-- ---------------------------------------------------------------------------
local lazy_root = vim.fn.stdpath("data") .. "/lazy"

local lock = {}
pcall(function()
  local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
  lock = vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
end)

---@param name string 插件名（与 lazy-lock.json 中的键相同）
---@param url string git 仓库地址
---@param branch string 锁文件中没有记录时使用的分支
local function clone_locked(name, url, branch)
  local path = lazy_root .. "/" .. name
  if (vim.uv or vim.loop).fs_stat(path) then
    return path
  end
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=" .. branch, url, path })
  local commit = vim.v.shell_error == 0 and vim.tbl_get(lock, name, "commit")
  if commit then
    out = vim.fn.system({ "git", "-C", path, "fetch", "--quiet", "origin", commit })
      .. vim.fn.system({ "git", "-C", path, "checkout", "--quiet", commit })
  end
  if vim.v.shell_error ~= 0 then
    vim.fn.delete(path, "rf") -- 下次启动时重新下载
    vim.api.nvim_echo({
      { "Failed to clone " .. name .. ":\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    -- 无界面（headless，如镜像构建）时直接退出，避免一直等待按键
    if #vim.api.nvim_list_uis() > 0 then
      vim.fn.getchar()
    end
    os.exit(1)
  end
  return path
end

local lazypath = clone_locked("lazy.nvim", "https://github.com/folke/lazy.nvim.git", "stable")
clone_locked("LazyVim", "https://github.com/LazyVim/LazyVim.git", "main")
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  -- 首次安装插件时使用的临时主题（插件版本以 lazy-lock.json 为准）
  -- 不使用 luarocks 安装插件（本配置没有插件需要它），避免 :checkhealth 报告缺少 luarocks
  rocks = { enabled = false },
  install = { colorscheme = { "catppuccin-mocha", "habamax" } },
  checker = {
    enabled = false, -- 关闭后台检查插件更新：版本已锁定，升级走 docs/03 中的流程
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        -- "tutor", -- 保留 :Tutor 交互式教程，方便新手学习
        "zipPlugin",
      },
    },
  },
})
