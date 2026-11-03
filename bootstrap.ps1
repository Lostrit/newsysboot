# bootstrap.ps1 — Windows 入口（⚠️ 未在真机测试，docs/progress.md）
#
# 用法（PowerShell；部署 mihomo 服务需要「以管理员身份运行」）：
#   irm https://gh-proxy.com/https://raw.githubusercontent.com/Lostrit/newsysboot/main/bootstrap.ps1 | iex
#   或：powershell -ExecutionPolicy Bypass -File bootstrap.ps1 [-Source github|cnb] [-Dir <检出目录>] [-NoMihomo]
#
# 步骤：
#   - winget 安装 Git 与 mise
#   - GitHub 加速代理测速（同 lib/mirrors.sh：取前 1MiB，校验 sha256）
#   - 检出仓库；安装仓库的工具（fnox、age）
#   - mihomo 系统服务（D-029，需要管理员）：官方二进制 + WinSW（锁定版本、校验 sha256），开机即启动（不延迟）、TUN 模式；
#     配置为预渲染的 files/mihomo/windows-desktop.yaml，节点由 fnox 用 age 私钥解密后填入
#   - `mise bootstrap --only dotfiles,tools`（mise 的 [bootstrap.files] 在 Windows 上不可用；不安装 Docker，D-005）
#
# 无人值守：环境变量 BOOTSTRAP_SOURCE、FNOX_AGE_KEY（age 私钥）、BOOTSTRAP_NO_MIHOMO=1。
param(
  [ValidateSet('github', 'cnb', '')] [string] $Source = $env:BOOTSTRAP_SOURCE,
  [string] $Dir = $(if ($env:BOOTSTRAP_DIR) { $env:BOOTSTRAP_DIR } else { Join-Path $HOME '.local\share\bootstrap' }),
  [switch] $NoMihomo = ($env:BOOTSTRAP_NO_MIHOMO -eq '1')
)
$ErrorActionPreference = 'Stop'

$RepoGithub = if ($env:BOOTSTRAP_REPO_GITHUB) { $env:BOOTSTRAP_REPO_GITHUB } else { 'https://github.com/Lostrit/newsysboot.git' }
$RepoCnb = if ($env:BOOTSTRAP_REPO_CNB) { $env:BOOTSTRAP_REPO_CNB } else { 'https://cnb.cool/xfengjing/lostrit/NewSysBoot.git' }
$GhProxies = @('', 'https://gh-proxy.com/', 'https://ghfast.top/', 'https://gh.qninq.cn/', 'https://github.cnxiaobai.com/', 'https://tvv.tw/')
$ProbeUrl = 'https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-linux-amd64.tar.gz'
$ProbeSha256 = '75c2d0d2265769452a72f14e9b956b6cc3968d0abd5a19904cb79a9267a117b1'

# mihomo 与 WinSW：锁定版本 + sha256（升级时同时修改版本与校验值，D-029）
# mihomo 的校验值来自 GitHub Release 记录的 digest；WinSW v2.12.0 发布时还没有 digest，经两个加速代理下载核对（2026-11-03）
$MihomoVersion = '1.19.33'
$MihomoAsset = "mihomo-windows-amd64-compatible-v$MihomoVersion.zip"
$MihomoSha256 = '7aaf636a4f2172dcd8ec34ac4f52797b059195e5afd6409508c963e545f8864d'
$WinswVersion = '2.12.0'
$WinswSha256 = '05b82d46ad331cc16bdc00de5c6332c1ef818df8ceefcd49c726553209b3a0da'
$MihomoBin = Join-Path $env:ProgramFiles 'mihomo'
$MihomoData = Join-Path $env:ProgramData 'mihomo'

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

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 下载并校验 sha256（经第三方加速代理下载的文件必须校验）
function Get-VerifiedFile($url, $sha256, $out) {
  Say "下载 $url"
  Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing -TimeoutSec 600
  $got = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $sha256) { Remove-Item $out -Force; throw "sha256 校验失败：$url（$got）" }
}

function Get-FileSha256($path) {
  if (Test-Path $path) { (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() } else { '' }
}

# ---------------------------------------------------------------------------
# mihomo 系统服务（D-029）
#   程序：$env:ProgramFiles\mihomo（mihomo.exe、WinSW 改名的 mihomo-service.exe 与同名 .xml）
#   配置：$env:ProgramData\mihomo\config（只允许 SYSTEM 与 Administrators 访问：包含节点）
#   启动：普通「自动」启动（不用「延迟启动」：它会在开机后约 2 分钟才启动，登录后的应用连不上网）
# ---------------------------------------------------------------------------
function Install-MihomoService($gh, $repoDir) {
  if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    Write-Warning "mihomo 服务目前只支持 x64（当前为 $env:PROCESSOR_ARCHITECTURE），跳过"
    return
  }
  $exe = Join-Path $MihomoBin 'mihomo.exe'
  $svcExe = Join-Path $MihomoBin 'mihomo-service.exe'
  $svcXml = Join-Path $MihomoBin 'mihomo-service.xml'
  $confDir = Join-Path $MihomoData 'config'
  $conf = Join-Path $confDir 'config.yaml'
  $svc = Get-Service -Name mihomo -ErrorAction SilentlyContinue

  New-Item -ItemType Directory -Force -Path $MihomoBin, $confDir, (Join-Path $MihomoData 'logs') | Out-Null
  # 配置目录只允许 SYSTEM（S-1-5-18）与 Administrators（S-1-5-32-544）访问；用 SID 避免系统语言不同导致的组名差异
  icacls $MihomoData /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null

  # 1. 程序：版本或校验值不符时才下载（替换前先停止服务，否则文件被占用）
  $needMihomo = -not ((Test-Path $exe) -and ((& $exe -v 2>$null | Out-String) -match "v$MihomoVersion "))
  $needWinsw = (Get-FileSha256 $svcExe) -ne $WinswSha256
  if (($needMihomo -or $needWinsw) -and $svc -and $svc.Status -ne 'Stopped') {
    Say '停止 mihomo 服务以替换程序'
    Stop-Service -Name mihomo -Force
  }
  $tmp = Join-Path $env:TEMP "bootstrap-mihomo-$PID"
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    if ($needMihomo) {
      $zip = Join-Path $tmp $MihomoAsset
      Get-VerifiedFile "${gh}https://github.com/MetaCubeX/mihomo/releases/download/v$MihomoVersion/$MihomoAsset" $MihomoSha256 $zip
      Expand-Archive -Path $zip -DestinationPath $tmp -Force
      Copy-Item (Join-Path $tmp 'mihomo-windows-amd64-compatible.exe') $exe -Force
    }
    if ($needWinsw) {
      Get-VerifiedFile "${gh}https://github.com/winsw/winsw/releases/download/v$WinswVersion/WinSW-x64.exe" $WinswSha256 (Join-Path $tmp 'WinSW-x64.exe')
      Copy-Item (Join-Path $tmp 'WinSW-x64.exe') $svcExe -Force
    }
  } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

  # 2. 配置：预渲染的 desktop 配置 + fnox 解密的节点（私钥只放在本进程的环境变量中，用完即删）
  $key = $env:FNOX_AGE_KEY
  if (-not $key) {
    $sec = Read-Host '请输入 age 私钥（AGE-SECRET-KEY-…，用于解密 mihomo 节点）' -AsSecureString
    $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  }
  $env:FNOX_AGE_KEY = $key
  Push-Location $repoDir
  try {
    $nodes = (mise exec fnox -- fnox get MIHOMO_PROXIES) -join "`n"
  } finally {
    Pop-Location
    Remove-Item Env:FNOX_AGE_KEY -ErrorAction SilentlyContinue
    $key = $null
  }
  if ($LASTEXITCODE -ne 0 -or $nodes -notmatch '(?m)^proxies:') { throw 'fnox 解密 mihomo 节点失败（私钥是否正确？）' }
  $tpl = [IO.File]::ReadAllText((Join-Path $repoDir 'files\mihomo\windows-desktop.yaml'))
  if (-not $tpl.Contains('# @@MIHOMO_PROXIES@@')) { throw 'windows-desktop.yaml 缺少节点占位行' }
  $utf8 = New-Object Text.UTF8Encoding $false
  [IO.File]::WriteAllText($conf, $tpl.Replace('# @@MIHOMO_PROXIES@@', $nodes), $utf8)
  $nodes = $null
  & $exe -t -d $confDir -f $conf | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "mihomo 配置校验失败：$conf" }

  # 3. WinSW 服务定义
  $xml = @"
<!-- 由 bootstrap.ps1 生成（D-029），勿直接编辑 -->
<service>
  <id>mihomo</id>
  <name>Mihomo</name>
  <description>mihomo 代理（bootstrap 部署，TUN 模式）</description>
  <executable>%BASE%\mihomo.exe</executable>
  <arguments>-d "$confDir"</arguments>
  <workingdirectory>$confDir</workingdirectory>
  <!-- 普通自动启动，不延迟：开机阶段（登录前）就启动；依赖网络服务保证启动顺序，网卡变化由 mihomo 的 auto-detect-interface 处理 -->
  <startmode>Automatic</startmode>
  <depend>Tcpip</depend>
  <depend>Dnscache</depend>
  <onfailure action="restart" delay="5 sec"/>
  <onfailure action="restart" delay="15 sec"/>
  <resetfailure>1 hour</resetfailure>
  <stoptimeout>15 sec</stoptimeout>
  <logpath>$(Join-Path $MihomoData 'logs')</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>5</keepFiles>
  </log>
</service>
"@
  [IO.File]::WriteAllText($svcXml, $xml, $utf8)

  # 4. 安装 / 启动；配置、服务定义或程序有变化时重启
  $sum = (@($conf, $svcXml, $exe, $svcExe) | ForEach-Object { Get-FileSha256 $_ }) -join ','
  $stateFile = Join-Path $MihomoData '.bootstrap.sha256'
  $old = if (Test-Path $stateFile) { (Get-Content $stateFile -Raw).Trim() } else { '' }
  if (-not $svc) {
    Say '注册并启动 mihomo 服务'
    & $svcExe install | Out-Null
    & $svcExe start | Out-Null
  } elseif ($old -ne $sum) {
    Say '配置有变化，重启 mihomo 服务'
    & $svcExe restart | Out-Null
  } elseif ((Get-Service -Name mihomo).Status -ne 'Running') {
    & $svcExe start | Out-Null
  }
  Set-Content -Path $stateFile -Value $sum

  # 5. 确认代理可用（经 mixed-port 访问 GitHub，最多 30 秒）
  for ($i = 0; $i -lt 15; $i++) {
    try {
      Invoke-WebRequest -Uri 'https://github.com' -Proxy 'http://127.0.0.1:7890' -UseBasicParsing -TimeoutSec 5 | Out-Null
      Say 'mihomo 已生效（TUN 模式，开机自动启动）'
      return
    } catch { Start-Sleep -Seconds 2 }
  }
  Write-Warning "mihomo 服务已启动，但暂时无法经代理访问 GitHub；日志：$(Join-Path $MihomoData 'logs')"
}

# ---------------------------------------------------------------------------
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
  # 仓库的工具（fnox、age）：解密 mihomo 节点需要 fnox
  mise install -q

  if ($NoMihomo) {
    Say '跳过 mihomo（-NoMihomo）'
  } elseif (-not (Test-Admin)) {
    Write-Warning '部署 mihomo 服务需要管理员权限：请在「以管理员身份运行」的 PowerShell 中重新执行（或加 -NoMihomo 跳过）'
  } else {
    Install-MihomoService $gh $Dir
  }

  Say 'mise bootstrap --yes --only dotfiles,tools'
  mise bootstrap --yes --only dotfiles,tools
} finally { Pop-Location }
Say '完成。重新打开终端使环境变量生效。'
