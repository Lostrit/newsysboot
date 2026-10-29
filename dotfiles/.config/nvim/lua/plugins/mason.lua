-- Mason：负责安装 LSP（语言服务器）、格式化与检查工具。
--
-- LazyVim 默认的做法是：启动时发现缺少哪个工具，就在后台安装它的“最新版”。
-- 这里改为：按 lua/config/mason-tools.lua 中的固定版本安装；
-- 已安装的版本与清单不一致时，也会改装为清单中的版本（类似 lazy-lock.json 对插件的作用）。
-- 因此无论是镜像构建（scripts/bootstrap.sh），还是在新环境里直接运行 nvim，得到的版本都相同。
-- （清单中去掉了 LazyVim 默认的 stylua：它以 zip 发布，需要 unzip；对本技术栈也非必需。）
local tools = require("config.mason-tools")

return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      -- 清空 LazyVim 的“安装最新版”清单，改由下面的 config 按固定版本安装
      opts.ensure_installed = {}
    end,
    config = function(_, opts)
      require("mason").setup(opts)
      local registry = require("mason-registry")

      -- 与 LazyVim 原本的行为一致：某个工具装好后，让当前文件重新触发一次文件类型事件，
      -- 刚装好的语言服务器可以立即启动，不必重开文件
      registry:on("package:install:success", function()
        vim.defer_fn(function()
          require("lazy.core.handler.event").trigger({
            event = "FileType",
            buf = vim.api.nvim_get_current_buf(),
          })
        end, 100)
      end)

      -- 镜像构建时由 scripts/bootstrap.lua 同步安装并校验，这里不做后台安装
      if vim.env.NVIM_BOOTSTRAP then
        return
      end

      registry.refresh(function()
        for name, version in pairs(tools) do
          local ok, pkg = pcall(registry.get_package, name)
          if not ok then
            vim.notify("Mason 中找不到工具：" .. name, vim.log.levels.WARN)
          elseif not pkg:is_installing() and pkg:get_installed_version() ~= version then
            vim.notify(string.format("Mason：安装 %s@%s", name, version))
            pkg:install({ version = version })
          end
        end
      end)
    end,
  },

  -- 语言服务器默认还会被 mason-lspconfig 以“最新版”自动安装。
  -- 对清单中已有的服务器设置 mason = false：不再由 mason-lspconfig 安装，
  -- 直接启用（可执行文件由上面按固定版本装好，Mason 会把它们加入 PATH）。
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local to_package = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
      for server, sopts in pairs(opts.servers or {}) do
        if server ~= "*" and tools[to_package[server]] then
          if sopts == true then
            sopts = {}
            opts.servers[server] = sopts
          end
          if type(sopts) == "table" then
            sopts.mason = false
          end
        end
      end
    end,
  },
}
