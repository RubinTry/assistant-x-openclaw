---
name: assistant-lifecycle
description: "执行语音助手生命周期动作：熄灭显示器、锁定屏幕，以及立即或延迟退回待机。"
metadata:
  openclaw:
    os: ["darwin", "win32"]
  allowed-tools:
    - exec
    - terminal
    - python
---

# Assistant Lifecycle

当用户明确要求熄屏、锁屏、退下、进入待机，或把这些动作组合成一个有顺序的流程时，使用本技能。

## 唯一调用入口

无论引擎当前工作目录在哪里，都使用项目的固定工作区路径：

```bash
$HOME/.openclaw/workspace/voice-assistant/assistant-x-openclaw/venv/bin/python $HOME/.openclaw/workspace/voice-assistant/assistant-x-openclaw/scripts/assistant_lifecycle.py display-sleep
$HOME/.openclaw/workspace/voice-assistant/assistant-x-openclaw/venv/bin/python $HOME/.openclaw/workspace/voice-assistant/assistant-x-openclaw/scripts/assistant_lifecycle.py lock-screen
$HOME/.openclaw/workspace/voice-assistant/assistant-x-openclaw/venv/bin/python $HOME/.openclaw/workspace/voice-assistant/assistant-x-openclaw/scripts/assistant_lifecycle.py stand-down --delay-seconds 2
```

不要直接请求 `127.0.0.1:18790`，不要读取、打印或转述认证令牌，也不要用任意 Shell 命令替代以上固定动作。

## 规划规则

- 保留用户指定的动作和顺序，不得把组合任务简化为单独退下。
- “熄屏、锁屏、两秒后退下”应依次调用 `display-sleep`、`lock-screen`、`stand-down --delay-seconds 2`。
- 用户对这些固定本地动作的明确命令已经构成授权，不要再次询问审批。
- 语义不明确时先问一句；普通问候、感谢、赞美或只有唤醒标记都不是退下指令。
- `stand-down` 必须是组合流程的最后一步，因为成功后当前语音会话会进入待机。

## 结果与诚实性

每次调用都会输出一个 JSON 对象。只有进程退出码为 0 且结果包含 `"ok":true` 才算成功。

- 任一步失败，停止依赖它的后续步骤并如实说明失败的动作。
- 不得在失败、超时、401 或没有有效 JSON 结果时声称已经完成。
- 成功退下后无需再尝试追加长回复；简短告别应在执行最后一步前完成，不能提前声称动作已完成。
