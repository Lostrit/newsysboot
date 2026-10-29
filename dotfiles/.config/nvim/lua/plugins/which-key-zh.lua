-- which-key：按下 空格（Leader 键）等前缀键后弹出的快捷键提示面板
-- 本文件把面板中的说明文字翻译为简体中文，翻译表见 lua/config/zh.lua
return {
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      local zh = require("config.zh")

      -- which-key 默认的 desc 清理规则（去掉开头的 + 和 :、<Cmd> 等）。
      -- 必须完整写出：选项列表会按下标合并，只写翻译函数会覆盖掉默认的第 1 条规则。
      opts.replace = opts.replace or {}
      opts.replace.desc = {
        { "<Plug>%(?(.*)%)?", "%1" },
        { "^%+", "" },
        { "<[cC]md>", "" },
        { "<[cC][rR]>", "" },
        { "<[sS]ilent>", "" },
        { "^lua%s+", "" },
        { "^call%s+", "" },
        { "^:%s*", "" },
        zh.translate, -- 最后一步：查中文翻译表
      }

      -- 底部帮助栏（"<esc> close  <bs> back"）的文字写死在 which-key 源码里，
      -- 没有提供配置项，这里在输出文字时做替换。
      local Text = require("which-key.text")
      local append = Text.append
      Text.append = function(self, str, hl)
        if hl == "WhichKeySeparator" and type(str) == "string" then
          local word = str:match("^ (%a+)$")
          if word and zh.help[word] then
            str = " " .. zh.help[word]
          end
        end
        return append(self, str, hl)
      end
    end,
  },
}
