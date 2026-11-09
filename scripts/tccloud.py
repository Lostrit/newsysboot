#!/usr/bin/env python3
"""scripts/tccloud.py —— 开发用：通过腾讯云 API 重装临时测试主机（轻量应用服务器）并注入 age 私钥（D-032、D-042）

密钥与实例信息：
  TENCENTCLOUD_SECRET_ID / TENCENTCLOUD_SECRET_KEY / TENCENTCLOUD_REGION / INSTANCE_ID / TAT_COMMAND_ID / SSH_PUBKEY_ID
优先从环境变量读取（dev 上：`with-secrets -P tencentcloud -- …`，凭据在 dev 的 fnox 密钥库中）；
环境变量里没有 TENCENTCLOUD_SECRET_ID 时，读取 $TCCLOUD_ENV 指定的 KEY=VALUE 文件（权限 600，不在仓库中）。
本脚本绝不输出密钥；注入私钥的 TAT 命令只执行、不查询其内容（命令中含私钥明文）。
dev（62.234.97.210）是用户的正式开发环境：reset 前检查实例的公网 IP，属于受保护的主机时拒绝执行。

用法：
  tccloud.py status                    # 实例状态、当前镜像、自动化助手（TAT）状态
  tccloud.py blueprints [关键词]        # 公共镜像列表（需要 DescribeBlueprints 权限）
  tccloud.py reset <BlueprintId>       # 重装为指定镜像并绑定 SSH 密钥，等待完成
  tccloud.py inject                    # 执行注入私钥的 TAT 命令（自动化助手未上线时重试）
  tccloud.py call <服务> <Action> [JSON] # 调试：直接调用接口
"""
import datetime
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.request

ENV_FILE = os.environ.get("TCCLOUD_ENV", os.path.expanduser("~/.config/tencentcloud/dev.env"))
ENV_KEYS = ("TENCENTCLOUD_SECRET_ID", "TENCENTCLOUD_SECRET_KEY", "TENCENTCLOUD_REGION", "INSTANCE_ID", "TAT_COMMAND_ID", "SSH_PUBKEY_ID")
# 不允许重装的主机（正式环境）；可用 TCCLOUD_PROTECTED_IPS（空格分隔）追加
PROTECTED_IPS = {"62.234.97.210"} | set(os.environ.get("TCCLOUD_PROTECTED_IPS", "").split())
SERVICES = {"lighthouse": "2020-03-24", "tat": "2020-10-28"}


def load_env():
    if os.environ.get("TENCENTCLOUD_SECRET_ID"):
        cfg = {k: os.environ[k] for k in ENV_KEYS if os.environ.get(k)}
        src = "环境变量"
    else:
        cfg = load_file()
        src = ENV_FILE
    for k in ENV_KEYS[:4]:
        if not cfg.get(k):
            sys.exit(f"tccloud: {src} 中缺少 {k}")
    return cfg


def load_file():
    cfg = {}
    with open(ENV_FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip()
    return cfg


def call(cfg, service, action, params=None):
    """TC3-HMAC-SHA256 签名调用；返回 Response（出错时抛出异常，不包含密钥）"""
    host = f"{service}.tencentcloudapi.com"
    payload = json.dumps(params or {}, separators=(",", ":"))
    ts = int(time.time())
    date = datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).strftime("%Y-%m-%d")
    canonical = "\n".join([
        "POST", "/", "",
        f"content-type:application/json; charset=utf-8\nhost:{host}\nx-tc-action:{action.lower()}\n",
        "content-type;host;x-tc-action",
        hashlib.sha256(payload.encode()).hexdigest(),
    ])
    scope = f"{date}/{service}/tc3_request"
    to_sign = f"TC3-HMAC-SHA256\n{ts}\n{scope}\n{hashlib.sha256(canonical.encode()).hexdigest()}"

    def h(key, msg):
        return hmac.new(key, msg.encode(), hashlib.sha256).digest()

    k = h(h(h(("TC3" + cfg["TENCENTCLOUD_SECRET_KEY"]).encode(), date), service), "tc3_request")
    sig = hmac.new(k, to_sign.encode(), hashlib.sha256).hexdigest()
    auth = (f"TC3-HMAC-SHA256 Credential={cfg['TENCENTCLOUD_SECRET_ID']}/{scope}, "
            f"SignedHeaders=content-type;host;x-tc-action, Signature={sig}")
    req = urllib.request.Request(f"https://{host}", data=payload.encode(), method="POST", headers={
        "Authorization": auth, "Content-Type": "application/json; charset=utf-8", "Host": host,
        "X-TC-Action": action, "X-TC-Timestamp": str(ts), "X-TC-Version": SERVICES[service],
        "X-TC-Region": cfg["TENCENTCLOUD_REGION"],
    })
    # 不经环境中的代理（腾讯云 API 在国内直连）
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=30) as r:
        resp = json.load(r)["Response"]
    if "Error" in resp:
        raise RuntimeError(f"{service}:{action} 失败：{resp['Error'].get('Code')} {resp['Error'].get('Message')}")
    return resp


def instance(cfg):
    r = call(cfg, "lighthouse", "DescribeInstances", {"InstanceIds": [cfg["INSTANCE_ID"]]})
    return r["InstanceSet"][0]


def cmd_status(cfg):
    i = instance(cfg)
    print(json.dumps({k: i.get(k) for k in (
        "InstanceId", "InstanceName", "InstanceState", "LatestOperation", "LatestOperationState",
        "BlueprintId", "OsName", "PublicAddresses", "LoginSettings", "CPU", "Memory")},
        ensure_ascii=False, indent=2))
    try:
        r = call(cfg, "tat", "DescribeAutomationAgentStatus", {"InstanceIds": [cfg["INSTANCE_ID"]]})
        print("TAT:", json.dumps(r.get("AutomationAgentSet"), ensure_ascii=False))
    except Exception as e:  # noqa: BLE001
        print("TAT:", e)


def cmd_blueprints(cfg, kw=""):
    r = call(cfg, "lighthouse", "DescribeBlueprints", {"Limit": 100, "Filters": [{"Name": "blueprint-type", "Values": ["PURE_OS"]}]})
    for b in r["BlueprintSet"]:
        line = f"{b['BlueprintId']}  {b.get('OsName', '')}  {b.get('BlueprintName', '')}  {b.get('BlueprintState', '')}"
        if kw.lower() in line.lower():
            print(line)


def wait_instance(cfg, timeout=900):
    t0 = time.time()
    while time.time() - t0 < timeout:
        i = instance(cfg)
        state, op = i.get("InstanceState"), i.get("LatestOperationState")
        print(f"tccloud: {int(time.time() - t0)}s  {state}  {i.get('LatestOperation')}={op}", flush=True)
        if state == "RUNNING" and op in ("SUCCESS", None):
            return i
        if op == "FAILED":
            sys.exit(f"tccloud: 操作失败：{i.get('LatestOperation')}")
        time.sleep(15)
    sys.exit("tccloud: 等待超时")


def cmd_reset(cfg, blueprint):
    ips = set(instance(cfg).get("PublicAddresses") or [])
    if ips & PROTECTED_IPS:
        sys.exit(f"tccloud: 拒绝重装：实例的公网 IP {sorted(ips & PROTECTED_IPS)} 是受保护的正式环境（dev），请改用临时测试主机的 INSTANCE_ID")
    params = {"InstanceId": cfg["INSTANCE_ID"], "BlueprintId": blueprint}
    key = cfg.get("SSH_PUBKEY_ID")
    bound = False
    try:
        # 重装时直接绑定 SSH 密钥（不设置密码）
        call(cfg, "lighthouse", "ResetInstance", dict(params, LoginConfiguration={"KeyIds": [key]}) if key else params)
        bound = bool(key)
    except RuntimeError as e:
        if not key or "InvalidParameter" not in str(e):
            raise
        print(f"tccloud: 重装时不能直接绑定密钥（{str(e)[:100]}），改为重装后再绑定", flush=True)
        call(cfg, "lighthouse", "ResetInstance", params)
    print(f"tccloud: 已提交重装：{blueprint}", flush=True)
    time.sleep(20)
    i = wait_instance(cfg)
    if key and not bound:
        call(cfg, "lighthouse", "AssociateInstancesKeyPairs", {"KeyIds": [key], "InstanceIds": [cfg["INSTANCE_ID"]]})
        time.sleep(10)
        i = wait_instance(cfg)
    print(f"tccloud: 重装完成：{i.get('OsName')}（{i.get('BlueprintId')}），密钥：{(i.get('LoginSettings') or {}).get('KeyIds')}")


def cmd_inject(cfg):
    if not cfg.get("TAT_COMMAND_ID"):
        sys.exit("tccloud: 缺少 TAT_COMMAND_ID")
    # 只执行，不查询命令内容（命令中含私钥明文）；结果由调用方经 SSH 检查。
    # 自动化助手（TAT agent）在重装后需要一段时间上线：执行失败时重试（查询助手状态的接口不一定有权限）
    last = None
    for _ in range(40):
        try:
            r = call(cfg, "tat", "InvokeCommand", {"CommandId": cfg["TAT_COMMAND_ID"], "InstanceIds": [cfg["INSTANCE_ID"]]})
            print(f"tccloud: 已执行注入命令（InvocationId={r.get('InvocationId')}）")
            return
        except RuntimeError as e:
            last = e
            print(f"tccloud: 暂时无法执行（{str(e)[:120]}），15 秒后重试…", flush=True)
            time.sleep(15)
    sys.exit(f"tccloud: 注入命令执行失败：{last}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cfg = load_env()
    op, args = sys.argv[1], sys.argv[2:]
    if op == "status":
        cmd_status(cfg)
    elif op == "blueprints":
        cmd_blueprints(cfg, args[0] if args else "")
    elif op == "reset" and args:
        cmd_reset(cfg, args[0])
    elif op == "inject":
        cmd_inject(cfg)
    elif op == "call" and len(args) >= 2:
        print(json.dumps(call(cfg, args[0], args[1], json.loads(args[2]) if len(args) > 2 else {}), ensure_ascii=False, indent=2))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
