---
name: desktop-control
description: "使用 Edwin 的桌面工具读取和控制 macOS：截屏、读取界面文字、定位 UI 元素、点击、输入、热键、拖拽和管理窗口。"
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

## 0. 权限由工具主动申请

不要在回复中预先要求主人配置录屏、辅助功能或 OpenClaw Bridge，也不要只给授权教程。
读取当前屏幕时直接调用内置 `read_screen`；它通过 Pillow + macOS Vision 完成本地截屏和
OCR，不依赖 Peekaboo。其他观察或控制任务调用 `desktop_observe` 或 `desktop_control`，
后两者将 Peekaboo 作为可选高级后端。Edwin 工具会检查权限并主动触发 macOS 系统授权；必要时会
打开对应的系统设置页面。只有工具明确返回系统请求已发起后，才简短请主人批准系统弹窗，
获批后再次调用原工具。

Edwin 不依赖 OpenClaw、Claude 或其他 GUI Bridge。
没有明确指定保存路径的 `see/image` 截图由 Edwin 作为临时文件管理；读取出结构化结果后，
无论成功、失败还是取消都会立即删除。只有主人明确要求保存截图或指定 `--path` 时才保留。

## 1. 操作循环：先看清，再动手

1. **看**：优先调用内置 `read_screen`，它会返回带归一化 `[x=...,y=...]` 中心坐标的 OCR 行，**不要盲点坐标**。
2. **定位**：用元素查询或坐标锁定目标。
3. **动作**：普通点击优先调用内置 `click_screen`；复杂语义操作才使用可选 Peekaboo 后端。
4. **复核**：动作后再 `image` 一次确认结果（导航、提交、弹窗后尤其要重看）。

## 2. 常用命令速查

观察
- `peekaboo image` — 截屏（整屏 / 指定 window / 菜单栏区域）
- `peekaboo see` — 截屏并返回可交互 UI 元素与文字，读取屏幕内容时优先使用
- `peekaboo inspect-ui` — 读取前台 App 的辅助功能树文本
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

## 3. 兜底

若 Peekaboo 本地模式执行失败且不是等待系统授权，可降级用系统自带工具（能力弱，**只能按坐标**，无 UI 元素语义）：

- 截屏：`screencapture -x /tmp/shot.png`（已装）
- 鼠标键盘：`cliclick`（已装，`/opt/homebrew/bin/cliclick`）
  - 点击：`cliclick c:800,450`
  - 输入：`cliclick t:"hello"`
  - 按键：`cliclick kp:return`

降级模式没有元素定位，全靠先 `screencapture` 看图再估算坐标，准确率低，仅应急。

## 4. 安全规则（强制）

- 用户明确要求的播放、暂停、选择、导航等普通本地点击已经获得授权，不要重复确认。删除、清空、发送消息/邮件、提交表单、购买、移动/覆盖文件、退出未保存应用等高影响操作必须逐次确认。
- 不自行提权（sudo）。需要提权的，把命令交给主人自己执行。
- 操作完成后用截屏或 `list` 复核，确认"目标状态真的达成"，不要只凭命令返回的 success 就当成功。
- 与 jarvis `TOOLS.md` 的「敏感操作规则」一致。
