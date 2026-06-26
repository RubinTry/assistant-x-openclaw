# Assistant-X · Hermes 主脑引擎

> 本文是 [README.md](./README.md) 的配套说明，只讲 **engine = hermes** 这条链路。
> 唤醒、ASR/TTS、连续对话、声纹、HUD 等通用部分与 README 一致，不再重复。

默认主脑引擎是 **OpenClaw**（走 OpenClaw Gateway）。如果你想让本地的 **Hermes** 来当大脑，
按本文切换即可。两者只是“主脑引擎”不同，语音识别/合成仍全程本地。

---

## 一、什么是 Hermes 模式

采用 **方案 B：一角色一 profile 一网关**：

- 每个角色 = 一个独立 Hermes profile（独立 `HERMES_HOME`，即独立的记忆 / 会话 / 技能 / `state.db`）。
  角色之间的长期记忆**物理隔离**，不会串。
- profile 默认在 `~/.hermes/profiles/<agent_id>/`（可用环境变量 `HERMES_HOME` 改根目录）。
- 每个角色各自跑一个 Hermes 网关、占一个端口。
- 桥接层（`src/hermes_bridge.py`）按 `agent_id` 定位 profile，从其 `.env` 读取
  `API_SERVER_PORT` / `API_SERVER_KEY` 自解析端点，**无需额外环境变量**。
- 多轮连续对话靠稳定的 `X-Hermes-Session-Id`（profile 内单一会话，天然隔离）。

> `agent_id` 就是 `assistants.json` 里角色的 `id` 字段，与 OpenClaw 版语义一致。

---

## 二、启用方式

在 `assistants.json` **顶层**把 `engine` 设为 `hermes`：

```json
{
    "engine_comment": "主脑引擎，可选值：openclaw（默认）、hermes",
    "engine": "hermes",
    "default": "jarvis",
    "assistants": [ ... ]
}
```

- `engine` 缺省或填了未知值时回退 **openclaw**。
- 改完重启 `./scripts/start.sh` 生效，启动日志会打印 `[引擎] 主脑：Hermes（一角色一 profile 一网关）`。

---

## 三、启动与网关自愈

`engine=hermes` 时，`scripts/start.sh` 会在拉起语音助手前自动校验/拉起各角色网关：

```bash
./scripts/start.sh
# [引擎] hermes：校验各角色网关…
# [引擎] hermes：角色网关就绪
```

- 自愈逻辑在 `scripts/hermes_provision.py`，由 start.sh 调用；网关 PID 记录在 `.hermes_gateways.pids`，退出时统一清理。
- 若提示 `角色网关自愈失败`，先检查：Hermes 是否装好、对应 profile 是否存在、模型凭证是否配齐。

**前置条件**：每个启用的角色都要有对应的 Hermes profile（`~/.hermes/profiles/<agent_id>/`），
且其 `.env` 含可用的 `API_SERVER_PORT` / `API_SERVER_KEY`。

---

## 四、唤醒问候协议（voice-assistant-wake-up）

> 这是 Hermes 链路上一个需要**角色 prompt 配合**的约定，OpenClaw 模式同样适用。

被唤醒后，语音助手**不再播放固定欢迎语**，而是自动给主脑引擎发送一条消息：

```
voice-assistant-wake-up-<本地时间戳>
# 例：voice-assistant-wake-up-2026-06-26 19:07:52
```

- 时间戳由 Python 端在发送前直接读取**本地时间**（`%Y-%m-%d %H:%M:%S`），
  规避 Hermes 自行取时常出错的问题——需要“当前时间”时直接用这条里的即可。
- 引擎返回的内容即作为问候语经 TTS 播报；等待引擎回复期间**不识别用户语音**。

**因此请在角色的 system prompt / 技能里加一条规则**：当收到 `voice-assistant-wake-up-*`
开头的消息时，识别为“被用户唤醒”，回一句简短得体的问候（可参考消息里的时间问早/午/晚安），
而不要把这串字面当普通用户输入来回应。

---

## 五、与 OpenClaw 版差异速查

| 维度 | OpenClaw（默认） | Hermes |
|---|---|---|
| `assistants.json` 顶层 `engine` | `openclaw` 或缺省 | `hermes` |
| 大模型接入 | OpenClaw Gateway | 各角色独立 Hermes 网关 |
| 记忆/会话隔离 | 由 OpenClaw 侧管理 | 一角色一 profile，物理隔离 |
| 桥接模块 | `src/openclaw_bridge_websocket.py` | `src/hermes_bridge.py` |
| 启动额外步骤 | 无 | start.sh 自动 provision 各角色网关 |
| 端点配置 | 网关地址 | 从 `~/.hermes/profiles/<id>/.env` 自解析 |

---

## 六、排错

- **启动报“角色网关自愈失败”**：Hermes 未装好 / profile 缺失 / 模型凭证未配。先单独跑
  `python scripts/hermes_provision.py` 看详细报错。
- **唤醒后问候很怪 / 把 `voice-assistant-wake-up-...` 念出来**：角色 prompt 没加唤醒消息应答规则，见第四节。
- **多个角色记忆串了**：确认每个角色用的是**各自独立**的 profile 目录（`agent_id` 不同）。
- **想切回 OpenClaw**：把 `engine` 改回 `openclaw`（或删掉该字段）重启即可。
