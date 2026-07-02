#!/usr/bin/env bash
# ensure_cdp.sh —— 确保本地 9222 上有一个「可用的」调试 Chrome，供 browser_cdp 连接。
#
# 用法：browser-cdp 技能在任何浏览器操作【之前】必须先跑本脚本，
#       只有它退出码为 0（打印 CDP_READY）才继续，否则中止并排查。
#
# 设计要点：
#   - 幂等：9222 已就绪 → 秒退，不重复启动（避免堆积多个实例）。
#   - 启动必须用 `open -na`，绝不能 `nohup … &`：后者是调用 shell 的子进程，
#     shell/exec 一返回就被回收，Chrome 立刻死 → 随后连 9222 必然 connection refused。
#     `open -na` 把进程交给 macOS launchservices，脱离 shell，才能持续存活。
#   - 阻塞等待到真正就绪（校验 webSocketDebuggerUrl，而非仅端口通）再返回。
#
# 退出码：0 = CDP 就绪可用；非 0 = 启动失败。
#
# 输出约定（同时兼容"手动跑"和"作为 hermes pre_tool_call 钩子跑"）：
#   - 所有人类可读信息一律走 stderr（终端/日志可见）。
#   - stdout 仅在「失败」时输出一个 JSON block 指令，让 hermes 拦下浏览器工具并给出明确原因；
#     成功时 stdout 保持为空（非 block → 工具照常放行，且不触发 hooks doctor 的 JSON 警告）。
set -u

CDP_PORT=9222
CDP_VER_URL="http://127.0.0.1:${CDP_PORT}/json/version"
USER_DATA_DIR="$HOME/.hermes/chrome-debug"
CHROME_APP="Google Chrome"

# 「真就绪」= /json/version 能返回且带 webSocketDebuggerUrl（浏览器端点已可被 CDP 接管）
is_ready() {
  curl -s --max-time 2 "$CDP_VER_URL" 2>/dev/null | grep -q 'webSocketDebuggerUrl'
}

if is_ready; then
  echo "CDP_READY (already up)" >&2
  exit 0
fi

echo "CDP down — 启动调试 Chrome ..." >&2
open -na "$CHROME_APP" --args \
  --remote-debugging-port="${CDP_PORT}" \
  --remote-allow-origins='*' \
  --user-data-dir="$USER_DATA_DIR" \
  --no-first-run --no-default-browser-check about:blank

# 冷启动要几秒，轮询等待（最多 ~20s）
for i in $(seq 1 20); do
  if is_ready; then
    echo "CDP_READY (started in ${i}s)" >&2
    exit 0
  fi
  sleep 1
done

echo "CDP_FAILED —— 9222 在 20s 内仍未就绪（Chrome 是否被杀 / user-data-dir 是否被锁）" >&2
# 失败时向 stdout 输出 block 指令，让 hermes 拦下浏览器工具并把原因回给 jarvis
echo '{"action":"block","message":"调试 Chrome(9222/CDP) 未能就绪，已尝试启动但 20s 内未连通。请人工检查后重试；勿反复重试浏览器工具。"}'
exit 1
