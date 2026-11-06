# macOS 真机验证清单（待执行）

> 状态：⏳ 尚未在 macOS 真机上验证（2026-11-03 记录）。
> 对应实现：`bootstrap.sh` + `lib/macos.sh`（Xcode 命令行工具、Homebrew 清华镜像）、`mise.macos.toml`、
> `scripts/install-mihomo.sh`（darwin 独立二进制）、`files/mihomo/bootstrap.mihomo.plist`、`scripts/macos-mihomo-daemon.sh`、
> mihomo 的 desktop 场景（D-021 → D-028、D-027）。
> 已完成的离线验证：desktop 场景渲染后 `mihomo -t` 通过；`tests/mihomo-rules.sh` 的 desktop 分流 28 项通过（在 Linux 主机上）；
> plist 格式校验通过；`mise -E macos bootstrap --dry-run --only files` 的计划为创建 `/opt/mihomo`、`/opt/mihomo/config`，
> 写入 `config.yaml` 与 `/Library/LaunchDaemons/bootstrap.mihomo.plist`；darwin 二进制的 sha256 与 GitHub digest 一致。
> 验证完成后：在每项后标注 ✅ / ❌，问题记入 `pitfalls.md`，结论更新到 `progress.md` 与 D-028 的状态。

## 0. 环境与准备

| 项目 | 要求 |
| --- | --- |
| 系统 | 记录 macOS 版本与芯片：`sw_vers; uname -m`（arm64 / x86_64 都支持） |
| 用户 | 管理员账户（需要 sudo，部署中会要求输入登录密码） |
| Xcode 命令行工具 | **不要预先安装**，用全新状态验证 P-038 的修复：bootstrap 应弹出安装窗口并在装好后自动继续（第 1 节） |
| 私钥 | age 私钥（`AGE-SECRET-KEY-…`），运行时按提示输入 |
| 其他代理 | 退出其他代理客户端（ClashX、Clash Verge、Surge 等），并关闭它们的「增强模式 / TUN」与系统代理 |
| 系统代理 | 「系统设置 → 网络 → 详细信息 → 代理」中不要残留其他客户端设置的代理 |

记录基线（部署前）：

```sh
sw_vers; uname -m
xcode-select -p; git --version
echo $SHELL; ls /opt/homebrew/bin/brew /usr/local/bin/brew 2>/dev/null
ifconfig | grep -c '^utun'          # 部署前已有的 utun 数量（系统自身会创建若干个）
scutil --proxy | head -12
```

## 1. 首次部署

```sh
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/Lostrit/newsysboot/main/bootstrap.sh | sh
```

预期：

- [ ] 没有命令行工具时（P-038）：输出「安装 Xcode 命令行工具（提供 git）…」并弹出系统安装窗口；点击「安装」后，
      每分钟输出一次等待提示，装好后输出「Xcode 命令行工具已安装：…」并**自动继续**拉取仓库，不需要重新运行
- [ ] 在安装窗口中点击「取消」：等待 30 分钟后报「尚未安装完成…请重新运行」并退出（可选验证，耗时长）
- [ ] 识别为 macOS：模块为 `macos`（不安装 Docker、不做 SSH 加固、不新建用户）
- [ ] Homebrew 经清华镜像安装（已安装则跳过）；`brew config` 中的 API / bottle 域名为镜像地址
- [ ] 需要 sudo 的步骤提示输入登录密码
- [ ] mihomo 下载为 `mihomo-darwin-<arm64|amd64>-v1.19.33.gz`，sha256 校验通过，装到 `/opt/mihomo/bin/mihomo`
- [ ] 提示输入 age 私钥（不回显）
- [ ] 第一次 `mise bootstrap`（files、packages、dotfiles）后输出 `macos-mihomo-daemon: 已加载 bootstrap.mihomo`
- [ ] 随后输出「mihomo 可用（http://127.0.0.1:7890），之后经代理访问 GitHub」
- [ ] 登录 shell：已经是 `/bin/zsh` 时不变；否则 `chsh` 要求输入密码
- [ ] 20 个工具安装完成；nvim 预装（网络检测通过时）完成或给出 WARNING
- [ ] 部署结束后新开终端：zsh 启动无报错，提示符正常

记录：总耗时、需要输入密码的次数、是否出现系统弹窗（「允许接受传入网络连接」「后台项目已添加」等）。

## 1.5 本地系统的工具与字体（D-036、D-039）

也可以直接运行自动检查：`zsh ~/.local/share/bootstrap/tests/ci/verify-macos.zsh`（GitHub Actions 使用同一个脚本；那里是 macOS 15，这里是 13.7.8 Intel）。

- [ ] `tmux`、`herdr`、`claude`、`btop` 不由 mise 提供（`mise which tmux` 失败）；nvim、node、bun、gh、fnox、age、jq 可用
- [ ] `~/Library/Fonts` 中有 `MapleMonoNormal-NF-CN-{Regular,Italic,Bold,BoldItalic}.ttf`；终端（Ghostty 等）中选用「Maple Mono Normal NF CN」后图标与中文正常
- [ ] `gh auth login` 后凭据在钥匙串中，`~/.config/gh/hosts.yml` 中没有 token；仓库 `git status` 干净

## 2. 文件布局与权限

```sh
ls -ld /opt/mihomo /opt/mihomo/bin /opt/mihomo/config
ls -l /opt/mihomo/bin/mihomo /Library/LaunchDaemons/bootstrap.mihomo.plist
sudo ls -l /opt/mihomo/config
cat /opt/mihomo/config/config.yaml          # 普通用户应被拒绝
/opt/mihomo/bin/mihomo -v
xattr -l /opt/mihomo/bin/mihomo             # 不应有 com.apple.quarantine
```

- [ ] `/opt/mihomo`、`/opt/mihomo/bin`：root:wheel 755；`mihomo`：root:wheel 755（当前用户不可写）
- [ ] `/opt/mihomo/config`：root:wheel 700；`config.yaml`：root:wheel 600；普通用户 `cat` 被拒绝
- [ ] plist：root:wheel 644
- [ ] `mihomo -v` 显示 v1.19.33；没有 quarantine 属性（curl 下载不会添加，若有则 launchd 可能无法启动）

## 3. LaunchDaemon

```sh
sudo launchctl print system/bootstrap.mihomo | grep -E 'state|pid|last exit|program'
sudo tail -20 /var/log/mihomo.log
```

- [ ] `state = running`，有 pid，以 root 运行（`ps -o user,pid,command -p <pid>`）
- [ ] 日志中没有 error；规则集下载成功
- [ ] 「系统设置 → 通用 → 登录项与扩展 → 允许在后台」中出现该项时记录名称（macOS 13+ 会列出后台项目）

## 4. TUN 与分流

```sh
ifconfig | grep -A3 '^utun' | tail -8       # 比基线多出一个 utun，带 198.18.x.x 地址
netstat -rn -f inet | head -20
dig +short github.com                       # 或 dscacheutil -q host -a name github.com
env -u http_proxy -u https_proxy -u all_proxy curl -sS -o /dev/null -w '%{http_code} %{time_total}s\n' https://www.google.com
env -u http_proxy -u https_proxy -u all_proxy curl -sS -o /dev/null -w '%{http_code}\n' https://github.com
sudo grep -E 'github.com|www.google.com|www.baidu.com|apps.apple.com' /var/log/mihomo.log | tail -8
```

- [ ] 新增的 utun 网卡由 mihomo 创建；默认路由指向它，局域网段（如 192.168.0.0/16）仍走物理网卡
- [ ] 不设代理变量时 Google / GitHub 可访问（经 TUN）；`dig github.com` 返回 `198.18.x.x`（fake-ip）
- [ ] 日志：`github.com` → `开发[…]`；`www.google.com` → `海外服务[…]`；`www.baidu.com` → `DIRECT`；`apps.apple.com` → `DIRECT`
- [ ] **App Store**（国区）可以浏览、下载、更新应用；Apple ID 登录、iCloud 同步正常
- [ ] Safari、Chrome 不设系统代理也能访问被墙网站；不在 mihomo 中的普通海外网站可访问
- [ ] 视频（YouTube、Netflix）、直播（Twitch）、聊天（Telegram、Discord）、社交（X、Reddit）可用
- [ ] 开发：`git clone https://github.com/…`、`npm view react version`（registry 为国内镜像时走直连）、`go env GOPROXY` 相关下载、`docker pull`（若装了 Docker Desktop）
- [ ] AI 平台（ChatGPT、Claude、Gemini）网页与 API 可用
- [ ] 广告拦截：打开含广告的网页，日志中出现 `using AD[REJECT]`；误拦时 AD 组可切 DIRECT（目前没有面板，需改配置）
- [ ] 局域网设备（路由器管理页、NAS、打印机、AirPlay 投屏）正常
- [ ] 国内应用（微信、QQ 音乐、Bilibili 等）正常且走直连

## 5. 开机生效时机

LaunchDaemon 应在开机阶段、用户登录前启动。

1. 创建一个登录时运行的测试 LaunchAgent，记录登录后多久能经 TUN 访问 Google：

   ```sh
   mkdir -p ~/Library/LaunchAgents
   cat > ~/Library/LaunchAgents/bootstrap.boottest.plist <<'EOF'
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0"><dict>
     <key>Label</key><string>bootstrap.boottest</string>
     <key>RunAtLoad</key><true/>
     <key>ProgramArguments</key><array><string>/bin/sh</string><string>-c</string>
       <string>t0=$(date +%s); for i in $(seq 120); do curl -s -m 3 -o /dev/null https://www.google.com &amp;&amp; { echo "$(date) 登录后 $(( $(date +%s) - t0 )) 秒可用" >> /tmp/mihomo-boot-test.log; exit 0; }; sleep 1; done</string>
     </array>
   </dict></plist>
   EOF
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/bootstrap.boottest.plist
   ```

2. 重启并登录，等 2 分钟后查看：

   ```sh
   cat /tmp/mihomo-boot-test.log
   sudo launchctl print system/bootstrap.mihomo | grep -E 'pid|state'
   ps -o lstart= -p "$(pgrep -x mihomo)"     # mihomo 进程的启动时间
   last -1 "$USER"                            # 登录时间
   ```

- [ ] mihomo 的启动时间早于登录时间
- [ ] 测试记录「登录后 N 秒可用」接近 0
- [ ] 依赖代理的登录项应用启动后不再出现网络连接失败（记录具体应用）
- [ ] 重启 2～3 次结果一致；分别测试 Wi-Fi（登录前是否已连接）与有线

测试结束后删除：`launchctl bootout gui/$(id -u)/bootstrap.boottest; rm ~/Library/LaunchAgents/bootstrap.boottest.plist /tmp/mihomo-boot-test.log`。

## 6. 崩溃自动重启

```sh
sudo kill -9 "$(pgrep -x mihomo)"; sleep 5; pgrep -x mihomo && sudo launchctl print system/bootstrap.mihomo | grep pid
```

- [ ] 几秒内出现新的 mihomo 进程（`KeepAlive`），网络恢复

## 7. 睡眠唤醒与网络切换

- [ ] 合盖睡眠后唤醒：TUN 与网络自动恢复，无需重启服务
- [ ] 切换 Wi-Fi、插拔网线 / 扩展坞、开关个人热点：网络自动恢复（`auto-detect-interface`）
- [ ] 断网后恢复：无需人工干预

## 8. 重复执行与变化检测

```sh
pgrep -x mihomo                                   # 记录 PID
sh ~/.local/share/bootstrap/bootstrap.sh          # 完整重新运行（需要再次输入私钥）
pgrep -x mihomo                                   # PID 应不变
sh ~/.local/share/bootstrap/bootstrap.sh --dotfiles
```

- [ ] 完整重新运行：`install-mihomo: 已是 v1.19.33`；配置未变时不输出「已重启」，PID 不变
- [ ] 仓库模板更新后完整重新运行：输出 `macos-mihomo-daemon: 配置有变化，已重启 bootstrap.mihomo`，新配置生效
- [ ] 手动 `sudo launchctl bootout system/bootstrap.mihomo` 后重新运行：重新加载
- [ ] `--dotfiles`：不需要私钥，`env.sh` 保留代理设置（「使用环境中的代理」）

## 9. 系统升级后保留

- [ ] macOS 小版本更新后：`/opt/mihomo`、plist 仍在，开机后 mihomo 正常运行
- [ ] Homebrew 更新（`brew upgrade`）不影响 mihomo（mihomo 不由 Homebrew 管理）

## 10. 私钥不残留

```sh
sudo grep -rlsaE 'AGE-SECRET-KEY-1[0-9A-Z]{50,}' ~/.local/state /tmp /private/var/tmp /var/log /opt/mihomo 2>/dev/null
grep -c 'AGE-SECRET-KEY' ~/.local/state/zsh/history ~/.zsh_history 2>/dev/null
log show --last 1h --predicate 'eventMessage CONTAINS "AGE-SECRET-KEY"' 2>/dev/null | grep -c AGE-SECRET-KEY
```

- [ ] 文件、shell 历史、统一日志中都找不到私钥

## 11. 回滚 / 卸载（验证后按需执行）

```sh
sudo launchctl bootout system/bootstrap.mihomo
sudo rm -f /Library/LaunchDaemons/bootstrap.mihomo.plist
sudo rm -rf /opt/mihomo /var/log/mihomo.log
rm -f ~/.local/state/bootstrap/mihomo-daemon.sha256
```

- [ ] 卸载后 utun 网卡消失，网络恢复直连
- [ ] 再次运行 bootstrap 可以从头部署成功

## 12. 需要回传的信息

- bootstrap 的完整输出（去掉节点信息）
- `/var/log/mihomo.log` 中与问题相关的部分（注意脱敏）
- `sudo launchctl print system/bootstrap.mihomo`、`ifconfig`、`netstat -rn -f inet` 的输出
- 第 5 节的 `/tmp/mihomo-boot-test.log`、进程启动时间与登录时间

## 13. 已知风险 / 需要重点观察的点

| # | 风险 | 说明 |
| --- | --- | --- |
| 1 | 命令行工具的安装等待（P-038，已修复，未在真机验证） | 依赖 `xcode-select -p` 在安装完成后返回成功；系统更新等情况下若 `xcode-select -p` 指向失效的路径，需要 `sudo xcode-select --reset` |
| 2 | sudo 次数 | 写入 `/opt`、`/Library` 与加载 LaunchDaemon 都要 sudo；密码缓存过期后可能多次询问 |
| 3 | 后台项目提示 | macOS 13+ 会提示「已添加后台项目」，需要允许 |
| 4 | DNS 劫持 | TUN 的 `dns-hijack: any:53` 能否接管系统 DNS（mDNSResponder）；fake-ip 是否影响 iCloud、AirDrop 等 |
| 5 | 与其他代理客户端冲突 | 同时开启其他增强模式 / TUN 会争抢路由 |
| 6 | 广告误拦 | 目前没有面板，AD 组只能改配置切换 |
| 7 | 未签名的二进制 | 由 launchd 以 root 运行未签名的 mihomo；没有 quarantine 属性时应不受 Gatekeeper 影响，未实测 |
