# tests/ci/verify-windows.ps1 —— Windows 部署后的检查（GitHub Actions，D-041；也可以在真机上运行）
$ErrorActionPreference = 'Continue'
$fail = 0
function Check($name, [scriptblock] $test) {
  $ok = $false
  try { $ok = [bool](& $test) } catch { $ok = $false }
  if ($ok) { Write-Host "PASS $name" } else {
    Write-Host "FAIL $name"; $script:fail++
    # GitHub Actions 的注解可以匿名读取（作业日志不行）
    if ($env:GITHUB_ACTIONS) { Write-Host "::error::FAIL $name" }
  }
}
# bootstrap.ps1 写入的是用户环境变量，后续进程才能看到：这里读进当前进程
foreach ($n in 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'MISE_DISABLE_TOOLS', 'BOOTSTRAP_ROLE') {
  $v = [Environment]::GetEnvironmentVariable($n, 'User')
  if ($v) { Set-Item "Env:$n" $v }
}
Write-Host "MISE_DISABLE_TOOLS=$env:MISE_DISABLE_TOOLS"

Check 'BOOTSTRAP_ROLE=windows' { $env:BOOTSTRAP_ROLE -eq 'windows' }
Check 'XDG_CONFIG_HOME = ~/.config' { $env:XDG_CONFIG_HOME -eq (Join-Path $HOME '.config') }
Check 'ssh.exe 可用' { Get-Command ssh.exe -ErrorAction SilentlyContinue }
Check 'ssh-agent 自动启动' { (Get-Service ssh-agent).StartType -eq 'Automatic' }
Check 'PowerShell 7' { Get-Command pwsh -ErrorAction SilentlyContinue }

# 启用的工具都能运行；排除的工具 mise 不提供（D-036）
$on = 'eza', 'bat', 'fd', 'rg', 'starship', 'atuin', 'fzf', 'jq', 'micro', 'vivid', 'fnox'
$off = @{ nvim = 'aqua:neovim/neovim'; node = 'node'; bun = 'bun'; lazygit = 'aqua:jesseduffield/lazygit'; delta = 'aqua:dandavison/delta'
  tmux = 'aqua:tmux/tmux-builds'; herdr = 'aqua:herdrdev/herdr'; claude = 'claude'; gh = 'aqua:cli/cli'; age = 'age'; btop = 'aqua:aristocratos/btop'
  cnb = 'npm:@cnbcool/cnb-cli' }
foreach ($t in $on) { Check "工具 $t" { $p = mise which $t 2>$null; $LASTEXITCODE -eq 0 -and $p -and (Test-Path $p) } }
foreach ($t in $off.Keys) { Check "不启用 $t" { ",$env:MISE_DISABLE_TOOLS," -like "*,$($off[$t]),*" -and -not (mise which $t 2>$null) } }
Check 'jq 配色（mise [env]）' { (mise env --json | ConvertFrom-Json).JQ_COLORS -like '38;2;*' }

# dotfiles 与 PowerShell profile（D-040）
Check '~/.config/powershell 链接到仓库' { (Get-Item (Join-Path $HOME '.config/powershell')).LinkType }
Check 'PSFzf 已安装' { Get-Module -ListAvailable PSFzf }
$prof = (pwsh -NoProfile -NonInteractive -Command '$PROFILE.CurrentUserCurrentHost' | Out-String).Trim()
Check "`$PROFILE 加载仓库的 profile（$prof）" { (Get-Content $prof -Raw) -match 'bootstrap（D-040）' }
$out = pwsh -NoLogo -NonInteractive -Command '"eza=" + (Get-Command ls).CommandType; "prompt=" + [bool](Get-Command prompt)' 2>&1 | Out-String
Write-Host $out
if ($env:GITHUB_ACTIONS -and $out -match 'Exception|错误') { Write-Host "::error title=pwsh profile::$(($out -replace '%', '%25') -replace "`r?`n", '%0A')" }
Check 'profile 加载无错误、ls 为 eza 函数' { $out -match 'eza=Function' -and $out -notmatch 'Exception|错误' }

# 字体（D-039）
$fdir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
foreach ($s in 'Regular', 'Italic', 'Bold', 'BoldItalic') {
  Check "字体 $s" { (Test-Path (Join-Path $fdir "MapleMonoNormal-NF-CN-$s.ttf")) -and
    (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts')."MapleMonoNormal-NF-CN-$s (TrueType)" }
}

Write-Host "==> FAIL $fail"
exit $fail
