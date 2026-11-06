# Windows 真机验证清单（待执行）

> 状态：⏳ 尚未在 Windows 真机上验证（2026-11-03 记录）。对应实现：`bootstrap.ps1`、D-022、D-029、`files/mihomo/windows-desktop.yaml`。
> 已完成的离线验证：PowerShell 7 语法解析通过；预渲染配置与模板一致，填入节点后 `mihomo -t` 通过；mihomo / WinSW 的 sha256 已核对。
> 验证完成后：在每项后标注 ✅ / ❌，问题记入 `pitfalls.md`，结论更新到 `progress.md` 与 D-029 的状态。

## 0. 环境与准备

| 项目 | 要求 |
| --- | --- |
| 系统 | Windows 11 x64（ARM64 暂不支持 mihomo 服务，脚本会跳过） |
| PowerShell | 系统自带的 **Windows PowerShell 5.1**（不要用 pwsh 7，验证的是默认环境） |
| 权限 | 「以管理员身份运行」的 PowerShell（另需一个普通权限窗口做对照） |
| 私钥 | age 私钥（`AGE-SECRET-KEY-…`），运行时按提示输入 |
| 其他代理 | 关闭其他代理客户端 / VPN 的 TUN 与系统代理（如 Clash Verge Rev），避免路由冲突 |
| 执行策略 | `irm … \| iex` 不受执行策略限制；用 `-File` 运行时加 `-ExecutionPolicy Bypass` |

建议先建一个系统还原点或虚拟机快照，便于回滚。

## 1. 首次部署（管理员）

```powershell
irm https://gh-proxy.com/https://raw.githubusercontent.com/Lostrit/newsysboot/main/bootstrap.ps1 | iex
```

预期：

- [ ] winget 安装 mise 与 PowerShell 7（已安装则跳过）；**不安装 Git**（D-040）
- [ ] 有 `ssh.exe`（缺失时自动安装 OpenSSH 客户端）；`Get-Service ssh-agent` 为 Running、Automatic
- [ ] 下载仓库压缩包：CNB 直连，或 GitHub 依次尝试内置的加速代理（最后才直连）
- [ ] 输出「选择 GitHub 加速代理（测延时与 release / raw / archive / clone）…」，约 30～60 秒后输出 `GH_PROXY: https://…`；
      `%LOCALAPPDATA%\bootstrap\gh-proxy.txt` 记录选择结果；再次运行时输出「使用缓存的 GitHub 加速代理」（D-031）
- [ ] mihomo、WinSW 经该加速代理下载；可手动设置 `$env:GH_PROXY='https://127.0.0.1:9/'` 后运行，确认输出「经 GitHub 加速代理下载失败，改为直连」并继续
- [ ] 选择拉取来源后，压缩包解压到 `%USERPROFILE%\.local\share\bootstrap`（目录中有 `.bootstrap-archive`，没有 `.git`）
- [ ] 输出「不启用的工具：…」（`lib/tool-roles.txt` 中 windows 的清单）；`mise install` 安装 fnox 与 Shell、文件搜索工具
- [ ] 下载 mihomo 与 WinSW 时 sha256 校验通过（失败会报「sha256 校验失败」并中止）
- [ ] 提示输入 age 私钥；输入时不回显
- [ ] 输出「注册并启动 mihomo 服务」，最后输出「mihomo 已生效（TUN 模式，开机自动启动）」
- [ ] 之后的 `mise bootstrap --only dotfiles,tools` 正常完成（此时 GitHub 下载经 TUN 代理）

记录：总耗时、是否出现 SmartScreen / Defender 拦截（WinSW、mihomo 为未签名或少见的可执行文件）。

## 1.5 本地系统的工具、PowerShell 7 与字体（D-036、D-039、D-040）

也可以直接运行自动检查：`pwsh -File $HOME\.local\share\bootstrap\tests\ci\verify-windows.ps1`（GitHub Actions 使用同一个脚本）。

- [ ] 新开 Windows Terminal 中的 **PowerShell 7**（`pwsh`）：starship 提示符正常，没有报错
- [ ] 输入命令时有灰色的历史预测，按 → 接受；命令、参数、字符串有颜色（Catppuccin Mocha）
- [ ] Ctrl+R 打开 atuin 历史搜索；Tab 补全弹出 fzf 选择（PSFzf）；Ctrl+T 选文件、Alt+C 进入目录
- [ ] `ll`、`lt` 输出 eza 的长列表 / 树形（带图标）；`bat`、`rg`、`fd`、`jq` 可用，`jq` 输出有颜色
- [ ] `nvim`、`node`、`git`、`lazygit`、`tmux` 不存在（`Get-Command` 找不到）
- [ ] `ssh <远程主机>` 能登录；`ssh-add` 能添加密钥（ssh-agent 已启用）
- [ ] 终端设置中能选到字体「Maple Mono Normal NF CN」，图标与中文显示正常
- [ ] 系统自带的 Windows PowerShell 5.1 打开时没有报错（不加载这份配置）

## 2. 文件布局与权限

```powershell
Get-ChildItem "$env:ProgramFiles\mihomo"
Get-ChildItem "$env:ProgramData\mihomo" -Recurse -Force | Select-Object FullName
icacls "$env:ProgramData\mihomo"
icacls "$env:ProgramData\mihomo\config\config.yaml"
```

预期：

- [ ] `%ProgramFiles%\mihomo` 下有 `mihomo.exe`、`mihomo-service.exe`、`mihomo-service.xml`
- [ ] `%ProgramData%\mihomo` 下有 `config\config.yaml`、`logs\`、`.bootstrap.sha256`
- [ ] `icacls` 只列出 `NT AUTHORITY\SYSTEM` 与 `BUILTIN\Administrators`（中文系统显示为对应的中文名），没有 Users / Authenticated Users
- [ ] 在**普通权限**的 PowerShell 中执行 `Get-Content "$env:ProgramData\mihomo\config\config.yaml"`：拒绝访问
- [ ] `config.yaml` 中 `proxies:` 段为真实节点，文件中不再有 `# @@MIHOMO_PROXIES@@`
- [ ] `& "$env:ProgramFiles\mihomo\mihomo.exe" -v` 显示 v1.19.33

## 3. 服务定义

```powershell
Get-Service mihomo | Format-List Name, Status, StartType
sc.exe qc mihomo
sc.exe qfailure mihomo
Get-CimInstance Win32_Service -Filter "Name='mihomo'" | Select-Object StartName, DelayedAutoStart, PathName
```

预期：

- [ ] `Status` 为 Running，`StartType` 为 Automatic
- [ ] `sc qc` 中 `START_TYPE` 为 `2 AUTO_START`，**不是** `AUTO_START (DELAYED)`；`DelayedAutoStart` 为 False
- [ ] `DEPENDENCIES` 包含 `Tcpip`、`Dnscache`
- [ ] `SERVICE_START_NAME` / `StartName` 为 `LocalSystem`
- [ ] `sc qfailure` 显示失败后重启（5 秒、15 秒）

## 4. TUN 与分流

在**普通权限**窗口中执行（不设置任何代理参数，验证 TUN 接管）：

```powershell
Get-NetAdapter | Where-Object InterfaceDescription -match 'Meta|mihomo|Wintun' | Format-Table Name, InterfaceDescription, Status
curl.exe -sS -o NUL -w "%{http_code} %{time_total}s`n" https://www.google.com
curl.exe -sS -o NUL -w "%{http_code} %{time_total}s`n" https://github.com
curl.exe -sS -o NUL -w "%{http_code} %{time_total}s`n" https://www.baidu.com
curl.exe -sS -o NUL -w "%{http_code} %{time_total}s`n" https://apps.apple.com
nslookup github.com
Get-Content "$env:ProgramData\mihomo\logs\mihomo-service.out.log" -Tail 30   # 需要管理员窗口
```

预期：

- [ ] 存在 mihomo 创建的 TUN 网卡（Status 为 Up）
- [ ] google / github 返回 200（不设代理，经 TUN）
- [ ] `nslookup` 返回 `198.18.x.x`（fake-ip）
- [ ] 日志中可以看到：
  - [ ] `github.com` → `match RuleSet(github) using 开发[…]`
  - [ ] `www.google.com` → `using 海外服务[…]`
  - [ ] `www.baidu.com` → `using DIRECT`
  - [ ] `apps.apple.com` → `using DIRECT`（国区 App Store 直连）
- [ ] 打开微软商店（Microsoft Store）可以正常浏览、下载（国区）
- [ ] 局域网设备（路由器管理页、NAS、打印机）可以正常访问（局域网段不进入 TUN）
- [ ] 广告域名被拦截：日志中出现 `using AD[REJECT]`（例如访问一个含广告的网页后查看）

## 5. 开机生效时机（本次改动的核心）

目的：确认「登录进桌面后要等一段时间代理才生效」的问题已解决。

1. 创建一个登录时运行的测试任务，记录登录后多久能经 TUN 访问 Google（管理员窗口执行一次即可）：

   ```powershell
   $log = "$env:PUBLIC\mihomo-boot-test.log"
   $cmd = "`$t0=Get-Date; for(`$i=0;`$i -lt 120;`$i++){ try { Invoke-WebRequest https://www.google.com -UseBasicParsing -TimeoutSec 3 | Out-Null; Add-Content '$log' (\"{0} 登录后 {1:N1} 秒可用\" -f (Get-Date), ((Get-Date)-`$t0).TotalSeconds); break } catch { Start-Sleep 1 } }"
   $action = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -WindowStyle Hidden -Command $cmd"
   Register-ScheduledTask -TaskName 'mihomo-boot-test' -Action $action -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Force
   ```

2. 重启电脑并登录，等 2 分钟后查看：

   ```powershell
   Get-Content "$env:PUBLIC\mihomo-boot-test.log"
   # 服务启动时间与登录时间
   Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; Id=7036} -MaxEvents 200 |
     Where-Object Message -match 'Mihomo' | Select-Object -First 3 TimeCreated, Message
   Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Winlogon'; Id=7001} -MaxEvents 3 |
     Select-Object TimeCreated
   ```

预期：

- [ ] Mihomo 服务「进入正在运行状态」的时间**早于**用户登录（Winlogon 7001）
- [ ] 测试任务记录的「登录后 N 秒可用」接近 0（几秒以内）
- [ ] 平时依赖代理的开机自启应用（记录具体是哪些）启动后不再出现网络连接失败
- [ ] 重复重启 2～3 次结果一致；如条件允许，再分别测试有线 / Wi-Fi（Wi-Fi 在登录前可能尚未连接）

测试结束后删除测试任务：`Unregister-ScheduledTask -TaskName mihomo-boot-test -Confirm:$false`。

## 6. 崩溃自动重启

```powershell
Stop-Process -Name mihomo -Force
Start-Sleep 10
Get-Service mihomo; Get-Process mihomo
```

- [ ] 约 5 秒后服务恢复 Running，出现新的 mihomo 进程
- [ ] 若 WinSW 没有因子进程退出而重启：记录现象（可能需要在 XML 中调整），并检查 `logs\mihomo-service.wrapper.log`

## 7. 重复执行与变化检测

```powershell
# 原样再运行一次（管理员）
irm https://gh-proxy.com/https://raw.githubusercontent.com/Lostrit/newsysboot/main/bootstrap.ps1 | iex
```

- [ ] 不重新下载 mihomo / WinSW；不输出「重启 mihomo 服务」（配置未变）
- [ ] 服务 PID 不变：运行前后各执行一次 `(Get-Process mihomo).Id` 对比
- [ ] 修改配置后（例如仓库更新了模板、重新生成了 `windows-desktop.yaml`）再运行：输出「配置有变化，重启 mihomo 服务」，并且新配置生效
- [ ] 手动停止服务（`Stop-Service mihomo`）后再运行：服务被重新启动

## 8. 非管理员与跳过选项

- [ ] 在**普通权限**窗口运行：输出「部署 mihomo 服务需要管理员权限…」警告，dotfiles 与工具照常部署，脚本正常结束
- [ ] 管理员窗口中 `$env:BOOTSTRAP_NO_MIHOMO='1'` 后运行（或 `& ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 .\bootstrap.ps1))) -NoMihomo`，不要用 `-File`，P-050）：输出「跳过 mihomo」，不改动服务
- [ ] 无人值守：预先设置 `$env:FNOX_AGE_KEY`、`$env:BOOTSTRAP_SOURCE='github'` 后运行，不出现任何交互提示
- [ ] 输入错误的私钥：报「fnox 解密 mihomo 节点失败」并中止，已有的服务与配置不被破坏

## 9. 私钥与节点不残留

```powershell
[Environment]::GetEnvironmentVariable('FNOX_AGE_KEY', 'User')
[Environment]::GetEnvironmentVariable('FNOX_AGE_KEY', 'Machine')
Select-String -Path (Get-PSReadLineOption).HistorySavePath -Pattern 'AGE-SECRET-KEY' -SimpleMatch
Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Select-String -Pattern 'AGE-SECRET-KEY' -SimpleMatch -List
Get-ChildItem "$env:ProgramData\mihomo\logs" | Select-String -Pattern 'AGE-SECRET-KEY' -SimpleMatch -List
```

- [ ] 两个环境变量查询都为空（私钥只存在于脚本进程中）
- [ ] PowerShell 历史、临时目录、mihomo 日志中都找不到私钥（交互输入经 `Read-Host -AsSecureString`，不会写入历史）
- [ ] `%TEMP%` 下没有残留的 `bootstrap-mihomo-*` 临时目录

## 10. 回滚 / 卸载（验证后按需执行）

```powershell
& "$env:ProgramFiles\mihomo\mihomo-service.exe" stop
& "$env:ProgramFiles\mihomo\mihomo-service.exe" uninstall
Remove-Item "$env:ProgramFiles\mihomo", "$env:ProgramData\mihomo" -Recurse -Force
```

- [ ] 卸载后 TUN 网卡消失，网络恢复为直连
- [ ] 再次运行 bootstrap 可以从头部署成功

## 11. 需要回传的信息

验证中出现问题时，请保留并提供：

- bootstrap 的完整输出（去掉其中的节点信息）
- `%ProgramData%\mihomo\logs\` 下的 `mihomo-service.wrapper.log`、`mihomo-service.out.log`、`mihomo-service.err.log`（注意脱敏）
- `sc.exe qc mihomo`、`icacls` 的输出
- 第 5 节的 `mihomo-boot-test.log` 与事件时间

## 12. 已知风险 / 需要重点观察的点

| 风险 | 说明 |
| --- | --- |
| PowerShell 5.1 兼容性 | 只用 PowerShell 7 做过语法解析，没有在 5.1 中运行过 |
| WinSW 与子进程 | 依赖 WinSW 在 mihomo 退出时让服务失败，从而触发 `onfailure` 重启（第 6 节） |
| 登录前网络未就绪 | Wi-Fi 等在登录前可能尚未连接；mihomo 的 `auto-detect-interface` 应在网卡就绪后自动接管（第 5 节） |
| 规则集首次下载 | 第一次启动需经 jsDelivr 下载规则集（缓存在 `config` 目录）；之后开机读缓存 |
| 安全软件拦截 | WinSW、mihomo 可能被 SmartScreen / Defender 提示或隔离 |
| 与其他代理客户端冲突 | 同时开启其他 TUN / VPN 会争抢路由 |
| 只支持 x64 | ARM64 设备上会跳过 mihomo 服务 |
