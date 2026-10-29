-- 格式化（conform.nvim）：去掉本环境用不到的两个格式化工具
-- * stylua（Lua）：未安装（见 lua/plugins/mason.lua）；Lua 文件改用 lua-language-server 自带的格式化
-- * fish_indent（fish shell）：容器里没有 fish
-- 这样 :checkhealth 不会再提示这两个工具找不到。
return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.lua = nil
      opts.formatters_by_ft.fish = nil
    end,
  },
}
