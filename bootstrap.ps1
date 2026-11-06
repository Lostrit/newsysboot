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
  [switch] $NoMihomo = ($env:BOOTSTRAP_NO_MIHOMO -eq '1'),
  [switch] $Reprobe = ($env:BOOTSTRAP_REPROBE -eq '1')
)
$ErrorActionPreference = 'Stop'

$RepoGithub = if ($env:BOOTSTRAP_REPO_GITHUB) { $env:BOOTSTRAP_REPO_GITHUB } else { 'https://github.com/Lostrit/newsysboot.git' }
$RepoCnb = if ($env:BOOTSTRAP_REPO_CNB) { $env:BOOTSTRAP_REPO_CNB } else { 'https://cnb.cool/xfengjing/lostrit/NewSysBoot.git' }
# 内置的 GitHub 加速代理（scripts/update-gh-proxies.sh 维护，D-031）；都不可用时直连
$GhProxies = @('https://github.cnxiaobai.com/', 'https://git.yylx.win/', 'https://gh.padao.fun/', 'https://ghproxy.sakuramoe.dev/')  # @gh-proxies
# Windows 自带 curl.exe / tar.exe（PowerShell 5.1 中 curl 是 Invoke-WebRequest 的别名）；在 Linux 的 pwsh 中测试时用 curl
$OnWindows = ($PSVersionTable.PSEdition -ne 'Core') -or $IsWindows
$Curl = if ($OnWindows) { 'curl.exe' } else { 'curl' }
$NullDev = if ($OnWindows) { 'NUL' } else { '/dev/null' }
$StateDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'bootstrap' } else { Join-Path $HOME '.local/state/bootstrap' }

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

# ---------------------------------------------------------------------------
# GitHub 加速代理（D-031，与 lib/mirrors.sh 相同的规则）：
#   候选来自仓库的 lib/gh-proxies.txt；测试目标（URL、sha256）从 lib/mirrors.sh 读取，两边共用一份定义。
#   全部候选并行测延时，最低的 5 个做 release / raw / archive / clone 真实测试，全部通过者中取 release 最快的；
#   结果缓存 7 天（-Reprobe 重新选择）；都不可用时直连
# ---------------------------------------------------------------------------
function Get-ShVar($repoDir, $name) {
  $m = Select-String -Path (Join-Path $repoDir 'lib\mirrors.sh') -Pattern "^$name=`"(.*)`"$" | Select-Object -First 1
  if (-not $m) { throw "lib/mirrors.sh 中没有 $name" }
  $m.Matches[0].Groups[1].Value
}

# 首字节时间（毫秒），并行测全部候选；返回按延时排序的前缀
function Get-GhByLatency($candidates) {
  $dir = Join-Path ([IO.Path]::GetTempPath()) "bootstrap-ghlat-$PID"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $procs = @()
  $i = 0
  foreach ($c in $candidates) {
    $i++
    $out = Join-Path $dir "$i.txt"
    Set-Content -Path (Join-Path $dir "$i.url") -Value $c
    $cargs = "-s --noproxy * --connect-timeout 3 -m 5 -o $NullDev -w `"%{http_code} %{time_starttransfer}`" $c"
    $procs += Start-Process -FilePath $Curl -ArgumentList $cargs -NoNewWindow -PassThru -RedirectStandardOutput $out
  }
  $procs | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
  $res = @()
  for ($j = 1; $j -le $i; $j++) {
    $t = (Get-Content (Join-Path $dir "$j.txt") -ErrorAction SilentlyContinue | Out-String).Trim()
    if ($t -match '^(\d{3}) ([\d.]+)$' -and $Matches[1] -ne '000') {
      $res += [pscustomobject]@{ Ms = [int]([double]$Matches[2] * 1000); Prefix = (Get-Content (Join-Path $dir "$j.url")).Trim() }
    }
  }
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
  $res | Sort-Object Ms | ForEach-Object { $_.Prefix }
}

# release 前 1MiB：校验 sha256，返回速度（B/s）；失败返回 0
function Get-GhReleaseSpeed($url, $sha) {
  $tmp = [IO.Path]::GetTempFileName()
  try {
    $o = & $Curl -sL --noproxy '*' --connect-timeout 3 -m 10 -r 0-1048575 -o $tmp -w '%{http_code} %{speed_download}' $url
    if ($o -notmatch '^(200|206) ([\d.]+)$') { return 0 }
    $speed = [double]$Matches[2]
    if ((Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower() -ne $sha) { return 0 }
    return $speed
  } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

# 真实测试：全部通过时返回 release 下载速度（两次取较慢），否则返回 0
function Test-GhProxy($p, $t) {
  $s1 = Get-GhReleaseSpeed "$p$($t.ProbeUrl)" $t.ProbeSha
  $s2 = if ($s1 -gt 0) { Get-GhReleaseSpeed "$p$($t.ProbeUrl)" $t.ProbeSha } else { 0 }
  $speed = [Math]::Min($s1, $s2)
  if ($speed -le 0) { return 0 }
  $tmp = Join-Path ([IO.Path]::GetTempPath()) "bootstrap-ghtest-$PID"
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    # raw
    $raw = Join-Path $tmp 'raw'
    & $Curl -fsSL --noproxy '*' --connect-timeout 5 -m 20 -o $raw "$p$($t.RawUrl)" | Out-Null
    if (-not (Test-Path $raw) -or (Get-FileHash $raw -Algorithm SHA256).Hash.ToLower() -ne $t.RawSha) { return 0 }
    # archive
    $tgz = Join-Path $tmp 'a.tgz'
    & $Curl -fsSL --noproxy '*' --connect-timeout 5 -m 30 -o $tgz "$p$($t.ArchiveUrl)" | Out-Null
    if (-not (Test-Path $tgz)) { return 0 }
    $list = & tar -tzf $tgz 2>$null
    if (-not ($list -contains $t.ArchiveFile)) { return 0 }
    # clone（不经环境中的代理；最多 60 秒）
    $saved = @{}
    foreach ($v in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy') {
      $saved[$v] = [Environment]::GetEnvironmentVariable($v, 'Process')
      [Environment]::SetEnvironmentVariable($v, $null, 'Process')
    }
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
      $dest = Join-Path $tmp 'clone'
      $gargs = "-c http.lowSpeedLimit=1024 -c http.lowSpeedTime=15 clone -q --depth 1 $p$($t.CloneUrl) `"$dest`""
      $gp = Start-Process -FilePath git -ArgumentList $gargs -NoNewWindow -PassThru `
        -RedirectStandardOutput (Join-Path $tmp 'git.out') -RedirectStandardError (Join-Path $tmp 'git.err')
      if (-not $gp.WaitForExit(60000)) { $gp.Kill(); return 0 }
      if ($gp.ExitCode -ne 0 -or -not (Test-Path (Join-Path $dest $t.CloneFile))) { return 0 }
    } finally {
      foreach ($v in $saved.Keys) { [Environment]::SetEnvironmentVariable($v, $saved[$v], 'Process') }
    }
    return $speed
  } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# 返回 @(主代理, 备用代理)（D-033）；空字符串表示没有（直连）
function Select-GhProxy($repoDir) {
  if ($null -ne $env:GH_PROXY) { return @($env:GH_PROXY, "$env:GH_PROXY_BACKUP") }
  $cache = Join-Path $StateDir 'gh-proxy.txt'
  if (-not $Reprobe -and (Test-Path $cache) -and ((Get-Item $cache).LastWriteTime -gt (Get-Date).AddDays(-7))) {
    Say "使用缓存的 GitHub 加速代理：$cache（-Reprobe 重新选择）"
    $l = @(Get-Content $cache | ForEach-Object { $_.Trim() }) + @('', '')
    return @($l[0], $l[1])
  }
  Say '选择 GitHub 加速代理（测延时与 release / raw / archive / clone）…'
  $t = @{
    ProbeUrl = Get-ShVar $repoDir 'BS_GH_PROBE_URL'; ProbeSha = Get-ShVar $repoDir 'BS_GH_PROBE_SHA256'
    RawUrl = Get-ShVar $repoDir 'BS_GH_RAW_URL'; RawSha = Get-ShVar $repoDir 'BS_GH_RAW_SHA256'
    ArchiveUrl = Get-ShVar $repoDir 'BS_GH_ARCHIVE_URL'; ArchiveFile = Get-ShVar $repoDir 'BS_GH_ARCHIVE_FILE'
    CloneUrl = Get-ShVar $repoDir 'BS_GH_CLONE_URL'; CloneFile = Get-ShVar $repoDir 'BS_GH_CLONE_FILE'
  }
  $list = Join-Path $repoDir 'lib\gh-proxies.txt'
  $candidates = if (Test-Path $list) {
    Get-Content $list | Where-Object { $_ -match '^(https:[^\s#]*)' } | ForEach-Object { ($_ -split '\s')[0] }
  } else { $GhProxies }
  # 全部能力测试通过者按 release 下载速度排序：最快的为主代理，第二快的为备用代理
  $ok = @()
  foreach ($c in (Get-GhByLatency $candidates | Select-Object -First 5)) {
    $sp = Test-GhProxy $c $t
    if ($sp -gt 0) { $ok += [pscustomobject]@{ Proxy = $c; Speed = $sp } }
  }
  $ranked = @($ok | Sort-Object Speed -Descending | ForEach-Object { $_.Proxy }) + @('', '')
  $best = $ranked[0]; $backup = $ranked[1]
  if (-not $best) { Write-Warning '没有完整可用的 GitHub 加速代理，GitHub 下载将直连（国内可能很慢或失败）' }
  elseif (-not $backup) { Write-Warning "只有一个完整可用的 GitHub 加速代理（$best），没有备用代理" }
  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
  Set-Content -Path $cache -Value @($best, $backup)
  return @($best, $backup)
}

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 下载并校验 sha256（经第三方加速代理下载的文件必须校验）；依次经主代理、备用代理（D-033），
# 失败回退直连（D-031），仍失败则报错。$ghs 为 @(主代理, 备用代理)
function Get-VerifiedFile($ghs, $url, $sha256, $out) {
  $urls = @($ghs | Where-Object { $_ } | ForEach-Object { "$_$url" }) + @($url)
  foreach ($u in $urls | Select-Object -Unique) {
    Say "下载 $u"
    try {
      Invoke-WebRequest -Uri $u -OutFile $out -UseBasicParsing -TimeoutSec 600
      $got = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower()
      if ($got -eq $sha256) { return }
      Write-Warning "sha256 校验失败：$u（$got）"
    } catch { Write-Warning "下载失败：$u（$($_.Exception.Message)）" }
    Remove-Item $out -Force -ErrorAction SilentlyContinue
    if ($u -ne $url) { Write-Warning '经 GitHub 加速代理下载失败，改用下一个（备用代理或直连）' }
  }
  throw "下载失败：$url"
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
function Install-MihomoService($ghs, $repoDir) {
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
      Get-VerifiedFile $ghs "https://github.com/MetaCubeX/mihomo/releases/download/v$MihomoVersion/$MihomoAsset" $MihomoSha256 $zip
      Expand-Archive -Path $zip -DestinationPath $tmp -Force
      Copy-Item (Join-Path $tmp 'mihomo-windows-amd64-compatible.exe') $exe -Force
    }
    if ($needWinsw) {
      Get-VerifiedFile $ghs "https://github.com/winsw/winsw/releases/download/v$WinswVersion/WinSW-x64.exe" $WinswSha256 (Join-Path $tmp 'WinSW-x64.exe')
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

if (-not $Source) {
  $c = Read-Host '从哪里拉取本仓库？ 1) GitHub（经加速代理）  2) CNB  [1]'
  $Source = if ($c -eq '2' -or $c -eq 'cnb') { 'cnb' } else { 'github' }
}

if (Test-Path (Join-Path $Dir '.git')) {
  Say "更新仓库 $Dir"
  git -C $Dir pull -q --ff-only
} else {
  New-Item -ItemType Directory -Force -Path (Split-Path $Dir) | Out-Null
  if ($Source -eq 'cnb') {
    Say "检出 $RepoCnb → $Dir"
    git clone -q $RepoCnb $Dir
  } else {
    # 此时还没有选择结果：依次尝试内置的加速代理，最后直连（与 bootstrap.sh 的管道模式一致）
    $tries = @()
    if ($env:GH_PROXY) { $tries += $env:GH_PROXY }
    $tries += $GhProxies
    $tries += ''
    foreach ($p in ($tries | Select-Object -Unique)) {
      Say "检出 $p$RepoGithub → $Dir"
      git clone -q --depth 1 "$p$RepoGithub" $Dir
      if ($LASTEXITCODE -eq 0) { break }
      Remove-Item $Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path (Join-Path $Dir '.git'))) { throw '无法从 GitHub 拉取仓库，可改用 -Source cnb' }
    git -C $Dir remote set-url origin $RepoGithub
  }
}

$ghs = Select-GhProxy $Dir
$gh = $ghs[0]
Say "GH_PROXY: $(if ($gh) { $gh } else { '<直连>' })  备用：$(if ($ghs[1]) { $ghs[1] } else { '<无>' })"

# mise 的 GitHub 下载经加速代理（与 Linux 的 env.sh 一致），并持久化到用户环境变量；$p 为空时取消
function Set-MiseGhProxy($p) {
  $rep = if ($p) { @{ 'https://github.com/' = "${p}https://github.com/"; 'https://raw.githubusercontent.com/' = "${p}https://raw.githubusercontent.com/" } | ConvertTo-Json -Compress } else { $null }
  $env:MISE_URL_REPLACEMENTS = $rep
  [Environment]::SetEnvironmentVariable('MISE_URL_REPLACEMENTS', $rep, 'User')
}
# mise 失败时依次改用备用代理、直连重试（D-031、D-033）；成功后之后的步骤沿用该前缀
function Invoke-MiseRetry([scriptblock] $run) {
  & $run
  if ($LASTEXITCODE -eq 0) { return }
  foreach ($p in @($ghs[1], '') | Select-Object -Unique) {
    if ($p -eq $script:gh) { continue }
    Write-Warning "mise 经 $(if ($script:gh) { "GitHub 加速代理 $($script:gh)" } else { '直连' }) 执行失败，改为$(if ($p) { "备用加速代理 $p" } else { '直连 GitHub' })重试"
    $script:gh = $p
    Set-MiseGhProxy $p
    & $run
    if ($LASTEXITCODE -eq 0) { return }
  }
  throw 'mise 执行失败'
}
if ($gh) { Set-MiseGhProxy $gh }
$env:MISE_NODE_MIRROR_URL = 'https://mirrors.cloud.tencent.com/nodejs-release/'
[Environment]::SetEnvironmentVariable('MISE_NODE_MIRROR_URL', $env:MISE_NODE_MIRROR_URL, 'User')
[Environment]::SetEnvironmentVariable('NPM_CONFIG_REGISTRY', 'https://mirrors.cloud.tencent.com/npm/', 'User')

Push-Location $Dir
try {
  mise trust -q (Join-Path $Dir 'mise.toml')
  # 仓库的工具（fnox、age）：解密 mihomo 节点需要 fnox
  Invoke-MiseRetry { mise install -q }

  if ($NoMihomo) {
    Say '跳过 mihomo（-NoMihomo）'
  } elseif (-not (Test-Admin)) {
    Write-Warning '部署 mihomo 服务需要管理员权限：请在「以管理员身份运行」的 PowerShell 中重新执行（或加 -NoMihomo 跳过）'
  } else {
    Install-MihomoService $ghs $Dir
  }

  Say 'mise bootstrap --yes --only dotfiles,tools'
  Invoke-MiseRetry { mise bootstrap --yes --only dotfiles,tools }
} finally { Pop-Location }
Say '完成。重新打开终端使环境变量生效。'
