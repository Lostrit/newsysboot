# Debian 辅助开发容器

更新时间：2026-11-09。运行在 Linux 主机上，用于环境隔离、实验性开发与验证、临时任务；经 SSH 登录（D-038）。
示例文件：[files/container/Dockerfile.example](../files/container/Dockerfile.example)、
[files/container/compose.example.yaml](../files/container/compose.example.yaml)。

## 1. 原则：容器内不落盘任何机密

- 服务使用的机密一律在运行时注入：环境变量、docker secrets，或经管道写入内存。
- 不写进镜像，不写进容器的可写层，也不写进卷。
- 所以容器中不装 fnox、age、gh（`lib/tool-roles.txt`）。
- claude CLI 不要在容器中 `claude login`，登录凭据会写进 `~/.local/share/claude`。改用环境变量注入 `CLAUDE_CODE_OAUTH_TOKEN`（由 `claude setup-token` 生成）或 `ANTHROPIC_API_KEY`。
- git 推送用 SSH agent 转发（`ssh -A`），私钥留在客户端。

## 2. bootstrap 在容器中做的事

| 项目 | 内容 |
| --- | --- |
| 软件包 | Debian 模块的全部软件包，另加 openssh-server、locales、tzdata、procps、iproute2 |
| locale / 时区 | 生成 zh_CN.UTF-8 与 en_US.UTF-8，`/etc/default/locale` 设为 `LANG=zh_CN.UTF-8`、`LANGUAGE=zh_CN:en_US`；`/etc/localtime` 指向 `Asia/Shanghai` |
| SSH 主机密钥 | **删除** openssh-server 安装时生成的 `/etc/ssh/ssh_host_*`。留在镜像层里，就等于所有容器共用、并随镜像分发 |
| sshd 配置 | `/etc/ssh/sshd_config.d/00-bootstrap-container.conf`：主机私钥在 `/dev/shm/bootstrap-sshd/`，授权公钥在 `/etc/ssh/bootstrap_authorized_keys`，禁止密码登录与 root 登录 |
| 入口 | `/usr/local/bin/bootstrap-sshd`（`files/container/bootstrap-sshd.sh`） |
| 代理 | **不写进** `~/.local/state/bootstrap/env.sh`（P-055）。构建时用的代理只在构建中生效；运行时用编排注入的代理（compose 的 `environment`）。运行时有代理时，env.sh 只把本机、云内网镜像与 GitHub 加速代理补进 `no_proxy` |

镜像的 `ENV` 由 Dockerfile 负责，bootstrap 改不了它。示例中设置了 `LANG`、`LANGUAGE`、`TZ`，`docker exec` 直接运行的命令也能用上。

### 代理：构建时与运行时分开

- **构建**：示例用 `docker build --network host --build-arg http_proxy=http://127.0.0.1:7890 …`，构建容器在宿主机网络中，直接用宿主机的 mihomo。
  `http_proxy` 等是 Docker 预定义的构建参数，不会进入镜像的 `ENV`；bootstrap 在容器中也不把检测到的代理写进 env.sh。
- **运行**：容器在自己的网络中，`127.0.0.1:7890` 不通。代理由 compose 注入 `http://host.docker.internal:7890`（`extra_hosts: host.docker.internal:host-gateway`，
  宿主机 mihomo 的 server 场景默认放行 Docker 网段）。`docker run` 时用 `--add-host host.docker.internal:host-gateway -e http_proxy=… -e https_proxy=…`。
- 2026-11-09 之前构建的镜像会把构建时的 `127.0.0.1:7890` 写进 env.sh，覆盖运行时注入的代理，导致 GitHub、npm 下载失败。需要重新构建镜像；
  或在容器中运行一次 `sh ~/.local/share/bootstrap/bootstrap.sh --dotfiles`，重新生成 env.sh。

## 3. SSH 主机私钥：经 fnox 注入内存

sshd 必须有一把**主机私钥**，用来向客户端证明身份。它和用户认证用的公钥不是一回事，跑 sshd 就一定需要它。

做法：私钥由 fnox 加密保存在 Linux 主机上，容器启动后解密，经管道写入容器的 `/dev/shm`（tmpfs，内存）。全程不落盘。

### 第一次：生成主机密钥并交给 fnox

在 Linux 主机上，compose 文件所在的项目目录中执行。该目录的 `fnox.toml` 已配置 age 提供者，做法同本仓库的 `fnox.toml`：

```sh
d=$(mktemp -d /dev/shm/hostkey.XXXXXX)          # 内存文件系统，不落盘
ssh-keygen -q -t ed25519 -N '' -C devbox -f "$d/key"
fnox set SSH_HOST_KEY --from-file "$d/key" -d 'devbox 容器的 SSH 主机私钥'
cat "$d/key.pub"                                 # 主机公钥：写入各客户端的 known_hosts（见第 5 节）
rm -rf "$d"
```

用 `--from-file` 原样保存。从标准输入读取时，fnox 会去掉末尾的换行。

### 每次容器启动后：注入

```sh
docker compose up -d
fnox get SSH_HOST_KEY | docker compose exec -T -u root dev bootstrap-sshd load-key
```

- `load-key` 校验私钥，写入 `/dev/shm/bootstrap-sshd/ssh_host_ed25519_key`（root，0600）。入口进程等到私钥出现后再启动 sshd。
- 容器重启后 `/dev/shm` 会被清空（实测，R-016），需要重新执行第二条命令。
- 未注入期间 sshd 不启动，`docker exec` 仍可正常使用容器。
- fnox 解密需要 age 私钥，用法与本仓库相同（`FNOX_AGE_KEY` 等）。

### 为什么不用 compose 的 secrets 注入私钥（P-049）

实测（Docker Compose v5.7.0）：

- **环境变量来源**（`secrets: x: environment: VAR`）：Compose 会把明文**复制进容器的可写层**，即主机磁盘上的 `/var/lib/docker/.../run/secrets/x`。权限是 0444，容器内任何用户都能读，并且一直保留到容器删除。
  - 在 `/run/secrets` 挂 tmpfs 只是把文件盖住，明文仍在磁盘上。
  - 非 Swarm 模式不支持 `mode` 设置。
- **文件来源**（`secrets: x: file: …`）：绑定挂载主机上的明文文件。

`bootstrap-sshd` 兼容 `/run/secrets/ssh_host_ed25519_key`，有它时直接使用，但不推荐这种方式。

## 4. 授权公钥：docker secrets

公钥是公开信息，可以落盘。compose 用文件来源的 secret 提供（示例中为 `./authorized_keys`，每行一个公钥，`.gitignore` 已忽略这个文件名）。
`bootstrap-sshd` 启动时把它复制为 `/etc/ssh/bootstrap_authorized_keys`（root，0644）。sshd 的 StrictModes 要求公钥文件所在的各级目录不能被其他用户写入。

## 5. 登录

- 示例只在 Linux 主机本机监听：`127.0.0.1:2222`。
- 从客户端经 Linux 主机跳转登录，客户端 `~/.ssh/config` 写法：

  ```sshconfig
  Host devbox
    HostName 127.0.0.1
    Port 2222
    User dev
    ProxyJump <Linux 主机>
    HostKeyAlias devbox            # known_hosts 中按别名记录主机公钥，不与其他 127.0.0.1:2222 混淆
  ```

- 第 3 节输出的主机公钥写入客户端 `~/.ssh/known_hosts`：`devbox ssh-ed25519 AAAA…`。

## 6. 检查

`tests/run.sh`（在 dev 上运行）部署完成后，会执行 `tests/container/verify.sh`：

- 工具：fnox、age、gh、btop、cnb 不存在，其余工具可用。
- 代理：env.sh 中没有代理变量；运行时注入的代理不被覆盖，`no_proxy` 补上本机与加速代理。
- 系统：procps、iproute2、locale、时区。
- 镜像中没有主机密钥。
- `load-key` 的校验，以及注入后的主机私钥被 sshd 使用。
- 公钥登录成功，root 与密码登录被拒绝。
- 主机私钥只在内存中：全盘搜索不到。
