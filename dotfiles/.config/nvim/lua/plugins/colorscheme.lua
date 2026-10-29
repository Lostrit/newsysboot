-- 配色主题：Catppuccin Mocha，与 tmux / fzf 保持一致。
-- catppuccin 插件 LazyVim 已自带，这里只需告诉 LazyVim 使用它。
return {
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "catppuccin-mocha" },
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      -- 关闭“自动检测已安装插件”：它会调用 nvim 0.12 自带的 vim.pack，
      -- 顺带创建空目录 ~/.local/share/nvim/site/pack/core，导致 :checkhealth 出现两条无意义的警告。
      -- LazyVim 已经显式列出了各插件的配色集成，自动检测只多补了 blink.cmp，这里手动补上。
      auto_integrations = false,
      integrations = { blink_cmp = true },
    },
  },
}
