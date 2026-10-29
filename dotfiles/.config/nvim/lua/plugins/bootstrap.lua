-- 仅在镜像构建时生效（scripts/bootstrap.sh 会设置 NVIM_BOOTSTRAP=1），日常使用时本文件不做任何事。
--
-- 平时 LazyVim 发现缺少工具或语法解析器时，会在后台自动安装“最新版”。
-- 构建时这会和脚本里的“固定版本安装”同时进行、互相冲突，所以这里关掉后台自动安装，
-- 改由 scripts/bootstrap.lua 按固定版本同步安装。
if not vim.env.NVIM_BOOTSTRAP then
  return {}
end

-- （Mason 的同类处理写在 lua/plugins/mason.lua 中：本文件按字母顺序先于它加载，写在这里会被覆盖。）
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- 把清单交给 bootstrap 脚本，自己不再自动安装
      vim.g.bootstrap_ts_langs = opts.ensure_installed
      opts.ensure_installed = {}
    end,
  },
}
