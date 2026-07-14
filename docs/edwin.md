# Edwin 内置 Agent 引擎

Edwin 是本项目自带的进程内 Agent Runtime。它直接运行在语音助手 Python 进程中，不需要 OpenClaw Gateway、Hermes Gateway 或 OpenJarvis。

## 启用与模型配置

`assistants.json`：

```json
{
  "engine": "edwin"
}
```

Control Center 的“模型路由”页面包含两个独立槽位：

- **快速路由**：处理闲聊和轻量问题，并把重任务升级给主脑；
- **Edwin**：执行多轮工具调用。

两个槽位可以使用同一个模型条目。Edwin 模型必须提供 OpenAI-compatible Chat Completions 和原生 tool calling；`openai-codex` CLI 类型不能用于 Edwin。模型 API Key 继续由现有模型表加密保存。

## 运行结构

Edwin 为每个 Assistant 建立独立会话，将数据保存到 `data/edwin/edwin.db`。会话静默 30 分钟后滚动；`/clear` 只让当前会话消息失效，不删除工具审计记录。

内置工具包括：

- 文件列表、读取、搜索和受控写入；
- 非交互 Shell（禁止 sudo）；
- 实时网页搜索和 Chrome CDP 浏览；
- 内置 macOS 截屏与 Vision OCR；Peekaboo 仅作为高级桌面控制的可选增强；
- 时间、计算和系统信息。

读取屏幕时产生的截图由 Edwin 放在系统临时目录，并在工具返回结构化结果后立即删除；
异常和取消路径同样清理。用户明确指定保存路径的文件不属于临时文件，会按要求保留。

Python 依赖统一由根目录 `requirements.txt` 安装，其中技能执行路径使用
`openai`、`requests` 和 `websocket-client`。SQLite、JSON、线程、子进程等来自
Python 标准库，不需要额外安装。

两个现有 Skill 还依赖系统命令而非 pip 包：`browser-cdp` 需要系统 `curl` 和
Google Chrome；`desktop-control` 在 macOS 需要 `peekaboo`。缺少系统命令时 Skill
预检会标记不可用或由工具返回明确错误，不会导致 Edwin 主进程退出。

Edwin 会读取项目 `skills/*/SKILL.md` 的说明、平台限制和允许工具。Skill 只提供提示与约束，不能加载任意可执行代码。

## 权限与语音审批

工具分为 `read`、`write`、`external`、`destructive` 和 `privileged`：

- 读取和观察可自动执行；
- 普通可逆修改只在用户任务明确要求时执行；
- 浏览器点击、桌面控制和 Shell 等高影响动作逐次要求语音确认；
- sudo 和系统提权操作始终拒绝自动执行。

审批绑定当前 request、tool call 和参数摘要，只能使用一次。参数变化、拒绝、取消、清空或角色切换都会使审批失效。回答含糊时 Edwin 只追问一次，仍不明确就拒绝执行。

## 中断与回滚

- 普通语音打断是 soft stop：停止 TTS 输出，但允许后台任务自然结束；
- 明确“取消任务”是 hard cancel：设置当前请求取消令牌并阻止后续工具；
- 每轮按 request ID 隔离，旧请求收尾不会清理新请求状态。

需要回滚外部主脑时，只修改 `assistants.json`：

```json
{"engine": "hermes"}
```

或：

```json
{"engine": "openclaw"}
```

Edwin 不会导入、覆盖或删除这两种引擎原有的会话和记忆。
