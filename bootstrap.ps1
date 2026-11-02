# bootstrap.ps1 — Windows 入口（⚠️ 未在真机测试，docs/progress.md）
#
# 用法（PowerShell）：
#   irm https://gh-proxy.com/https://raw.githubusercontent.com/lostrit/newsysboot/main/bootstrap.ps1 | iex
#   或：powershell -ExecutionPolicy Bypass -File bootstrap.ps1 [-Source github|cnb] [-Dir <检出目录>]
#
# 范围（阶段 7 的第一版）：
#   - winget 安装 Git 与 mise
#   - GitHub 加速代理测速（同 lib/mirrors.sh：取前 1MiB，校验 sha256）
#   - 检出仓库，运行 `mise bootstrap --only dotfiles,tools`
#     （mise 的 [bootstrap.files] 在 Windows 上不可用；mihomo 与 Docker 在 Windows 上暂不处理，D-005）
param(
  [ValidateSet('github', 'cnb', '')] [string] $Source = $env:BOOTSTRAP_SOURCE,
  [string] $Dir = $(if ($env:BOOTSTRAP_DIR) { $env:BOOTSTRAP_DIR } else { Join-Path $HOME '.local\share\bootstrap' })
)
$ErrorActionPreference = 'Stop'

$RepoGithub = if ($env:BOOTSTRAP_REPO_GITHUB) { $env:BOOTSTRAP_REPO_GITHUB } else { 'https://github.com/lostrit/newsysboot.git' }
$RepoCnb = if ($env:BOOTSTRAP_REPO_CNB) { $env:BOOTSTRAP_REPO_CNB } else { 'https://cnb.cool/xfengjing/lostrit/NewSysBoot.git' }
$GhProxies = @('', 'https://gh-proxy.com/', 'https://ghfast.top/', 'https://gh.qninq.cn/', 'https://github.cnxiaobai.com/', 'https://tvv.tw/')
$ProbeUrl = 'https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-linux-amd64.tar.gz'
$ProbeSha256 = '75c2d0d2265769452a72f14e9b956b6cc3968d0abd5a19904cb79a9267a117b1'

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

function Install-WingetPackage($id) {
  if (-not (winget list --id $id -e 2>$null | Select-String $id)) {
    Say "winget install $id"
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
  }
}

# GitHub 加速代理测速：前 1MiB + sha256 校验，按速度选择；直连最快时返回空字符串
function Select-GhProxy {
  if ($null -ne $env:GH_PROXY) { return $env:GH_PROXY }
  $best = $null; $bestSpeed = 0
  foreach ($p in $GhProxies) {
    $tmp = New-TemporaryFile
    try {
      $sw = [Diagnostics.Stopwatch]::StartNew()
      Invoke-WebRequest -Uri "$p$ProbeUrl" -Headers @{ Range = 'bytes=0-1048575' } -OutFile $tmp -TimeoutSec 10 -UseBasicParsing
      $sw.Stop()
      if ((Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower() -ne $ProbeSha256) { continue }
      $speed = 1048576 / [Math]::Max($sw.Elapsed.TotalSeconds, 0.001)
      if ($speed -gt $bestSpeed) { $best = $p; $bestSpeed = $speed }
    } catch { } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
  }
  if ($null -eq $best) { Write-Warning 'GitHub 直连与所有加速代理都不可用'; return '' }
  return $best
}

Install-WingetPackage 'Git.Git'
Install-WingetPackage 'jdx.mise'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

$gh = Select-GhProxy
Say "GH_PROXY: $(if ($gh) { $gh } else { '<直连>' })"

if (-not $Source) {
  $c = Read-Host '从哪里拉取本仓库？ 1) GitHub（经加速代理）  2) CNB  [1]'
  $Source = if ($c -eq '2' -or $c -eq 'cnb') { 'cnb' } else { 'github' }
}
$repo = if ($Source -eq 'cnb') { $RepoCnb } else { "$gh$RepoGithub" }

if (Test-Path (Join-Path $Dir '.git')) {
  Say "更新仓库 $Dir"
  git -C $Dir pull -q --ff-only
} else {
  Say "检出 $repo → $Dir"
  New-Item -ItemType Directory -Force -Path (Split-Path $Dir) | Out-Null
  git clone -q $repo $Dir
  if ($Source -eq 'github') { git -C $Dir remote set-url origin $RepoGithub }
}

# mise 的 GitHub 下载经加速代理（与 Linux 的 env.sh 一致），并持久化到用户环境变量
if ($gh) {
  $rep = (@{ 'https://github.com/' = "${gh}https://github.com/"; 'https://raw.githubusercontent.com/' = "${gh}https://raw.githubusercontent.com/" } | ConvertTo-Json -Compress)
  $env:MISE_URL_REPLACEMENTS = $rep
  [Environment]::SetEnvironmentVariable('MISE_URL_REPLACEMENTS', $rep, 'User')
}
$env:MISE_NODE_MIRROR_URL = 'https://mirrors.cloud.tencent.com/nodejs-release/'
[Environment]::SetEnvironmentVariable('MISE_NODE_MIRROR_URL', $env:MISE_NODE_MIRROR_URL, 'User')
[Environment]::SetEnvironmentVariable('NPM_CONFIG_REGISTRY', 'https://mirrors.cloud.tencent.com/npm/', 'User')

Push-Location $Dir
try {
  mise trust -q (Join-Path $Dir 'mise.toml')
  Say 'mise bootstrap --yes --only dotfiles,tools'
  mise bootstrap --yes --only dotfiles,tools
} finally { Pop-Location }
Say '完成。重新打开终端使环境变量生效。'
