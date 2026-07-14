# Overlay 特效接入 API

本文只描述语音助手与桌面特效之间的通信协议。开发者可以修改现有 Flutter Overlay，也可以用任意语言实现自己的特效程序。

## 1. 通信方式

当前特效接口不是 HTTP 或 WebSocket，而是本机 TCP。

| 项目 | 值 |
| --- | --- |
| 地址 | `127.0.0.1` |
| 端口 | `17889` |
| 编码 | UTF-8 |
| 消息边界 | 每条消息以 `\n` 结束 |
| 方向 | Python 语音助手 → Overlay |
| 连接方式 | 长连接；Python 断线后自动重连 |

Overlay 应只监听 loopback，不要监听 `0.0.0.0`。

## 2. 程序名称与自动扫描

若希望控制中心能够自动启动、停止和清理自定义特效，建议保留项目的标准程序名。

### macOS

启动脚本按以下顺序查找：

```text
assistant_overlay/build/macos/Build/Products/Debug/assistant_overlay.app
assistant_overlay/build/macos/Build/Products/Release/assistant_overlay.app
/Applications/assistant_overlay.app
```

因此安装版 App Bundle 必须命名为：

```text
assistant_overlay.app
```

如果改成其他名称，必须同步修改 `scripts/start.sh` （不推荐）中的 `DEBUG_APP`、`RELEASE_APP`、`SYSTEM_APP`，以及控制中心 macOS 服务中的 Overlay 结束规则，否则控制中心无法完整管理该进程。

### Windows

启动脚本会扫描开始菜单应用，显示名只要包含以下任意关键字即可被发现：

```text
overlay
jarvis
Assistants
```

匹配不区分大小写，并启动第一个结果。为避免误启动其他应用，推荐保持安装显示名：

```text
Assistants-Overlay
```

停止和清理流程按固定进程名结束：

```text
assistant_overlay.exe
```

因此只修改开始菜单显示名可能仍能启动，但修改可执行文件名会导致控制中心无法正常停止它。自定义打包时最好同时保留 `Assistants-Overlay` 和 `assistant_overlay.exe`。

### Linux

当前 Linux 控制中心服务尚未实现自动启动和扫描。Linux 特效需自行启动，仍按 `127.0.0.1:17889` 接收协议。

## 3. 命令 API

Python 主程序的状态机是协议权威。当前正式命令如下。

### `agent:<id>`

切换当前显示的 Assistant 特效。

```text
agent:jarvis
agent:lin-meimei
```

- `<id>` 与 `assistants.json` 中的 Assistant `id` 一致；
- 未知 ID 应被忽略，不要导致 Overlay 崩溃；
- 该命令只负责切换，通常下一条命令是 `wake`。

### `wake`

Assistant 通过唤醒词和身份验证后发送。Overlay 应显示当前角色并播放入场动画。

```text
wake
```

`wake` 必须幂等。当前调度器还会忽略 1.5 秒内的重复 `wake`。

### `user:<text>`

更新用户语音识别文本。

```text
user:今天天气
user:今天天气怎么样
```

Python 发送的是截至当前的完整累计文本，不是新增 token。第二条应覆盖更新第一条，不应重复追加成两条消息。

空文本表示清空用户文本：

```text
user:
```

正文中的换行会被 Python 替换为空格，因此一条命令始终占一行。

### `reset_scale`

表示用户本轮讲话结束，最终指令即将提交给主脑。

```text
reset_scale
```

现有 JARVIS 特效用它结束“用户正在讲话”的放大动画。自定义特效不必实现缩放，但应把它视为从用户讲话态回到常态的通知。

### `ai:<text>`

更新 Assistant 的流式回复文本。

```text
ai:上海今天
ai:上海今天多云，气温 34°C。
```

与 `user:` 相同，Python 发送的是完整累计文本。接收端应覆盖更新当前回复。

空文本表示清空 AI 文本：

```text
ai:
```

### `hide`

Assistant 退下或连续对话超时时发送。Overlay 应清理临时状态并播放退场动画。角色切换时，现有 Flutter 调度器也会在内部向旧角色派发同一命令。

```text
hide
```

`hide` 必须幂等；重复接收不得报错。

## 4. 标准事件顺序

### 唤醒并完成一轮对话

```text
agent:jarvis
wake
user:帮我查一下
user:帮我查一下上海天气
reset_scale
ai:上海今天多云
ai:上海今天多云，最高气温 34°C。
```

### 退下

```text
user:
ai:
hide
```

### 切换 Assistant

```text
agent:lin-meimei
wake
```

收到 `agent:<id>` 时，现有调度器会先向旧角色派发 `hide`，再切换当前角色；随后的 `wake` 负责显示新角色。

## 5. 接入现有 Python 客户端

新 Assistant 使用相同 TCP 协议时，可在 `assistants.json` 中选择通用 Visual：

```json
{
  "id": "my-assistant",
  "components": {
    "visual": "custom"
  },
  "visual_config": {
    "agent_id": "my-assistant",
    "host": "127.0.0.1",
    "port": 17889
  }
}
```

`agent_id` 必须与 Overlay 注册的角色 ID 完全一致。

若第三方特效程序直接实现本协议，则不限制语言或 UI 框架；只需监听 TCP 端口并处理上述命令。

## 6. 最小服务端示例

以下 Python 示例仅用于说明协议，不需要集成进项目：

```python
import socket

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 17889))
server.listen()

while True:
    connection, _ = server.accept()
    buffer = b""
    with connection:
        while chunk := connection.recv(4096):
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                command = line.decode("utf-8", errors="replace").strip()
                if command:
                    print(command)
```

接收端必须维护缓冲区后再按换行拆包，不能假定一次 `recv()` 恰好对应一条命令。

## 7. 手工测试

启动 Overlay 后，可直接发送一轮测试命令：

```bash
printf 'agent:jarvis\nwake\nuser:测试输入\nreset_scale\nai:测试回复\n' \
  | nc -w 1 127.0.0.1 17889
```

隐藏特效：

```bash
printf 'user:\nai:\nhide\n' | nc -w 1 127.0.0.1 17889
```

接入完成后至少验证：

1. 重复 `wake` 和 `hide` 不报错；
2. `user:` / `ai:` 累计文本不会重复入历史；
3. 空 `user:` / `ai:` 能清空文本；
4. 中文、英文、冒号和长文本可正常显示；
5. TCP 断开后，Python 重连时 Overlay 仍可继续接收命令。
