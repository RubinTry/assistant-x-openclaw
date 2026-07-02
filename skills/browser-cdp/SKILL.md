---
name: browser-cdp
description: "打开/浏览/操作网页前，先跑 ensure_cdp.sh 确保本地 9222 调试 Chrome 就绪，然后用 browser_navigate / browser_snapshot / browser_click 操作（不要用 browser_cdp）。解决『无法为浏览器引擎建立稳定前台会话 / connection issue』这类 CDP 未连报错。"
metadata:
  openclaw:
    emoji: "🌐"
    os: ["darwin"]
    requires:
      bins: ["curl"]
  allowed-tools:
    - exec
---

# Browser CDP 自检自启（浏览器调试通道）

浏览器操作需要一个**本地 Chrome 实例**在 `127.0.0.1:9222` 上开着调试端口。Chrome 一关端口就没了，
随后操作会报「无法为浏览器引擎建立稳定的前台会话 / connection issue / connection refused」。

**两条铁律：**
1. **任何浏览器操作【之前】，先跑 `ensure_cdp.sh`，退出码 0（`CDP_READY`）才继续。**
2. **就绪后用 `browser_navigate` / `browser_snapshot` / `browser_click` 操作，绝不要用 `browser_cdp`。**

## 0. 用哪个工具（关键，之前一直踩这里）

- ✅ **`browser_navigate`（打开网页）、`browser_snapshot`（读页面）、`browser_click` / `browser_type`（交互）**
  —— 这些是**无条件注册**的标准浏览器工具，会自动连 9222。**这才是正路。**
- ❌ **`browser_cdp`** —— 它只有在网关启动那刻 9222 已活着才注册；否则会被系统**静默改写成
  `browser_type`**，表现为"看似导航实则空转、反复 connection issue"。**别调它。** 想低层 CDP 也先走
  `browser_navigate`，除非主人明确要求裸 CDP。

**绝对禁止（这些正是之前 Chrome 反复被杀、连不上的元凶）：**
- ❌ `pkill "Google Chrome"` / `pkill -9 "Google Chrome"` —— 会连主人的**日常 Chrome 一起杀**。
  只允许精确杀调试实例：`pkill -f -- "--remote-debugging-port=9222"`。
- ❌ 用 `nohup '…Chrome' … &` 或任何 `… &` 从 shell 起 Chrome —— exec 一返回进程被回收，Chrome 秒死。
  启动一律交给 `ensure_cdp.sh`（内部用 `open -na` 脱离 shell 才持久）。
- ❌ 自带的 `chrome-cdp` skill 里教的 `… &` 启动和 `pkill -9 "Google Chrome"` —— **不要照做**，以本 skill 为准。

## 0.5 动态页交互铁律：ref 用完就废 + 提交用 browser_press_key（B站实测）

在 B站首页这类动态页反复失败的**真根因有两条**（CDP 亲验，别再误判为"页面结构诡异"）：

**① ref 会过期——这是头号杀手。** `browser_snapshot` 给的 `@e63` 这类 ref，只对**那一刻**的
快照有效。B站首页搜索框 placeholder 是滚动热搜词（"AG超玩会官方账号"→"救了一万次的你"…几秒一换），
每换一次 a11y 树就重建、旧 ref 立即作废。Jarvis 之前正是**上一轮 snapshot、隔轮才 `browser_type`**，
撞上 `Unknown ref: e63` 而失败。
→ **铁律：`browser_snapshot` 与紧随的 `browser_type`/`browser_click` 必须在同一轮、连续调用，
用最新快照里的 ref；绝不复用上一轮的 ref。** 一旦报 `Unknown ref` / `not found in snapshot`，
不要重试同一个 ref，先重新 `browser_snapshot` 拿新 ref。

**② 工具只认 ref，不认 CSS 选择器/坐标。** `browser_click(ref)`、`browser_type(ref, text)` 的
参数是**快照里的 ref（如 `@e5`）**，传 `.nav-search-btn` 这种 CSS 选择器必然 `not found in snapshot`
（而且 B站那个搜索按钮是无 role 的 `<div>`，本就不进快照）。**提交搜索用 `browser_press_key("Enter")`**
——实测可信 Enter **能正常提交**（早前"Enter 没反应"是脏状态/非可信合成事件导致的误判，已排除）。

**可靠动作序列（搜索类页面通用）：**
1. `browser_navigate <url>`（导航返回的快照即最新，可直接用其 ref，无需再 snapshot）；
2. `browser_type(<搜索框最新ref>, "关键词")`（会先清空再输入，走可信输入，Vue v-model 同步正常）；
3. `browser_press_key("Enter")` 提交（**不要**去点 `.nav-search-btn`，那是 CSS 选择器点不了）；
4. **结果常在新标签页打开**（如 `search.bilibili.com/all?keyword=…`）：别只看原页 URL 没变就判"失败"，
   `browser_snapshot` 刷新 / 切到新标签确认。

> 经验法则：① 每个 ref 当"一次性用品"，snapshot 完立刻用、隔轮作废；② 提交用 `browser_press_key`，
> 不要臆想点某个 CSS 选择器；③ 动作后先确认是否弹了新标签，再判成败。

## 1. 每次必跑：确保 CDP 就绪

```bash
bash "$HOME/.openclaw/workspace/voice-assistant/assistant-x-openclaw/skills/browser-cdp/ensure_cdp.sh"
```

（脚本就在本技能目录下，路径不确定时用 `find ~ -name ensure_cdp.sh -path '*browser-cdp*'` 定位。）

脚本行为（幂等、可反复调）：
1. 检查 `127.0.0.1:9222` 是否已有可用调试 Chrome（校验 `webSocketDebuggerUrl`，不是只看端口通）。
2. 已就绪 → 立即返回 `CDP_READY`，**不重复启动**。
3. 未就绪 → 用 `open -na` 拉起一个独立调试 Chrome（`--user-data-dir=$HOME/.hermes/chrome-debug`），
   然后**阻塞轮询到真就绪**再返回。
4. 退出码：`0`=就绪可用；非 0=启动失败（打印 `CDP_FAILED`）。

**判定：** 看到 `CDP_READY` / 退出码 0 → 继续浏览器操作；否则**中止**，走第 3 节排查，别硬闯。

> 为什么必须脚本 + `open -na`：从 exec 的 shell 里 `nohup '…Chrome' … &` 起的进程是该 shell 的子进程，
> exec 一返回进程组被回收，Chrome 立刻死 → 随后连 9222 必然 connection refused。
> `open -na` 把进程交给 macOS launchservices，脱离 shell，才能持续存活。这是之前反复失败的真根因。

## 2. 前提（已就绪，通常无需管）

jarvis profile 的 `~/.hermes/profiles/jarvis/config.yaml` 里 `cdp_url: http://127.0.0.1:9222`
**已配好**——这是每个 profile 独立的配置。**不要去动 hermes 默认的 `~/.hermes/config.yaml`。**
若哪天发现 profile 的 `cdp_url` 变空，向主人说明、经其确认后再改 profile 配置并重启网关，别擅自动。

## 3. 排查兜底（脚本返回 CDP_FAILED 时）

- `curl -s http://127.0.0.1:9222/json/version` 看返回；无响应=Chrome 没起来。
- `lsof -nP -iTCP:9222 -sTCP:LISTEN` 看端口是否被占/监听。
- 有僵死实例占坑：`pkill -f -- "--remote-debugging-port=9222"` 清掉，再跑一次 `ensure_cdp.sh`
  （只杀调试实例，不动日常 Chrome）。
- 数据目录被锁（profile in use）：已有一个同目录 Chrome 在跑；先跑脚本确认它是否已在 9222 服务，
  是就直接用，别再起第二个。

## 4. 安全规则（强制）

- 只操作**专用调试实例**（`--user-data-dir=$HOME/.hermes/chrome-debug`），绝不拿主人日常
  Chrome 的默认 profile 开调试端口。
- 不自行重启 hermes 网关、不自行改 `config.yaml`——这些先报主人、经批准再动。
- 与 jarvis `TOOLS.md` 的「敏感操作规则」一致：破坏性/不可逆动作先确认。
