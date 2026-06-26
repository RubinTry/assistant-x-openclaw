---
name: desktop-control
description: "像 Claude 一样控制 macOS 桌面：截屏、定位 UI 元素、点击、键盘输入、热键、拖拽、管理应用/窗口/菜单。底层复用 Peekaboo CLI，复用 OpenClaw App 的录屏与辅助功能授权。"
metadata:
  openclaw:
    emoji: "🖱️"
    os: ["darwin"]
    requires:
      bins: ["peekaboo"]
    install:
      - id: brew
        kind: brew
        formula: steipete/tap/peekaboo
        bins: ["peekaboo"]
        label: "Install Peekaboo (brew)"
  allowed-tools:
    - exec
    - read
---

# Desktop Control（桌面控制）

当主人要求"看屏幕 / 操作某个 app / 点某个按钮 / 帮我输入 / 打开某窗口"等桌面级操作时使用本技能。
底层是 [Peekaboo](https://peekaboo.boo) —— 一个完整的 macOS UI 自动化 CLI。

## 0. 必须先配 Bridge（关键，否则没授权）

OpenClaw App 已经拿到了「录屏 Screen Recording」和「辅助功能 Accessibility」授权。
让 Peekaboo 复用这套授权，而不是另起独立 daemon：

```bash
export PEEKABOO_BRIDGE_SOCKET="${PEEKABOO_BRIDGE_SOCKET:-$HOME/Library/Application Support/OpenClaw/bridge.sock}"
peekaboo bridge status --json   # hostKind 必须是 gui，socket 路径须以 OpenClaw/bridge.sock 结尾
```

若 `hostKind` 不是 `gui`，先排查 OpenClaw App 是否在运行、是否已授予录屏+辅助功能。

所有命令都支持 `--json` / `-j` 便于脚本解析。不确定参数就 `peekaboo <cmd> --help`。

## 1. 操作循环：先看清，再动手

1. **看**：先用 `image`（截屏）或 `list`（列 apps/windows/screens）搞清当前界面，**不要盲点坐标**。
2. **定位**：用元素查询或坐标锁定目标。
3. **动作**：`click` / `type` / `hotkey` / `paste` / `move` / `drag`。
4. **复核**：动作后再 `image` 一次确认结果（导航、提交、弹窗后尤其要重看）。

## 2. 常用命令速查

观察
- `peekaboo image` — 截屏（整屏 / 指定 window / 菜单栏区域）
- `peekaboo list apps|windows|screens|menubar|permissions` — 枚举
- `peekaboo permissions` — 查录屏/辅助功能状态

交互
- `peekaboo click <ID|query|coords>` — 点击，带智能等待
- `peekaboo type "<文本>"` — 键盘输入
- `peekaboo hotkey cmd,shift,t` — 组合键
- `peekaboo paste` — 设剪贴板→粘贴→还原
- `peekaboo move` — 移动光标
- `peekaboo drag` — 拖拽（元素/坐标/Dock）
- `peekaboo run <脚本.peekaboo.json>` — 批量脚本

应用/窗口/菜单管理见 `peekaboo --help`。

## 3. 兜底：无 GUI Bridge 授权时

若 `peekaboo bridge status` 拿不到 GUI 授权，可降级用系统自带工具（能力弱，**只能按坐标**，无 UI 元素语义）：

- 截屏：`screencapture -x /tmp/shot.png`（已装）
- 鼠标键盘：`cliclick`（已装，`/opt/homebrew/bin/cliclick`）
  - 点击：`cliclick c:800,450`
  - 输入：`cliclick t:"hello"`
  - 按键：`cliclick kp:return`

降级模式没有元素定位，全靠先 `screencapture` 看图再估算坐标，准确率低，仅应急。

## 4. 安全规则（强制）

- **破坏性 / 不可逆操作必须先获主人确认**：删除文件、清空、发送消息/邮件、提交表单、移动/覆盖文件、退出未保存的应用等——先把要做的事说清楚，得到主人批准再执行。
- 不自行提权（sudo）。需要提权的，把命令交给主人自己执行。
- 操作完成后用截屏或 `list` 复核，确认"目标状态真的达成"，不要只凭命令返回的 success 就当成功。
- 与 jarvis `TOOLS.md` 的「敏感操作规则」一致。
