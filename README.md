# 语音助手项目 (Voice Assistant)

> **贾维斯（J.A.R.V.I.S.）** – 承载于 OpenClaw 环境的 AI 语音助手，基于 `sherpa‑onnx` 实现唤醒词检测、流式语音识别与 TTS 播放。

***

## 项目概览

- **核心功能**：
  - 唤醒词检测（Keyword Spotting）
  - 实时流式语音识别（中英双语）
  - 文本清理与 TTS 合成
  - 与 OpenClaw Gateway 双向交互（`/v1/chat/completions`）
- **技术栈**：
  - 语音识别：`sherpa‑onnx`（online recognizer）
  - 音频采集：`sounddevice`（采样率 16000 Hz）
  - TTS：本地或 Edge‑TTS（`edge_playback`）
  - 桥接层：`openclaw_bridge.py`（使用 `agent:main:jarvis` 会话键）
- **身份设定**：贾维斯（J.A.R.V.I.S.），托尼·斯塔克的 AI 智能助手兼管家，语气专业、可靠、略带英式绅士风度。

***

## 关键文件 & 代码位置

| 文件                       | 作用                                       | 关键点                                                    |
| ------------------------ | ---------------------------------------- | ------------------------------------------------------ |
| `app/main.py`            | 程序入口，初始化桥接并启动主循环                         | 调用 `OpenClawBridge`、`VoiceAssistant.run()`             |
| `app/assistant.py`       | `VoiceAssistant` 类，管理音频队列、唤醒、退出          | `EXIT_KEYWORDS`、`idle_timeout`、音频回调逻辑                  |
| `app/openclaw_bridge.py` | OpenClaw HTTP 调用封装                       | `_load_token()`、`send_and_wait`、`send_and_wait_stream` |
| `app/tts.py`             | TTS 播放 & 文本清理                            | `_clean_for_tts`（去除 Markdown/Emoji 与长度截断）              |
| `app/model_manager.py`   | 加载 `sherpa‑onnx` 模型、创建 `keyword_spotter` | `sample_rate = 16000`                                  |
| `app/config_manager.py`  | 读取/写入本地 JSON 配置                          | 读取 `~/.openclaw/openclaw.json`（已废弃）                    |

***

## 安全 / 隐私要点

1. **凭证管理**
   - 访问 OpenClaw 必须通过环境变量 `OPENCLAW_GATEWAY_TOKEN` 提供 token，或在 `~/.openclaw/openclaw.json` 中的 `gateway.auth.token`（已标记废弃）读取。
   - **切勿** 将 token 硬编码在源码或提交到 Git。当前实现仅在运行时读取。
2. **网络通信**
   - 默认使用 **HTTP**（本机 127.0.0.1），若部署到远程机器请自行启用 TLS 并相应修改 `OpenClawBridge` 中的 URL 前缀。
3. **数据持久化**
   - 项目不在磁盘上持久化音频或识别文本，仅在内存中短暂缓存，符合最小化数据原则。
4. **退出关键词**
   ```python
   EXIT_KEYWORDS = {"退下", "退下吧", "没事了", "没有了", "结束", "行了", "好了", "你可以退下了"}
   ```
   - 触发后 `VoiceAssistant.stop()` 立即结束主循环并清理资源。
5. **敏感信息泄漏检查**
   - 已通过全项目搜索确认未出现明文 `Bearer`、`Authorization`、`API_KEY` 等敏感字符串。

***

## 性能 / 卡点排查指南

| 症状                             | 可能原因                                    | 排查/解决方案                                                                                                      |
| ------------------------------ | --------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| 唤醒后 TTS 播放完仍 **无法立刻说话**        | TTS 播放线程未及时释放、音频队列未清空                   | 确认 `tts.text_to_speech_play` 为非阻塞（使用 `threading.Thread`），在播放结束回调里调用 `assistant._reset_audio_queue()`         |
| 语音识别出现 **延迟**                  | `sounddevice` blocksize 过大、模型首次加载慢      | 将 `blocksize` 调小（如 512），在程序启动时预先调用一次 `model_manager.initialize()` 进行 warm‑up                                 |
| OpenClaw 请求 **卡顿** 或返回 **403** | Token 未生效、Gateway 未启动、工具列表受限            | 手动 `curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:18789/v1/models` 测试；检查 `openclaw gateway status` |
| TTS 文本被 **截断或乱码**              | `_clean_for_tts` 正则误删合法字符（如 URL 中的 `%`） | 检查正则表达式，必要时加入 `[%]` 等保留字符；确保 `json.dumps(..., ensure_ascii=False)` 使用正确编码                                    |

***

## 环境变量配置

| 环境变量                     | 说明                    | 必填 |
| ------------------------ | --------------------- | -- |
| `OPENCLAW_GATEWAY_TOKEN` | OpenClaw Gateway 认证令牌 | 是  |

**设置示例**（macOS/Linux）:

```bash
export OPENCLAW_GATEWAY_TOKEN=your-token-here
```

（Windows）:

```cmd
set OPENCLAW_GATEWAY_TOKEN=your-token-here
```

或在项目根目录创建 `.env`（复制自 `.env.example`）并填写相应值。

***

## 安装依赖

```bash
pip install sounddevice numpy sherpa-onnx edge-playback requests
```

> 若使用 `venv`，先激活：`source venv/bin/activate`。

***

## 使用方法

1. **下载模型**（放置于 `app/models/`）
   - 关键词检测模型：`sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01`
   - 语音识别模型：`sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20`
2. **启动 OpenClaw Gateway**（确保已安装 OpenClaw CLI）
   ```bash
   openclaw gateway start
   ```
3. **运行语音助手**
   ```bash
   python -m app.main
   ```
   - 也可使用自带脚本 `./run_voice_assistant.sh`（确保可执行）

***

## 自定义唤醒词

编辑 `custom_keywords.txt`（每行一个唤醒词）并重新启动程序即可生效。

***

## 支持的命令示例

- 查询时间：包含 **"时间"** 或 **"几点"** 的语句
- 查询日期：包含 **"日期"** 或 **"几号"** 的语句
- 退出程序：包含 **"退出"**、**"关闭"**、**"停止"** 的语句

***

## 待办事项（Roadmap）

- 零延迟唤醒（低延迟回调 + 双缓冲）
- 自适应采样率（根据硬件自动切换）
- 插件化 TTS（支持 `espeak‑ng`、云端服务）
- 统一日志审计（写入 OpenClaw 审计系统）
- 单元测试覆盖（`pytest`，目标覆盖率 ≥ 80%）

