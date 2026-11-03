-- scripts/bootstrap.lua —— 由 scripts/bootstrap.sh 以 `NVIM_BOOTSTRAP=1 nvim --headless -c "luafile …"` 调用
--
-- 按固定版本同步安装，每一步都校验；全部齐全时以 0 退出，否则以非零退出（由 bootstrap.sh 重试）：
--   1. 插件：按 lazy-lock.json 恢复，并校验每个插件位于锁定的提交
--   2. treesitter 语法解析器：清单来自 LazyVim 的 ensure_installed（lua/plugins/bootstrap.lua 转交），由锁定的 nvim-treesitter 决定版本
--   3. Mason 工具：lua/config/mason-tools.lua 中的名字与版本
--   4. blink.cmp 模糊匹配库：下载与锁定 tag 对应的预编译文件
-- 每一步只安装缺少或版本不符的部分，因此可以重复执行。

local TIMEOUT = 15 * 60 * 1000

-- GitHub 加速代理由 scripts/bootstrap.sh 处理（D-031）：git 经 GIT_CONFIG_*（url.<GH_PROXY>.insteadOf），
-- curl 下载（treesitter 语法解析器源码、Mason、blink.cmp）经 PATH 中的 curl 包装脚本改写地址；这里只用于输出
local GH_PROXY = vim.env.GH_PROXY or ""

-- 并发上限：编译语法解析器（cc1）与 npm 安装都很占内存，小内存机器上并发过高会把内存耗尽（P-042）。
-- 按每个任务约 1.5GB 估算：min(CPU 核数, 总内存 GB / 1.5)，至少 1；可用 NVIM_BOOTSTRAP_JOBS 覆盖
local JOBS = tonumber(vim.env.NVIM_BOOTSTRAP_JOBS or "")
if not JOBS then
  local uv = vim.uv or vim.loop
  local mem_gb = uv.get_total_memory() / 1024 / 1024 / 1024
  JOBS = math.max(1, math.min(uv.available_parallelism(), math.floor(mem_gb / 1.5)))
end

local function say(msg)
  io.stdout:write("bootstrap.lua: " .. msg .. "\n")
end

local failed = {}
local function fail(msg)
  failed[#failed + 1] = msg
  io.stderr:write("bootstrap.lua: ✗ " .. msg .. "\n")
end

-- 等待异步回调完成；超时视为失败
local function wait_for(desc, start)
  local done, result = false, nil
  start(function(...)
    result = { ... }
    done = true
  end)
  if not vim.wait(TIMEOUT, function()
    return done
  end, 200) then
    fail(desc .. "：超时")
    return nil
  end
  return result
end

-- ---------------------------------------------------------------------------
-- 1. 插件
-- ---------------------------------------------------------------------------
local function step_plugins()
  say("插件：按 lazy-lock.json 恢复")
  require("lazy").restore({ wait = true, show = false })

  local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
  local lock = vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
  local root = vim.fn.stdpath("data") .. "/lazy"
  local n = 0
  for name, entry in pairs(lock) do
    local head = vim.trim(vim.fn.system({ "git", "-C", root .. "/" .. name, "rev-parse", "HEAD" }))
    if vim.v.shell_error ~= 0 then
      fail("插件未安装：" .. name)
    elseif head ~= entry.commit then
      fail(("插件 %s 位于 %s，锁定的是 %s"):format(name, head:sub(1, 7), entry.commit:sub(1, 7)))
    else
      n = n + 1
    end
  end
  say(("插件：%d 个位于锁定的提交"):format(n))
end

-- ---------------------------------------------------------------------------
-- 2. treesitter 语法解析器
-- ---------------------------------------------------------------------------
local function step_treesitter()
  -- 计算 nvim-treesitter 的 opts：lua/plugins/bootstrap.lua 会把 ensure_installed 存入 vim.g.bootstrap_ts_langs
  -- tree-sitter CLI 无法运行时（官方 Linux 版需要 glibc ≥ 2.39，Debian 12 / Ubuntu 22.04 不满足，P-043）跳过：
  -- 这是环境限制而不是网络问题，重试也无济于事；没有语法解析器时 nvim 仍可使用（回退为正则高亮）
  local ts_out = vim.fn.system({ "tree-sitter", "--version" })
  if vim.v.shell_error ~= 0 then
    io.stderr:write("bootstrap.lua: WARNING: tree-sitter CLI 无法运行，跳过语法解析器：" .. vim.trim(ts_out):sub(1, 160) .. "\n")
    return
  end
  LazyVim.opts("nvim-treesitter")
  local langs = vim.g.bootstrap_ts_langs or {}
  if #langs == 0 then
    return fail("treesitter：没有拿到语法解析器清单（lua/plugins/bootstrap.lua 未生效？）")
  end
  require("lazy").load({ plugins = { "nvim-treesitter" } })
  local ts = require("nvim-treesitter")

  local installed = {}
  for _, l in ipairs(ts.get_installed()) do
    installed[l] = true
  end
  local missing = vim.tbl_filter(function(l)
    return not installed[l]
  end, langs)
  say(("treesitter：清单 %d 个，需要安装 %d 个"):format(#langs, #missing))
  if #missing > 0 then
    ts.install(missing, { summary = true, max_jobs = JOBS }):wait(TIMEOUT)
  end

  installed = {}
  for _, l in ipairs(ts.get_installed()) do
    installed[l] = true
  end
  for _, l in ipairs(langs) do
    if not installed[l] then
      fail("treesitter 语法解析器未安装：" .. l)
    end
  end
end

-- ---------------------------------------------------------------------------
-- 3. Mason 工具
-- ---------------------------------------------------------------------------
local function step_mason()
  require("lazy").load({ plugins = { "mason.nvim" } })
  require("mason.settings").current.max_concurrent_installers = JOBS
  local registry = require("mason-registry")
  if not wait_for("Mason：刷新软件源", function(cb)
    registry.refresh(cb)
  end) then
    return
  end

  local tools = require("config.mason-tools")
  local pending = 0
  for name, version in pairs(tools) do
    local ok, pkg = pcall(registry.get_package, name)
    if not ok then
      fail("Mason 中找不到工具：" .. name)
    elseif pkg:get_installed_version() ~= version and not pkg:is_installing() then
      say(("Mason：安装 %s@%s"):format(name, version))
      pending = pending + 1
      pkg:install({ version = version }, function(success, err)
        pending = pending - 1
        if not success then
          fail(("Mason 安装 %s@%s 失败：%s"):format(name, version, tostring(err)))
        end
      end)
    end
  end
  if not vim.wait(TIMEOUT, function()
    return pending == 0
  end, 500) then
    fail("Mason：安装超时")
  end

  for name, version in pairs(tools) do
    local ok, pkg = pcall(registry.get_package, name)
    if ok and pkg:get_installed_version() ~= version then
      fail(("Mason 工具 %s 的版本为 %s，清单要求 %s"):format(name, tostring(pkg:get_installed_version()), version))
    end
  end
  say("Mason：已校验 " .. vim.tbl_count(tools) .. " 个工具")
end

-- ---------------------------------------------------------------------------
-- 4. blink.cmp 模糊匹配库
-- ---------------------------------------------------------------------------
local function step_blink()
  require("lazy").load({ plugins = { "blink.cmp" } })
  local download = require("blink.cmp.fuzzy.download")
  local res = wait_for("blink.cmp：下载模糊匹配库", function(cb)
    download.ensure_downloaded(cb)
  end)
  if not res then
    return
  end
  if res[1] then
    return fail("blink.cmp 模糊匹配库下载失败：" .. tostring(res[1]))
  end
  -- lazy.load 时 blink.cmp 自己的 setup 也会在后台下载同一个文件：等它写完再加载（dev 主机首次运行时遇到）
  if not vim.wait(30000, function()
    return (pcall(require, "blink.cmp.fuzzy.rust"))
  end, 500) then
    return fail("blink.cmp 模糊匹配库无法加载")
  end
  say("blink.cmp：模糊匹配库可用")
end

say("GitHub 加速代理：" .. (GH_PROXY ~= "" and GH_PROXY or "<直连>") .. "；并发上限：" .. JOBS)
for _, step in ipairs({ step_plugins, step_treesitter, step_mason, step_blink }) do
  local ok, err = pcall(step)
  if not ok then
    fail(tostring(err))
  end
end

if #failed > 0 then
  io.stderr:write(("bootstrap.lua: 有 %d 项未完成\n"):format(#failed))
  vim.cmd("cquit 1")
else
  say("全部完成")
  vim.cmd("qall!")
end
