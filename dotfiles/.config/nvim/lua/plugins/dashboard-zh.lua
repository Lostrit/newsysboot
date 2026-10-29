-- 启动页（Dashboard，直接运行 nvim 时看到的首页）的简体中文化
--
-- 1. 菜单文字：把启动页上“Find File / Recent Files …”等菜单项翻译为中文（翻译表见 lua/config/zh.lua）
-- 2. which-key 说明：snacks 为启动页上的每个按键注册快捷键时，说明一律写死为 "Dashboard action"，
--    which-key 无法区分它们。这里在启动页每次渲染完成后，把这些按键的说明改为对应菜单项的中文名称。
return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      local zh = require("config.zh")
      local items = vim.tbl_get(opts, "dashboard", "preset", "keys") or {}

      local desc_by_key = { ["<CR>"] = "执行光标所在的菜单项" }
      for _, item in ipairs(items) do
        if item.desc then
          item.desc = zh.translate(item.desc)
          if item.key then
            desc_by_key[item.key] = item.desc
          end
        end
      end

      vim.api.nvim_create_autocmd("User", {
        pattern = "SnacksDashboardUpdatePost",
        group = vim.api.nvim_create_augroup("dashboard_zh", { clear = true }),
        callback = function()
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "snacks_dashboard" then
              for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
                local desc = desc_by_key[map.lhs]
                if map.desc == "Dashboard action" and desc and map.callback then
                  vim.keymap.set("n", map.lhs, map.callback, {
                    buffer = buf,
                    nowait = map.nowait == 1,
                    desc = desc,
                  })
                end
              end
            end
          end
        end,
      })
    end,
  },
}
