# JARVIS 语音助手

基于 sherpa-onnx 的本地语音助手，通过 OpenClaw Gateway 与 LLM 对话，以 JARVIS 风格进行语音交互。支持语音唤醒、连续对话、实时 TTS 播报和 HUD 视觉特效。

<iframe src="//player.bilibili.com/player.html?isOutside=true&aid=116367223230904&bvid=BV1uQDrB4EqT&cid=37328389365&p=1" scrolling="no" border="0" frameborder="no" framespacing="0" allowfullscreen="false"></iframe>

## 目录结构

```
jarvis-x-openclaw/
├── src/                    # Python 源代码
│   ├── main.py             # 主程序：语音唤醒 + 流式识别 + 对话流程
│   ├── tts.py              # TTS 模块：统一接口，优先使用本地合成
│   ├── sherpa_onnx_tts.py  # Sherpa-onnx TTS 引擎（ZipVoice 零样本克隆）
│   ├── openclaw_bridge.py  # OpenClaw Gateway 桥接（流式对话）
│   ├── jarvis_feedback.py  # JARVIS 风格音效 + 终端动画 + 桌面通知
│   └── jarvis_visual.py    # JARVIS Overlay 视觉特效通信
├── scripts/
│   ├── start.sh            # 启动脚本（macOS）
│   ├── start.bat           # 启动脚本（Windows）
│   ├── restart_voice_assistant.sh  # 重启脚本
│   └── enroll_speaker.py   # 声纹录入工具
├── data/
│   └── voices/             # 音效文件（.wav）+ JARVIS 参考音频（jarvis_start_up.mp3）
├── models/                 # ONNX 模型文件（gitignore）
├── sound_sample/           # 用户声纹样本
├── jarvis_overlay/         # Flutter HUD 特效应用
├── custom_keywords.txt     # 唤醒词配置
├── .env                    # API 密钥等配置
├── requirements.txt        # Python 依赖
└── venv/                   # Python 虚拟环境
```

## 系统架构

```
┌─────────────────────────────────────────────────────┐
│                   JARVIS Overlay (Flutter)          │
│              透明 HUD 窗口，TCP 端口 17889           │
└──────────────────────────┬──────────────────────────┘
                           │ TCP
┌──────────────────────────▼──────────────────────────┐
│                      main.py                          │
│                                                      │
│  ┌─────────────┐   ┌──────────────┐   ┌──────────┐ │
│  │ KWS 唤醒检测 │ → │ ASR 语音识别  │ → │ OpenClaw │ │
│  │ (sherpa-onnx│   │ (流式/离线)  │   │ Gateway  │ │
│  └─────────────┘   └──────────────┘   └────┬─────┘ │
│                                             │        │
│  ┌──────────────────────┐   ┌─────────────▼──────┐ │
│  │ jarvis_feedback       │ ← │ TTS (ZipVoice 克隆)│ │
│  │ 音效 + HUD + 通知       │   │ sherpa-onnx TTS   │ │
│  └──────────────────────┘   └────────────────────┘ │
└─────────────────────────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │ Jarvis.app   │
                    │ (Xcode macOS │
                    │  控制面板)   │
                    └─────────────┘
```

## 核心模块

### main.py — 主程序
- **唤醒词检测**：使用 sherpa-onnx 关键词检测器（KWS），唤醒词在 `custom_keywords.txt` 配置
- **语音识别**：默认流式识别，可选 Qwen3-ASR 离线识别模式（VAD 静音检测）
- **连续对话**：唤醒后进入连续对话模式，支持多轮语音指令，朗读"退出连续对话模式"或超时 30 秒自动退出
- **打断机制**：唤醒词随时可打断当前处理流程
- **API 接口**：`POST http://127.0.0.1:18790/exit` 可远程触发退下

### tts.py — TTS 统一接口
- 优先播放预生成音效（`data/voices/`），找不到则调用本地合成
- 语音合成由 `sherpa_onnx_tts.py` 提供

### sherpa_onnx_tts.py — 本地语音合成
- 使用 **ZipVoice**（sherpa-onnx）零样本声音克隆，以 JARVIS 参考音频合成语音
- 参考音频、模型文件位于 `~/.openclaw/tools/sherpa-onnx-tts/`
- 配置：guidance_scale=1.5，num_steps=8，num_threads=3，provider=cpu

### openclaw_bridge.py — OpenClaw 桥接
- 与本地 Gateway（`http://127.0.0.1:18789`）通信
- 流式传输：实时接收 LLM 回复并逐字回调
- 打断支持：发送 `/stop` 命令取消正在进行的请求

### jarvis_feedback.py — 反馈系统
- 11 种音效：唤醒、处理、成功、错误、退出等
- HUD 终端动画（初始化、退出的逐字显示）
- macOS 桌面通知

### jarvis_visual.py — 视觉特效通信
- 通过 TCP 连接 JARVIS Overlay，发送控制命令：
  - `wake` — 唤醒特效
  - `hide` — 隐藏特效
  - `user:{text}` / `ai:{text}` — 显示对话内容

## 快速开始

### 1. 克隆项目

```bash
mkdir -p ~/.openclaw/workspace/voice-assistant
cd ~/.openclaw/workspace/voice-assistant
git clone <仓库地址>
```

克隆完成后，项目路径为 `~/.openclaw/workspace/voice-assistant/jarvis-x-openclaw/`。

### 2. 安装依赖

在项目根目录下创建虚拟环境并安装依赖：

**macOS / Linux：**

```bash
cd ~/.openclaw/workspace/voice-assistant/jarvis-x-openclaw
python3 -m venv venv
venv/bin/pip install --force-reinstall --no-cache -r requirements.txt
```

**Windows：**

```cmd
cd %USERPROFILE%\.openclaw\workspace\voice-assistant\jarvis-x-openclaw
python -m venv venv
.\venv\Scripts\pip.exe install --force-reinstall --no-cache  -r .\requirements.txt
```

### 3. 配置

复制 `.env.example` 为 `.env`，填入以下配置：

```bash
MINIMAX_API_KEY=your_api_key_here（不想用也可以换别家大模型，变量名记得改）
OPENCLAW_GATEWAY_TOKEN=your_gateway_token
```

同时需要在 `~/.openclaw/openclaw.json` 中确保 Gateway 的 HTTP 端点已启用：

```json
"gateway": {
  "port": 18789,
  "mode": "local",
  "bind": "loopback",
  "auth": {
    "mode": "token",
    "token": "your token"
  },
  "tailscale": {
    "mode": "off",
    "resetOnExit": false
  },
  "http": {
    "endpoints": {
      "chatCompletions": {
        "enabled": true
      }
    }
  }
}
```

### 4. 下载模型文件

本项目使用的模型分为三类，全部放在项目 `models/` 目录下。每个模型下载后需解压（.tar.bz2 文件），并删除压缩包以节省空间。

**KWS 唤醒词模型：**
```bash
cd models/
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2
tar xf sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2
rm sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01.tar.bz2
```

**ASR 语音识别模型：**
```bash
cd models/
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2
tar xf sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2
rm sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2
```

**TTS 模型：**
```bash
# ZipVoice（语音克隆引擎）
cd models/
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-zipvoice-distill-int8-zh-en-emilia.tar.bz2
tar xf sherpa-onnx-zipvoice-distill-int8-zh-en-emilia.tar.bz2
rm sherpa-onnx-zipvoice-distill-int8-zh-en-emilia.tar.bz2

# Vocos vocoder
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/vocoder-models/vocos_24khz.onnx

# JARVIS 参考音频（自定义录音，需命名为 jarvis_start_up.mp3 放入 data/voices/）
# 参考文本为：Allow me to introduce myself I am jarvis, a virtual artificial intelligence
# importing all preferences from home interface systems are now fully operational.
# 请自行录制一段 JARVIS 开场白音频，保存为 data/voices/jarvis_start_up.mp3
```

**VAD 静音检测模型（Qwen3-ASR 离线识别模式用）：**
```bash
cd models/
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad_v5.onnx
mv silero_vad_v5.onnx silero_vad.onnx
```

**Qwen3-ASR 离线识别模型（可选）：**
```bash
# 模型位于 sherpa-onnx-tts 工具包中
# 下载地址：https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models
# 文件名：sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2
```
=======

### 5. 配置唤醒词

编辑 `custom_keywords.txt`，格式：
```
j iǎ w éi s ī :3.0 #0.02 @贾维斯
```
每行：`拼音 @唤醒词`，冒号后为灵敏度，`#` 后为阈值。

### 6. 启动

```bash
./scripts/start.sh
```

脚本会自动：
1. 清理端口 17888/17889 上的旧进程
2. 启动 JARVIS Overlay（Flutter HUD 应用，特效全在这）
3. 启动语音助手主程序

**首次运行前需构建 Overlay**：
```bash
cd jarvis_overlay
flutter build macos --debug    # Debug 版本
# 或
flutter build macos            # Release 版本
```

### 7. 通过 Jarvis.app 管理

项目由 macOS 应用 `Jarvis.app`（位于 `~/xcodeProject/jarvis/`）管理，支持启动、重启、查看状态。代码变更后需在 Xcode 中重新编译。

## 使用方式

1. **唤醒**：说出唤醒词（如"贾维斯"），听到确认音效后进入连续对话
2. **对话**：直接说出指令，助手实时流式响应
3. **打断**：再次说出唤醒词，随时打断当前处理
4. **退出**：说"退出连续对话模式"或 30 秒无活动自动退出

## 命令行参数

```bash
python src/main.py [options]

# 核心参数
--kws-tokens, --kws-encoder, --kws-decoder, --kws-joiner   # 唤醒词模型路径
--keywords-file           # 唤醒词配置文件（默认 custom_keywords.txt）
--keywords-score          # 唤醒词得分阈值（默认 0.15）
--asr-tokens, --asr-encoder, --asr-decoder, --asr-joiner   # ASR 模型路径
--provider                # 推理后端：cpu / coreml（默认 cpu）

# Qwen3-ASR 离线识别模式（可选）
--qwen3-conv-frontend     # Qwen3 卷积前端路径
--qwen3-encoder           # Qwen3 编码器路径
--qwen3-decoder           # Qwen3 解码器路径
--qwen3-tokenizer         # Qwen3 分词器路径
--vad-model               # Silero VAD 模型路径
```

## API

### 远程退下

```bash
curl -X POST http://127.0.0.1:18790/exit
```

## 声纹录入

如需使用声纹验证（可选），运行：

```bash
./scripts/enroll_speaker.py
```

按照提示朗读"贾维斯"即可完成录入，样本保存在 `sound_sample/`。

## 音效文件说明

`data/voices/` 目录包含以下 JARVIS 风格音效：

| 文件 | 用途 |
|------|------|
| wake.wav | 唤醒确认 |
| processing.wav | 处理中（等待音效） |
| thinking.wav | 思考中 |
| execute.wav | 执行指令 |
| success.wav | 操作成功 |
| error.wav | 操作失败 |
| exit.wav | 退出待机 |
| blaster.wav | 特效音效 |
| continue.wav | 继续对话 |
| system_ready.wav | 系统就绪 |
