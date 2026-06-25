#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Hermes 多角色网关确保脚本（方案 B：一角色一 profile 一网关）。
仅在 assistants.json 顶层 engine=hermes 时由 start.sh 调用。

约定：profile 由用户亲自创建并配置（含启用 API Server）。本脚本不创建、
不改 profile、不碰 SOUL，只做「可达就用，没起就帮起」：

  对每个启用角色（profile 名 = agent_id）：
    1. profile 不存在            → 报错，提示用户先创建该 agent，退出非零。
    2. profile 未启用 API Server → 报错（缺 API_SERVER_PORT/KEY），退出非零。
    3. 网关已在监听该端口        → 复用。
    4. 未在跑                    → 读其 .env 的端口/key，后台 gateway run + 健康检查。

本脚本拉起的网关 pid 写入 <PROJECT>/.hermes_gateways.pids，供 start.sh 退出时清理。
任一角色网关不可达则以非零码退出。所有日志走 stderr。
"""

import json
import os
import subprocess
import sys
import time
import shutil
import urllib.request

HOST = "127.0.0.1"
HERMES_HOME = os.path.expanduser("~/.hermes")
PROFILES_DIR = os.path.join(HERMES_HOME, "profiles")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
ASSISTANTS_JSON = os.path.join(PROJECT_DIR, "assistants.json")
PIDS_FILE = os.path.join(PROJECT_DIR, ".hermes_gateways.pids")


def log(*a):
    print("[hermes-gateways]", *a, file=sys.stderr, flush=True)


def hermes_bin():
    return shutil.which("hermes") or os.path.expanduser("~/.local/bin/hermes")


def profile_dir(profile):
    return os.path.join(PROFILES_DIR, profile)


def penv(profile):
    return os.path.join(profile_dir(profile), ".env")


def health_ok(port, timeout=2):
    try:
        with urllib.request.urlopen(f"http://{HOST}:{port}/health", timeout=timeout) as r:
            return r.status == 200
    except Exception:
        return False


def read_env(path):
    d = {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return d


def ensure_gateway_running(profile, port):
    if health_ok(port):
        log(f"  '{profile}' 网关已在 :{port} 运行，复用")
        return None, True
    gw_log = os.path.join(profile_dir(profile), "voice_gateway.log")
    log(f"  '{profile}' 网关未在跑，后台启动 (:{port}, 日志 {gw_log}) …")
    env = dict(os.environ)
    env["HERMES_ACCEPT_HOOKS"] = "1"
    logf = open(gw_log, "ab")
    proc = subprocess.Popen(
        [hermes_bin(), "-p", profile, "gateway", "run", "--accept-hooks"],
        stdout=logf, stderr=logf, start_new_session=True, env=env,
    )
    with open(os.path.join(profile_dir(profile), ".voice_gateway.pid"), "w") as f:
        f.write(str(proc.pid))
    for _ in range(40):
        if health_ok(port):
            log(f"  '{profile}' 网关就绪 (pid={proc.pid})")
            return proc.pid, True
        if proc.poll() is not None:
            log(f"  '{profile}' 网关进程提前退出 (code={proc.returncode})，详见 {gw_log}")
            return None, False
        time.sleep(1)
    log(f"  '{profile}' 网关健康检查超时（40s）")
    return proc.pid, False


def load_enabled_roles():
    with open(ASSISTANTS_JSON, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    engine = (cfg.get("engine") or "openclaw").strip().lower()
    roles = [
        a["id"].replace("-", "_")           # profile 名 = agent_id
        for a in cfg.get("assistants", [])
        if a.get("enabled") and a.get("id")
    ]
    return engine, roles


def main():
    engine, roles = load_enabled_roles()
    if engine != "hermes":
        return 0  # 非 hermes：静默 no-op
    if not (shutil.which("hermes") or os.path.exists(hermes_bin())):
        log("未找到 hermes 可执行文件，无法启动角色网关")
        return 1
    if not roles:
        log("assistants.json 中没有启用的角色")
        return 1

    managed_pids, all_ok = [], True
    for profile in roles:
        if not os.path.isdir(profile_dir(profile)):
            log(f"  角色 '{profile}' 的 Hermes agent 不存在。"
                f"请先创建：hermes profile create {profile}")
            all_ok = False
            continue
        env = read_env(penv(profile))
        port, key = env.get("API_SERVER_PORT"), env.get("API_SERVER_KEY")
        if not (port and port.isdigit() and key):
            log(f"  角色 '{profile}' 未启用 API Server（缺 API_SERVER_PORT/KEY）。"
                f"请在该 profile 的 .env 设置 API_SERVER_ENABLED=true、API_SERVER_PORT、API_SERVER_KEY")
            all_ok = False
            continue
        pid, ok = ensure_gateway_running(profile, int(port))
        if pid:
            managed_pids.append(pid)
        if not ok:
            all_ok = False

    with open(PIDS_FILE, "w") as f:
        f.write("\n".join(str(p) for p in managed_pids))

    if not all_ok:
        log("部分角色网关未就绪，请按上述提示处理后重试")
        return 1
    log(f"全部 {len(roles)} 个角色网关就绪: {', '.join(roles)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
