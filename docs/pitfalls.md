# 开发中遇到的坑

格式：现象 / 原因 / 解决。

---

## P-001 `mirrors.tencentcloud.com` 在腾讯云内网无法连接

- **现象**：2026-10-29 在腾讯云 Debian 13 主机上 `curl https://mirrors.tencentcloud.com/` 返回 000（连接失败）。
- **原因**：腾讯云内网镜像的域名是 `mirrors.tencentyun.com`（dotconfig 的 npmrc 用的也是它）；
  `mirrors.tencentcloud.com` 应该是国际站域名（未进一步核实）。
- **解决**：内网用 `https://mirrors.tencentyun.com/docker-ce`，公网用 `https://mirrors.cloud.tencent.com/docker-ce`。

## P-002 开发机器默认没有 git

- **现象**：当前 Debian 13 环境执行 `git` 提示 command not found。
- **解决**：已用 `apt-get install git` 安装。stage-0 也要先处理这种情况：mise 的 `[bootstrap.repos]`、
  zsh 插件、lazy.nvim 都依赖 git。

## P-003 `curl | sh` 时无法交互读取输入

- **预判**：通过管道执行脚本时 stdin 是脚本本身，`read` 读不到用户输入。
- **解决**：交互输入改为从 `/dev/tty` 读取；没有 tty 时（Dockerfile 中）必须通过环境变量传入，否则报错退出。

## P-004 经 GitHub 代理访问私有仓库会泄露 token

- **预判**：`https://<proxy>/https://<token>@github.com/...` 这种写法会把 token 交给第三方代理。
- **解决**：本仓库和 dotconfig 如果要经代理拉取，必须是公开仓库且不含任何密钥；或者托管到国内平台（CNB / Gitee）。
