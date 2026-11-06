# ~/.config/powershell/profile.ps1 — PowerShell 7 的交互配置（D-040），尽量接近 zsh 的体验（dotfiles/.config/zsh）
#
# 由 bootstrap.ps1 在 $PROFILE（「文档\PowerShell\Microsoft.PowerShell_profile.ps1」，可能被 OneDrive 重定向）
# 中写入一行加载本文件；本文件随仓库更新。
#
#   zsh                                   PowerShell
#   mise activate zsh                  →  mise activate pwsh（PATH 与 [env]：EDITOR、BAT_CONFIG_PATH、JQ_COLORS 等）
#   zsh-autosuggestions / 语法高亮     →  PSReadLine 的历史预测（行内灰色提示）与内置语法着色（Catppuccin Mocha）
#   fzf-tab / fzf 快捷键               →  PSFzf：Tab 补全用 fzf 选择，Ctrl+T 选文件，Alt+C 进入目录
#   atuin（Ctrl+R、上方向键）          →  atuin init powershell
#   starship                           →  starship init powershell
#   zsh-eza 的 ls / l / ll / la / lt   →  同名函数
#   tools.zsh 生成并缓存的补全         →  同样按工具路径缓存到 $XDG_CACHE_HOME\powershell
if ($PSVersionTable.PSVersion.Major -lt 7) { return }

foreach ($kv in @(
    @('XDG_CONFIG_HOME', '.config'), @('XDG_DATA_HOME', '.local\share'),
    @('XDG_STATE_HOME', '.local\state'), @('XDG_CACHE_HOME', '.cache'))) {
  if (-not [Environment]::GetEnvironmentVariable($kv[0])) { Set-Item "Env:$($kv[0])" (Join-Path $HOME $kv[1]) }
}
$script:PwshCache = Join-Path $env:XDG_CACHE_HOME 'powershell'
New-Item -ItemType Directory -Force -Path $script:PwshCache, (Join-Path $env:XDG_STATE_HOME 'powershell') | Out-Null

# 1. mise —— 必须最先，后面的工具都由它放进 PATH
if (Get-Command mise -ErrorAction SilentlyContinue) {
  (& mise activate pwsh) | Out-String | Invoke-Expression
}

# 生成（或命中缓存）工具的 init / 补全脚本，返回脚本路径：缓存键为工具的真实路径与修改时间，工具升级后自动重新生成
# （同 tools.zsh）。调用方在脚本作用域中点加载（在函数中点加载，定义的函数与键位只在函数内有效）
function Get-ToolScript([string] $Name, [string] $Kind, [scriptblock] $Generate) {
  $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) { return }
  $file = Join-Path $script:PwshCache "$Kind-$Name.ps1"
  $stamp = "$file.stamp"
  $key = "$($cmd.Source)|$((Get-Item $cmd.Source).LastWriteTimeUtc.Ticks)"
  if (-not (Test-Path $file) -or ((Get-Content $stamp -ErrorAction SilentlyContinue) -ne $key)) {
    try {
      $out = (& $Generate) | Out-String
      if ($out.Trim()) {
        Set-Content -Path $file -Value $out -Encoding utf8
        Set-Content -Path $stamp -Value $key
      }
    } catch { return }
  }
  if (Test-Path $file) { $file }
}

# 2. 颜色：LS_COLORS（eza、fd 使用）与 PSReadLine（Catppuccin Mocha）
if (Get-Command vivid -ErrorAction SilentlyContinue) {
  $lsc = Join-Path $script:PwshCache 'ls_colors.txt'
  if (-not (Test-Path $lsc)) { vivid generate catppuccin-mocha | Set-Content -Path $lsc -Encoding utf8 }
  $env:LS_COLORS = (Get-Content $lsc -Raw).Trim()
}

function Get-Rgb([string] $hex) {
  $c = [Convert]::ToInt32($hex.TrimStart('#'), 16)
  "`e[38;2;$(($c -shr 16) -band 255);$(($c -shr 8) -band 255);$($c -band 255)m"
}

if ($Host.Name -eq 'ConsoleHost' -and (Get-Module -ListAvailable PSReadLine)) {
  Import-Module PSReadLine
  Set-PSReadLineOption -EditMode Emacs -BellStyle None `
    -HistorySavePath (Join-Path $env:XDG_STATE_HOME 'powershell\history.txt') -HistoryNoDuplicates `
    -PredictionSource History -PredictionViewStyle InlineView
  Set-PSReadLineOption -Colors @{
    Command = Get-Rgb '#89b4fa'; Parameter = Get-Rgb '#f9e2af'; Operator = Get-Rgb '#89dceb'
    Variable = Get-Rgb '#f5e0dc'; String = Get-Rgb '#a6e3a1'; Number = Get-Rgb '#fab387'
    Type = Get-Rgb '#f9e2af'; Keyword = Get-Rgb '#cba6f7'; Member = Get-Rgb '#94e2d5'
    Comment = Get-Rgb '#6c7086'; Default = Get-Rgb '#cdd6f4'; Error = Get-Rgb '#f38ba8'
    Emphasis = Get-Rgb '#f38ba8'; Selection = "`e[48;2;69;71;90m"; InlinePrediction = Get-Rgb '#6c7086'
    ListPrediction = Get-Rgb '#cba6f7'
  }
  # 与 zsh（bindkey -e）一致的常用键
  Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
  Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow -Function BackwardWord
}

# 3. 补全（tools.zsh 中「comp」的对应）
foreach ($t in @(
    @('mise', 'comp', { mise completion powershell }),
    @('rg', 'comp', { rg --generate complete-powershell }),
    @('fd', 'comp', { fd --gen-completions powershell }),
    @('bat', 'comp', { bat --completion ps1 }),
    @('starship', 'comp', { starship completions powershell }),
    @('atuin', 'comp', { atuin gen-completions --shell powershell }))) {
  $f = Get-ToolScript @t
  if ($f) { . $f }
}

# 4. eza：与 zsh-eza 插件相同的别名与参数
if (Get-Command eza -CommandType Application -ErrorAction SilentlyContinue) {
  Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
  $global:BsEzaParams = @('--git', '--icons', '--group', '--group-directories-first', '--time-style=long-iso', '--color-scale=all')
  function global:ls { $p = $global:BsEzaParams; eza @p @args }
  function global:l { $p = $global:BsEzaParams; eza --git-ignore @p @args }
  function global:ll { $p = $global:BsEzaParams; eza --all --header --long @p @args }
  function global:llm { $p = $global:BsEzaParams; eza --all --header --long --sort=modified @p @args }
  function global:la { $p = $global:BsEzaParams; eza -lbhHigUmuSa @p @args }
  function global:lt { $p = $global:BsEzaParams; eza --tree @p @args }
  function global:tree { $p = $global:BsEzaParams; eza --tree @p @args }
}

# 5. fzf（PSFzf 模块，由 bootstrap.ps1 安装）：Ctrl+R 留给 atuin
if ($Host.Name -eq 'ConsoleHost' -and (Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Module -ListAvailable PSFzf)) {
  Import-Module PSFzf
  Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -EnableAliasFuzzyEdit:$false
  Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
  Set-PSReadLineKeyHandler -Key Alt+c -ScriptBlock { Invoke-FuzzySetLocation; [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
}

# 6. 历史（atuin）与提示符（starship，最后加载）
if ($Host.Name -eq 'ConsoleHost') {
  $f = Get-ToolScript atuin init { atuin init powershell }
  if ($f) { . $f }
}
$f = Get-ToolScript starship init { starship init powershell --print-full-init }
if ($f) { . $f }
Remove-Variable t, f, kv -ErrorAction SilentlyContinue
