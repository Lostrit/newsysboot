# SteamOS 真机验证清单（待执行）

> 状态：⏳ 尚未在 SteamOS 真机（Steam Deck 等）上验证（2026-11-03 记录）。
> 对应实现：`bootstrap.sh`（以 `deck` 等普通用户运行，D-025）、`mise.steamos.toml`、`files/mihomo/mihomo.service`、
> `scripts/install-mihomo.sh`（独立二进制，D-020）、mihomo 的 steamos 场景（`files/mihomo/config.yaml.tera`，D-027、D-028）。
> 已完成的离线验证：steamos 场景渲染后 `mihomo -t` 通过；`tests/mihomo-rules.sh` 的 steamos 分流 12 项通过（在 Linux 主机上，关闭 TUN，
> 用假节点；Steam 商店的 fallback 在「直连可用、代理不可用」时回退 DIRECT）。
> 验证完成后：在每项后标注 ✅ / ❌，问题记入 `pitfalls.md`，结论更新到 `progress.md` 与 D-020 / D-027 / D-028 的状态。

## 0. 环境与准备

| 项目 | 要求 |
| --- | --- |
| 系统 | SteamOS 3.x（记录版本：`cat /etc/os-release`，以及「设置 → 系统」中的版本与更新通道） |
| 模式 | 部署在**桌面模式**的 Konsole 中进行；验证同时覆盖桌面模式与**游戏模式** |
| 用户 | `deck`（普通用户）。默认没有密码，sudo 需要先执行 `passwd` 设置密码 |
| 私钥 | age 私钥（`AGE-SECRET-KEY-…`），运行时按提示输入 |
| 约束 | **不得**执行 `steamos-readonly disable`，不得用 pacman 修改根分区；所有改动应只落在 `/etc`、`/var`、`/home` |
| 其他代理 | 关闭其他代理软件（如 Decky 插件中的代理、Clash 类软件） |
| 对照设备 | 同一局域网中的一台 PC（局域网串流）；另一个国内网络中的 PC 或手机热点（互联网远程畅玩） |

记录基线（部署前）：

```sh
cat /etc/os-release
command -v git curl zsh gcc cc || true   # SteamOS 是否自带 git / curl / zsh（D-020 待核实）
systemctl is-enabled sshd 2>/dev/null; ls ~/.ssh/authorized_keys 2>/dev/null
sudo steamos-readonly status
```

## 1. 首次部署

```sh
passwd   # 如尚未设置密码
curl -fsSL https://gh-proxy.com/https://raw.githubusercontent.com/Lostrit/newsysboot/main/bootstrap.sh | sh
```

预期：

- [ ] 识别为 SteamOS：模块为 `steamos,mihomo`（不安装 Docker；没有 apt，不做换源）
- [ ] 需要 root 的步骤提示输入 sudo 密码，之后不再重复询问
- [ ] 不新建用户；SSH 加固：`deck` 没有 `authorized_keys` 时输出「没有 SSH 公钥…跳过 SSH 加固」（有公钥时按提示确认后执行）
- [ ] 登录 shell 经 sudo 设置为 zsh（P-031），不要求输入 `deck` 自己的密码之外的东西
- [ ] mihomo 下载为 `mihomo-linux-amd64-v1.19.33.gz`，sha256 校验通过，装到 `/var/lib/mihomo/bin/mihomo`
- [ ] 提示输入 age 私钥（不回显）
- [ ] 第一次 `mise bootstrap` 后输出「mihomo 可用（http://127.0.0.1:7890），之后经代理访问 GitHub」
- [ ] 20 个工具安装完成
- [ ] nvim 预装：SteamOS 没有 C 编译器时，应输出 `WARNING: nvim 预装未全部完成…`（缺少 cc），部署整体仍然成功；记录实际输出
- [ ] 部署结束后 `sudo steamos-readonly status` 仍为 enabled（只读未被关闭）

记录：总耗时、哪些步骤需要输入密码、是否有报错。

## 2. 文件布局与系统分区

```sh
ls -l /var/lib/mihomo/bin/mihomo /etc/systemd/system/mihomo.service
sudo ls -la /etc/mihomo
sudo stat -c '%a %U' /etc/mihomo/config.yaml
cat /etc/mihomo/config.yaml   # 普通用户应被拒绝
sudo pacman -Q mihomo 2>/dev/null || echo "未经 pacman 安装（预期）"
```

- [ ] 二进制在 `/var/lib/mihomo/bin`，属主 root，权限 755
- [ ] unit 在 `/etc/systemd/system/mihomo.service`
- [ ] `config.yaml` 为 `600 root`；普通用户 `cat` 被拒绝
- [ ] 根分区没有被改动（没有通过 pacman 安装任何东西）

## 3. 服务

```sh
systemctl status mihomo --no-pager
systemctl is-enabled mihomo
systemctl show mihomo -p Restart -p RestartUSec -p AmbientCapabilities
journalctl -u mihomo -b --no-pager | head -30
```

- [ ] active (running)，enabled
- [ ] `Restart=on-failure`，`RestartSec=10s`，具有 `cap_net_admin`（TUN 需要）
- [ ] 日志中没有 error；规则集下载成功（首次需经 jsDelivr）

## 4. TUN

```sh
ip -br addr | grep -iE 'meta|mihomo|tun'
ip rule
ip route show table all | grep -iE 'meta|tun' | head
resolvectl status | head -20
curl -sS -o /dev/null -w '%{http_code} %{time_total}s\n' https://www.google.com          # 不设代理
env -u http_proxy -u https_proxy -u all_proxy curl -sS -o /dev/null -w '%{http_code}\n' https://github.com
getent hosts github.com
```

- [ ] 存在 mihomo 创建的 TUN 网卡（如 `Meta`），状态 UP
- [ ] 不设代理变量时 Google / GitHub 可访问（经 TUN）
- [ ] `getent hosts github.com` 返回 `198.18.x.x`（fake-ip）；国内域名（如 `www.baidu.com`）返回真实 IP（fake-ip-filter）
- [ ] 路由表中局域网段与国内 IP 段被排除在 TUN 之外（`route-exclude-address` / `route-exclude-address-set: cn-ip`）：
  `ip route get 192.168.1.1`、`ip route get 119.29.29.29` 不经 TUN 网卡；`ip route get 8.8.8.8` 经 TUN 网卡
- [ ] 桌面模式中的浏览器（Firefox 等）不设代理也能访问被墙网站

## 5. Steam 商店（优先代理，失败回退直连）

在**游戏模式**与**桌面模式**的 Steam 客户端中分别打开商店、社区、个人资料页面，同时观察日志：

```sh
journalctl -u mihomo -f | grep -iE 'steam'
```

- [ ] 商店、社区、登录正常，页面图片可加载
- [ ] 日志中 `store.steampowered.com`、`steamcommunity.com`、`*.steamstatic.com` → `match RuleSet(steam) using Steam商店[<节点名>]`（代理可用时走节点）
- [ ] **回退测试**：临时阻断到节点服务器的连接，约 2 分钟（健康检查间隔 120 秒）后，Steam 商店改为 `Steam商店[DIRECT]` 且仍可打开（直连能访问时）

  ```sh
  NODE_IP=<节点服务器 IP>
  sudo nft add table inet bstest
  sudo nft add chain inet bstest out '{ type filter hook output priority 0; }'
  sudo nft add rule inet bstest out ip daddr $NODE_IP drop
  # …等待 2～3 分钟，打开商店，查看日志…
  sudo nft delete table inet bstest
  ```

- [ ] 恢复连接后，约 2 分钟内重新回到节点
- [ ] 记录：直连状态下 Steam 商店本身能否打开（取决于当地网络），以及回退所需的时间

## 6. 游戏下载（不走代理）

下载或更新一个游戏（选一个几 GB 的，观察稳定速度）：

```sh
journalctl -u mihomo -f | grep -iE 'steamcontent|steampipe|steamchina|steamserver|wmsjsteam'
```

- [ ] 下载相关域名全部 `using DIRECT`（`steam-download` / `steam-cn` 规则），没有经节点
- [ ] 下载速度与关闭 mihomo 时相当（对比记录：开启 / 关闭 mihomo 各下载一段时间的速度）
- [ ] 下载服务器（Steam「设置 → 下载 → 下载地区」）为国内地区时，连接到国内 CDN；记录所用地区
- [ ] 创意工坊内容下载正常

## 7. 局域网与互联网远程畅玩

局域网串流（Deck 与同一局域网的 PC 互相串流）：

- [ ] 串流可以建立，画面流畅；Steam 串流统计（性能叠加层 / 串流设置中的统计信息）中连接类型为局域网直连
- [ ] `journalctl -u mihomo` 中没有该 PC 局域网 IP 的连接记录（局域网段不进入 TUN）
- [ ] 记录延迟、丢包、码率

互联网远程畅玩（国内网络 ↔ 国内网络，例如对端用手机热点或另一处宽带）：

- [ ] 串流可以建立；记录连接方式（直连 P2P 还是经 Steam 中继）
- [ ] 对端为国内 IP 时，流量不经过 mihomo（国内 IP 段不进入 TUN）；经中继时，`*.steamserver.net` / 中继 IP 的连接为 `DIRECT`
- [ ] 与关闭 mihomo 时对比：延迟、丢包、画面稳定性没有明显变差
- [ ] 远程同乐（Remote Play Together）可用

## 8. 其他游戏联机

- [ ] 选 1～2 个联机游戏，进入在线对局：连接正常，延迟与关闭 mihomo 时相当（UDP 一律直连）
- [ ] 日志中游戏服务器的 UDP 连接为 `DIRECT`

## 9. 休眠唤醒、网络切换与重启

- [ ] 休眠后唤醒（按电源键）：网络与 TUN 自动恢复，Steam 商店可用，无需重启服务
- [ ] 切换 Wi-Fi（或在 Wi-Fi 与有线 / 扩展坞之间切换）：网络自动恢复（`auto-detect-interface`）
- [ ] 重启后直接进入游戏模式：mihomo 已运行，Steam 商店与下载正常（`systemctl status mihomo` 显示开机即启动）
- [ ] 断网 → 恢复网络后，无需人工干预

## 10. 系统更新后保留

执行一次 SteamOS 系统更新（或切换更新通道后更新）：

- [ ] 更新后 `/var/lib/mihomo/bin/mihomo`、`/etc/systemd/system/mihomo.service`、`/etc/mihomo/config.yaml` 仍然存在
- [ ] mihomo 服务仍为 enabled 并在开机后运行
- [ ] 登录 shell 仍为 zsh，`~/.local/share/bootstrap`、dotfiles 与工具不受影响
- [ ] 如有丢失：记录丢失的内容，评估改用 systemd 的 `/etc/extensions` 或其他持久化方式

## 11. 重复执行与变化检测

```sh
sh ~/.local/share/bootstrap/bootstrap.sh   # 完整重新运行（需要再次输入私钥）
sh ~/.local/share/bootstrap/bootstrap.sh --dotfiles
```

- [ ] 完整重新运行：mihomo 显示「已是 v1.19.33」，配置未变时服务不重启（`systemctl show mihomo -p ActiveEnterTimestamp` 前后一致）
- [ ] `--dotfiles`：不需要私钥，`env.sh` 保留代理设置（「使用环境中的代理」）
- [ ] 仓库更新了模板后完整重新运行：配置变化，服务被重启并生效

## 12. 私钥不残留

```sh
grep -rlsaE 'AGE-SECRET-KEY-1[0-9A-Z]{50,}' ~ /tmp /dev/shm /var/log 2>/dev/null | grep -v '/age-keygen$'
sudo journalctl --no-pager -q | grep -cE 'AGE-SECRET-KEY-1[0-9A-Z]{50,}'
grep -c 'AGE-SECRET-KEY' ~/.local/state/zsh/history ~/.bash_history 2>/dev/null
```

- [ ] 文件与 journal 中都找不到私钥（`age-keygen` 二进制本身含该字符串，已排除）
- [ ] shell 历史中没有私钥（交互输入不会写入历史；若通过 `FNOX_AGE_KEY=… sh …` 传入，注意清理历史）

## 13. 回滚 / 卸载（验证后按需执行）

```sh
sudo systemctl disable --now mihomo
sudo rm -rf /etc/systemd/system/mihomo.service /var/lib/mihomo /etc/mihomo
sudo systemctl daemon-reload
```

- [ ] 卸载后 TUN 网卡消失，网络恢复直连，Steam 正常
- [ ] 再次运行 bootstrap 可以从头部署成功

## 14. 需要回传的信息

- bootstrap 的完整输出（去掉节点信息）
- `journalctl -u mihomo -b` 中与问题相关的部分（注意脱敏）
- `ip -br addr`、`ip rule`、`ip route get <目标>` 的输出
- 第 5～8 节的速度、延迟、连接方式记录（开启 / 关闭 mihomo 对比）

## 15. 已知风险 / 需要重点观察的点

| 风险 | 说明 |
| --- | --- |
| 系统自带软件 | git / curl / zsh 是否自带未核实（D-020）；没有 gcc，nvim 预装会给出 WARNING |
| sudo 密码 | `deck` 默认无密码，需先 `passwd`；部署中多次 sudo 是否只问一次 |
| 系统更新 | `/etc` overlay 与 `/var` 应在更新后保留，未实测 |
| Steam 客户端与 TUN | Steam 不读系统代理，依赖 TUN；游戏模式下的行为未实测 |
| fallback 回退 | 代理与直连都不可用时选第一个（代理，P-036）；直连 Steam 商店是否可用取决于当地网络 |
| 远程串流 | 依赖 `route-exclude-address-set: cn-ip` 让国内 IP 绕过 TUN；经 Steam 中继时中继多在境外 |
| 休眠唤醒 | Deck 频繁休眠，TUN 与路由能否自动恢复 |
| fake-ip 与游戏 | 个别游戏或反作弊可能不适应 fake-ip（198.18.0.0/16），出现时记录游戏名称 |
