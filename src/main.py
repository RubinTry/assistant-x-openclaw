#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
语音助手程序 - 基于 sherpa-onnx
语音唤醒 + 流式语音识别
为 OpenClaw 联动预留接口
"""

import argparse
import json
import os
import random
import sys
import time
import threading
import queue
import tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

_assistant_instance = None
PID_FILE = os.path.join(tempfile.gettempdir(), "voice_assistant.pid")
API_PORT = 18790


class _ExitAPIHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/exit":
            if _assistant_instance is not None:
                threading.Thread(
                    target=_assistant_instance.exit_standby, daemon=True
                ).start()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"status": "ok"}).encode())
            else:
                self.send_response(404)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "assistant not ready"}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


def _start_api_server():
    server = HTTPServer(("127.0.0.1", API_PORT), _ExitAPIHandler)
    server.serve_forever()


try:
    import sounddevice as sd
except ImportError:
    print("请先安装 sounddevice：pip install sounddevice")
    sys.exit(1)

try:
    import numpy as np
except ImportError:
    print("请先安装 numpy：pip install numpy")
    sys.exit(1)

try:
    import sherpa_onnx
except ImportError:
    print("请先安装 sherpa-onnx：pip install sherpa-onnx")
    sys.exit(1)

from tts import (
    text_to_speech_play,
    is_tts_playing,
    play_prebuilt_voice,
    stop_tts,
    set_tts,
)
from openclaw_bridge import get_bridge
from assistants import (
    AssistantFeedback,
    AssistantVisual,
    AssistantTTS,
    get_feedback,
    get_visual_effects,
    get_tts,
    AssistantManager,
    AssistantInstance,
    get_manager,
)

# ── assistants.json 配置加载 ─────────────────────────────────
_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ASSISTANTS_CFG_PATH = os.path.join(_PROJECT_DIR, "assistants.json")


def _load_all_assistant_configs() -> tuple[dict, list]:
    """加载所有启用的 assistant 配置

    Returns:
        (default_config, list_of_all_enabled_configs)
    """
    with open(_ASSISTANTS_CFG_PATH, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    default_id = cfg.get("default")
    all_assistants = cfg.get("assistants", [])

    # 过滤启用的 assistant
    enabled_assistants = [a for a in all_assistants if a.get("enabled", True)]

    if not enabled_assistants:
        raise ValueError("assistants.json 中没有启用的 assistant")

    # 找到默认配置
    default_config = None
    for a in enabled_assistants:
        if a["id"] == default_id:
            default_config = a
            break

    # 如果默认不在启用列表中，使用第一个启用的
    if default_config is None:
        default_config = enabled_assistants[0]

    return default_config, enabled_assistants


def _load_assistant_config(assistant_id: str = None) -> dict:
    """从 assistants.json 加载指定 assistant 的配置，返回 dict（兼容旧代码）"""
    with open(_ASSISTANTS_CFG_PATH, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    target_id = assistant_id or cfg.get("default")
    for a in cfg.get("assistants", []):
        if a["id"] == target_id:
            return a
    raise ValueError(f"assistants.json 中未找到 assistant: {target_id}")


# _merge_keywords_files 函数已废弃
# 唤醒词合并逻辑已移至 start.sh 脚本中
# 程序直接使用 global.txt 文件


# ── 运行时变量（由 _apply_assistant_config 填充） ────────────
EXIT_KEYWORDS: set = set()
INSTANT_EXIT_KEYWORDS: set = set()
INSTANT_EXIT_FUZZY: tuple = ()
WAKE_LINES: list = []
EXIT_LINES: list = []


def _apply_assistant_config(cfg: dict):
    """将 assistant 配置写入模块级变量"""
    global EXIT_KEYWORDS, INSTANT_EXIT_KEYWORDS, INSTANT_EXIT_FUZZY
    global WAKE_LINES, EXIT_LINES

    EXIT_KEYWORDS = set(cfg.get("exit_keywords", []))
    EXIT_KEYWORDS.update({"QUIT", "quit", "EXIT", "exit"})
    INSTANT_EXIT_KEYWORDS = set(cfg.get("instant_exit_keywords", []))
    INSTANT_EXIT_FUZZY = tuple(cfg.get("instant_exit_fuzzy", []))
    WAKE_LINES = list(cfg.get("wake_lines", []))
    EXIT_LINES = list(cfg.get("exit_lines", []))


def _is_instant_exit(text: str) -> bool:
    return text in INSTANT_EXIT_KEYWORDS or any(kw in text for kw in INSTANT_EXIT_FUZZY)


# ── 唤醒 / 退出随机话术 ──────────────────────────────────────


def _random_wake_line() -> str:
    return random.choice(WAKE_LINES)


def _random_exit_line() -> str:
    return random.choice(EXIT_LINES)


def _clean_for_tts(text: str) -> str:
    """清理文本，适合 TTS 朗读"""
    import re

    # 去掉 markdown 符号
    text = re.sub(r"[*`#>\-]+", "", text)
    # 去掉 emoji
    text = re.sub(r"[\U0001f300-\U0001f9ff\u2600-\u26ff\u2700-\u27bf]", "", text)
    # 合并多余空白和换行
    text = re.sub(r"\s+", " ", text).strip()
    # 截断过长文本（取前500字符，尽量在句号处截断）
    if len(text) > 500:
        cut = text[:500]
        last_period = max(
            cut.rfind("。"), cut.rfind("！"), cut.rfind("？"), cut.rfind(".")
        )
        if last_period > 100:
            text = cut[: last_period + 1]
        else:
            text = cut + "。"
    return text


class VoiceAssistant:
    def __init__(
        self, args, default_cfg: dict, all_assistants: list, keyword_mapping: dict
    ):
        self.args = args
        self.default_cfg = default_cfg
        self.all_assistants = {a["id"]: a for a in all_assistants}
        self.keyword_mapping = keyword_mapping  # keyword_text -> assistant_id

        # 初始化 assistant manager
        self.assistant_manager = get_manager()

        # 注册所有启用的 assistant
        for cfg in all_assistants:
            assistant_id = cfg["id"]
            self.assistant_manager.register(
                assistant_id,
                cfg,
                sound_enabled=True,
                hud_enabled=True,
                notification_enabled=True,
            )

        # 切换到默认 assistant
        self.current_cfg = default_cfg
        self._switch_assistant(default_cfg["id"])

        self.sample_rate = 16000
        self.is_awake = False
        self.continuous_mode = False
        self.audio_queue = queue.Queue()
        self.stop_event = threading.Event()
        self.last_voice_time = time.time()
        self.idle_timeout = 30
        self.last_activity_time = time.time()
        self._last_tts_check = False

        self._is_openclaw_busy = False
        self._openclaw_request_active = threading.Event()
        self._stop_openclaw_request = threading.Event()
        self._ignore_next_result = False
        self._suppress_recognition_until_tts_done = False
        self._last_interrupt_time = 0  # 记录上次打断时间，用于防止误触发
        self._last_wake_time = 0  # 记录上次唤醒时间，唤醒后保护期内跳过退出检测

        self.keyword_spotter = self._create_keyword_spotter()
        # 始终创建流式识别器（用于连续对话模式）
        self.recognizer = self._create_recognizer()
        
        # 根据 assistant 配置决定使用哪种识别模式
        asr_mode = self.current_cfg.get("asr_mode", "streaming")
        if asr_mode == "sense_voice_en":
            # 使用 SenseVoice 英文模式
            sense_result = self._create_sense_voice_recognizer(language="en")
            if sense_result and sense_result[0] is not None:
                self.offline_recognizer, self.vad_config = sense_result
                self._use_offline_asr = True
                print("[配置] 贾维斯使用 SenseVoice 英文识别模式 (English only)")
            else:
                self._use_offline_asr = False
                print("[配置] SenseVoice 不可用，使用流式识别模式（热词增强）")
        elif asr_mode == "sense_voice":
            # 使用 SenseVoice 自动语言检测
            sense_result = self._create_sense_voice_recognizer(language="auto")
            if sense_result and sense_result[0] is not None:
                self.offline_recognizer, self.vad_config = sense_result
                self._use_offline_asr = True
                print("[配置] 使用 SenseVoice 多语言识别模式")
            else:
                self._use_offline_asr = False
                print("[配置] SenseVoice 不可用，使用流式识别模式（热词增强）")
        elif asr_mode == "offline":
            # 尝试创建 Qwen3-ASR 离线识别器
            offline_result = self._create_offline_recognizer()
            if offline_result and offline_result[0] is not None:
                self.offline_recognizer, self.vad_config, _ = offline_result
                self._use_offline_asr = True
                print("[配置] 使用 Qwen3-ASR 离线识别模式")
            else:
                self._use_offline_asr = False
                print("[配置] Qwen3-ASR 不可用，使用流式识别模式（热词增强）")
        else:
            self._use_offline_asr = False
            print("[配置] 使用流式识别模式（热词增强）")
        
        self._check_microphone()

        # OpenClaw bridge 会在切换 assistant 时动态创建
        self.openclaw = None
        self._init_openclaw()

        print("语音助手初始化完成！")
        print(
            f"已加载 {len(all_assistants)} 个 assistant: {[a['name'] for a in all_assistants]}"
        )
        print(f"唤醒词: {self._get_keywords()}")
        print("正在检测 OpenClaw 连接...")
        print("提示: 说出任意唤醒词即可唤醒对应的 assistant，支持连续对话")

    def _switch_assistant(self, assistant_id: str):
        """切换到指定的 assistant"""
        if assistant_id not in self.all_assistants:
            print(f"[错误] 未知的 assistant: {assistant_id}")
            return False

        # 切换到新的 assistant
        instance = self.assistant_manager.switch_to(assistant_id)
        if not instance:
            return False

        self.current_cfg = self.all_assistants[assistant_id]
        _apply_assistant_config(self.current_cfg)

        # 根据 assistant 配置决定使用哪种识别模式
        asr_mode = self.current_cfg.get("asr_mode", "streaming")
        if asr_mode == "sense_voice_en":
            if hasattr(self, 'offline_recognizer') and self.offline_recognizer is not None:
                self._use_offline_asr = True
                print(f"[配置] {self.current_cfg['name']} 使用 SenseVoice 英文模式")
            else:
                sense_result = self._create_sense_voice_recognizer(language="en")
                if sense_result and sense_result[0] is not None:
                    self.offline_recognizer, self.vad_config = sense_result
                    self._use_offline_asr = True
                    print(f"[配置] {self.current_cfg['name']} 使用 SenseVoice 英文模式 (English only)")
                else:
                    self._use_offline_asr = False
                    print(f"[配置] {self.current_cfg['name']} SenseVoice 不可用，使用流式识别")
        elif asr_mode == "sense_voice":
            if hasattr(self, 'offline_recognizer') and self.offline_recognizer is not None:
                self._use_offline_asr = True
                print(f"[配置] {self.current_cfg['name']} 使用 SenseVoice 多语言模式")
            else:
                sense_result = self._create_sense_voice_recognizer(language="auto")
                if sense_result and sense_result[0] is not None:
                    self.offline_recognizer, self.vad_config = sense_result
                    self._use_offline_asr = True
                    print(f"[配置] {self.current_cfg['name']} 使用 SenseVoice 多语言模式")
                else:
                    self._use_offline_asr = False
                    print(f"[配置] {self.current_cfg['name']} SenseVoice 不可用，使用流式识别")
        elif asr_mode == "offline":
            if hasattr(self, 'offline_recognizer') and self.offline_recognizer is not None:
                self._use_offline_asr = True
                print(f"[配置] {self.current_cfg['name']} 使用 Qwen3-ASR 离线识别模式")
            else:
                offline_result = self._create_offline_recognizer()
                if offline_result and offline_result[0] is not None:
                    self.offline_recognizer, self.vad_config, _ = offline_result
                    self._use_offline_asr = True
                    print(f"[配置] {self.current_cfg['name']} 使用 Qwen3-ASR 离线识别模式")
                else:
                    self._use_offline_asr = False
                    print(f"[配置] {self.current_cfg['name']} Qwen3-ASR 不可用，使用流式识别")
        else:
            self._use_offline_asr = False
            print(f"[配置] {self.current_cfg['name']} 使用流式识别模式")

        # 更新当前使用的组件
        self.jarvis = instance.feedback
        self.visual = instance.visual
        self.tts = instance.tts
        set_tts(self.tts)

        print(f"[切换] 已切换到: {self.current_cfg['name']} ({assistant_id})")
        return True

    def _init_openclaw(self):
        """初始化 OpenClaw bridge"""
        assistant_id = self.current_cfg["id"]
        if self.openclaw:
            # 如果有旧的，先发送停止
            self.openclaw.send_stop_command()
        self.openclaw = get_bridge(
            agent_id=assistant_id.replace("-", "_"), namespace="main"
        )
        self.openclaw.precheck_async()

    def _detect_assistant_from_keyword(self, keyword_result: str) -> str:
        """从唤醒词检测结果识别是哪个 assistant"""
        if not keyword_result:
            return self.current_cfg["id"]

        # 在 keyword_mapping 中查找
        for keyword_text, assistant_id in self.keyword_mapping.items():
            if keyword_text in keyword_result or keyword_result in keyword_text:
                return assistant_id

        # 如果没找到，返回当前 assistant
        return self.current_cfg["id"]

    def _check_microphone(self):
        """检查麦克风设备"""
        devices = sd.query_devices()
        if len(devices) == 0:
            print("未找到麦克风设备")
            sys.exit(0)

        print("可用设备:")
        for i, device in enumerate(devices):
            name = (
                device.get("name", f"设备 {i}")
                if hasattr(device, "get")
                else f"设备 {i}"
            )
            print(f"  {i}: {name}")

        default_idx = sd.default.device[0]
        if default_idx is not None and default_idx < len(devices):
            dev = devices[default_idx]
            name = (
                dev.get("name", f"设备 {default_idx}")
                if hasattr(dev, "get")
                else f"设备 {default_idx}"
            )
            print(f"使用默认设备: {name}")

    def _create_keyword_spotter(self):
        """创建关键词检测器"""
        return sherpa_onnx.KeywordSpotter(
            tokens=self.args.kws_tokens,
            encoder=self.args.kws_encoder,
            decoder=self.args.kws_decoder,
            joiner=self.args.kws_joiner,
            num_threads=1,
            keywords_file=self.args.keywords_file,
            keywords_score=self.args.keywords_score,
            keywords_threshold=self.args.keywords_threshold,
            max_active_paths=8,
            num_trailing_blanks=2,
            provider=self.args.provider,
        )

    def _create_recognizer(self):
        """创建语音识别器"""
        hotwords_file = os.path.expanduser(self.args.hotwords_file)
        use_hotwords = os.path.exists(hotwords_file)
        if use_hotwords:
            print(f"[ASR] 加载热词文件: {hotwords_file}")
        else:
            print(f"[ASR] 热词文件不存在: {hotwords_file}，不启用热词")

        return sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=self.args.asr_tokens,
            encoder=self.args.asr_encoder,
            decoder=self.args.asr_decoder,
            joiner=self.args.asr_joiner,
            num_threads=1,
            sample_rate=self.sample_rate,
            feature_dim=80,
            decoding_method="modified_beam_search" if use_hotwords else "greedy_search",
            hotwords_file=hotwords_file if use_hotwords else "",
            hotwords_score=self.args.hotwords_score,
            modeling_unit="cjkchar+bpe",
            bpe_vocab=self.args.asr_tokens,
            provider=self.args.provider,
        )

    def _create_sense_voice_recognizer(self, language="auto"):
        """创建 SenseVoice 离线识别器和 VAD 配置
        
        Args:
            language: 语言参数，auto/zh/en/ko/ja/yue
        """
        sense_voice_model = os.path.expanduser(self.args.sense_voice_model)
        sense_voice_tokens = os.path.expanduser(self.args.sense_voice_tokens)
        vad_model = os.path.expanduser(self.args.vad_model)

        if not os.path.exists(sense_voice_model):
            print(f"[警告] SenseVoice 模型不存在: {sense_voice_model}")
            return None, None

        print(f"[SenseVoice] 初始化离线识别器 (language={language})...")
        print(f"  model: {sense_voice_model}")
        print(f"  tokens: {sense_voice_tokens}")
        print(f"  use_itn: {self.args.sense_voice_use_itn}")

        try:
            recognizer = (
                sherpa_onnx.offline_recognizer.OfflineRecognizer.from_sense_voice(
                    model=sense_voice_model,
                    tokens=sense_voice_tokens,
                    num_threads=2,
                    use_itn=bool(self.args.sense_voice_use_itn),
                    language=language,
                )
            )
            print("[SenseVoice] 离线识别器创建成功")
        except Exception as e:
            print(f"[SenseVoice] 创建离线识别器失败: {e}")
            return None, None

        if not os.path.exists(vad_model):
            print(f"[警告] VAD 模型不存在: {vad_model}")
            print("[警告] 无法使用 SenseVoice")
            return recognizer, None

        print(f"[VAD] 初始化 VAD...")
        try:
            vad_config = sherpa_onnx.VadModelConfig(
                silero_vad=sherpa_onnx.SileroVadModelConfig(
                    model=vad_model,
                    threshold=0.1,
                    min_silence_duration=0.3,
                    min_speech_duration=0.1,
                    max_speech_duration=30,
                    window_size=512,
                ),
                sample_rate=16000,
                num_threads=1,
                provider=self.args.provider,
            )
            print("[VAD] VAD 配置创建成功")
        except Exception as e:
            print(f"[VAD] 创建 VAD 配置失败: {e}")
            return recognizer, None

        return recognizer, vad_config

    def _create_offline_recognizer(self):
        """创建 Qwen3-ASR 离线识别器和 VAD 配置"""
        qwen3_conv_frontend = os.path.expanduser(self.args.qwen3_conv_frontend)
        qwen3_encoder = os.path.expanduser(self.args.qwen3_encoder)
        qwen3_decoder = os.path.expanduser(self.args.qwen3_decoder)
        qwen3_tokenizer = os.path.expanduser(self.args.qwen3_tokenizer)
        vad_model = os.path.expanduser(self.args.vad_model)

        if not os.path.exists(qwen3_encoder):
            print(f"[警告] Qwen3-ASR 模型不存在: {qwen3_encoder}")
            print("[警告] 使用流式识别器替代")
            return None, None, None

        print(f"[Qwen3-ASR] 初始化离线识别器...")
        print(f"  conv_frontend: {qwen3_conv_frontend}")
        print(f"  encoder: {qwen3_encoder}")
        print(f"  decoder: {qwen3_decoder}")
        print(f"  tokenizer: {qwen3_tokenizer}")

        try:
            recognizer = (
                sherpa_onnx.offline_recognizer.OfflineRecognizer.from_qwen3_asr(
                    conv_frontend=qwen3_conv_frontend,
                    encoder=qwen3_encoder,
                    decoder=qwen3_decoder,
                    tokenizer=qwen3_tokenizer,
                    num_threads=2,
                )
            )
            print("[Qwen3-ASR] 离线识别器创建成功")
        except Exception as e:
            print(f"[Qwen3-ASR] 创建离线识别器失败: {e}")
            return None, None, None

        if not os.path.exists(vad_model):
            print(f"[警告] VAD 模型不存在: {vad_model}")
            print("[警告] 无法使用 Qwen3-ASR")
            return None, None, None

        print(f"[VAD] 初始化 VAD...")
        try:
            vad_config = sherpa_onnx.VadModelConfig(
                silero_vad=sherpa_onnx.SileroVadModelConfig(
                    model=vad_model,
                    threshold=0.1,
                    min_silence_duration=0.3,
                    min_speech_duration=0.1,
                    max_speech_duration=30,
                    window_size=512,
                ),
                sample_rate=16000,
                num_threads=1,
                provider=self.args.provider,
            )
            print("[VAD] VAD 配置创建成功")
        except Exception as e:
            print(f"[VAD] 创建 VAD 配置失败: {e}")
            return recognizer, None, None

        return recognizer, vad_config, None

    def _process_recognition_result(self, recognition_result):
        """处理识别结果，返回是否继续循环"""
        if not recognition_result:
            return True

        _recog = recognition_result.strip()
        _is_exit = _recog in EXIT_KEYWORDS or any(
            kw in _recog for kw in INSTANT_EXIT_FUZZY
        )
        if _is_exit:
            print(f"收到退出指令: {recognition_result.strip()}")
            self._interrupt_openclaw()
            self.jarvis.on_exit()
            self.visual.clear_texts()
            self.visual.hide_effects()
            if not _is_instant_exit(_recog):
                play_prebuilt_voice("exit", _random_exit_line())
                while is_tts_playing():
                    time.sleep(0.05)
            self._clear_queue()
            self.is_awake = False
            self.continuous_mode = False
            self._vad_stream = None
            self._audio_buffer = []
            self._speech_started = False
            print("\n已退出监听，等待唤醒词...")
            return False

        self.visual.show_user_text(recognition_result)
        if not self._ignore_next_result:
            threading.Thread(
                target=self._on_recognized,
                args=(recognition_result,),
                daemon=True,
            ).start()
        else:
            self._ignore_next_result = False
            print("[打断] 已忽略识别结果")
        return True

    def _get_keywords(self):
        """获取关键词列表"""
        keywords = []
        if os.path.exists(self.args.keywords_file):
            with open(self.args.keywords_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line and "@" in line:
                        keyword = line.split("@")[-1].strip()
                        keywords.append(keyword)
        return keywords

    def _audio_callback(self, indata, frames, time_info, status):
        """音频回调函数"""
        if status:
            print(status)
        if not is_tts_playing():
            if self.audio_queue.qsize() < 100:
                self.audio_queue.put(indata.copy())

    def _clear_queue(self):
        """清空音频队列"""
        try:
            while True:
                self.audio_queue.get_nowait()
        except queue.Empty:
            pass

    def _process_audio(self):
        """主音频处理循环 - 支持 Qwen3-ASR + VAD 模式"""

        recognition_stream = None
        recognition_result = ""
        keyword_stream = self.keyword_spotter.create_stream()
        audio_stream = None
        vad_stream = None
        audio_buffer = []
        speech_started = False
        speech_start_time = 0

        def start_audio_stream():
            nonlocal audio_stream
            if audio_stream is None:
                audio_stream = sd.InputStream(
                    channels=1,
                    dtype="float32",
                    samplerate=self.sample_rate,
                    callback=self._audio_callback,
                )
                audio_stream.start()

        def stop_audio_stream():
            nonlocal audio_stream
            if audio_stream is not None:
                try:
                    audio_stream.stop()
                    audio_stream.close()
                except Exception:
                    pass
                finally:
                    audio_stream = None

        def reset_audio_stream():
            nonlocal audio_stream
            try:
                if audio_stream is not None:
                    audio_stream.stop()
                    audio_stream.close()
            except Exception:
                pass
            audio_stream = None

        def _create_vad_stream():
            nonlocal vad_stream
            if self._use_offline_asr and self.vad_config:
                try:
                    vad_stream = sherpa_onnx.VoiceActivityDetector(
                        config=self.vad_config,
                        buffer_size_in_seconds=60,
                    )
                    return True
                except Exception as e:
                    print(f"[VAD] 创建失败: {e}")
                    return False
            return False

        def _do_recognize(audio_samples):
            """使用 SenseVoice 离线识别器识别音频片段"""
            if not self._use_offline_asr or not self.offline_recognizer:
                return None

            try:
                stream = self.offline_recognizer.create_stream()
                if hasattr(audio_samples, "tolist"):
                    samples_list = audio_samples.tolist()
                else:
                    samples_list = list(audio_samples)
                stream.accept_waveform(16000, samples_list)
                self.offline_recognizer.decode_stream(stream)
                return stream.result.text
            except Exception as e:
                print(f"[离线识别] 识别失败: {e}")
                return None

        start_audio_stream()
        print("开始监听...")
        print("提示: 说出唤醒词后可进入连续对话模式")

        if self._use_offline_asr:
            _create_vad_stream()

        while not self.stop_event.is_set():
            try:
                if is_tts_playing():
                    try:
                        audio_data = self.audio_queue.get(timeout=0.5)
                    except queue.Empty:
                        time.sleep(0.1)
                        continue

                    samples = audio_data.reshape(-1)

                    keyword_stream.accept_waveform(self.sample_rate, samples)

                    while self.keyword_spotter.is_ready(keyword_stream):
                        self.keyword_spotter.decode_stream(keyword_stream)
                        kw_result = self.keyword_spotter.get_result(keyword_stream)
                        if kw_result:
                            # 只有当前assistant的唤醒词才能打断
                            detected_id = self._detect_assistant_from_keyword(kw_result)
                            if detected_id != self.current_cfg["id"]:
                                continue
                            print(f"\n[打断] 检测到唤醒词: {kw_result}")
                            stop_tts()
                            self._interrupt_openclaw()
                            self._ignore_next_result = True
                            self.keyword_spotter.reset_stream(keyword_stream)
                            keyword_stream = self.keyword_spotter.create_stream()
                            print("\n请说出指令...")
                            break

                    self._clear_queue()
                    continue

                if self._last_tts_check and not is_tts_playing():
                    self._clear_queue()
                    self._last_tts_check = False
                    time.sleep(0.1)
                    continue

                if audio_stream is None:
                    start_audio_stream()

                self._last_tts_check = is_tts_playing()

                try:
                    audio_data = self.audio_queue.get(timeout=0.5)
                except queue.Empty:
                    continue

                samples = audio_data.reshape(-1)
                self.last_activity_time = time.time()

                if not self.is_awake:
                    keyword_stream.accept_waveform(self.sample_rate, samples)

                    while self.keyword_spotter.is_ready(keyword_stream):
                        self.keyword_spotter.decode_stream(keyword_stream)
                        result = self.keyword_spotter.get_result(keyword_stream)
                        if result:
                            if result.strip() in EXIT_KEYWORDS:
                                print(f"\n检测到退出指令: {result}")
                                stop_audio_stream()
                                self._clear_queue()
                                play_prebuilt_voice("exit", "Standing by.")
                                while is_tts_playing():
                                    time.sleep(0.05)
                                time.sleep(0.1)
                                self._clear_queue()
                                keyword_stream = self.keyword_spotter.create_stream()
                                start_audio_stream()
                                time.sleep(0.05)
                                self._clear_queue()
                                continue

                            print(f"\n检测到唤醒词: {result}")

                            # 识别是哪个 assistant 的唤醒词，并切换
                            detected_assistant_id = self._detect_assistant_from_keyword(
                                result
                            )
                            if detected_assistant_id != self.current_cfg["id"]:
                                print(
                                    f"[切换] 检测到 {self.keyword_mapping.get(result, detected_assistant_id)} 的唤醒词，正在切换..."
                                )
                                self._switch_assistant(detected_assistant_id)
                                self._init_openclaw()

                            self._ignore_next_result = True
                            self._suppress_recognition_until_tts_done = True

                            if self.is_awake and self._is_openclaw_busy:
                                self._interrupt_openclaw()
                            elif self.is_awake:
                                pass

                            print("已进入连续对话模式，可以连续说出指令...")
                            print('说"退出连续对话模式"可返回唤醒模式')

                            self.is_awake = True
                            self.continuous_mode = True
                            self.last_voice_time = time.time()

                            stop_audio_stream()
                            self._clear_queue()
                            recognition_result = ""
                            recognition_stream = self.recognizer.create_stream()
                            self.recognizer.reset(recognition_stream)
                            keyword_stream = self.keyword_spotter.create_stream()

                            if self._use_offline_asr:
                                vad_stream = None
                                _create_vad_stream()
                                audio_buffer = []
                                speech_started = False

                            import threading

                            self.visual.show_wake_effect()
                            self._suppress_recognition_until_tts_done = True
                            self._tts_start_time = time.time()
                            tts_thread = threading.Thread(
                                target=play_prebuilt_voice,
                                args=("wake", _random_wake_line()),
                                daemon=True,
                            )
                            tts_thread.start()
                            tts_thread.join()

                            self._suppress_recognition_until_tts_done = False
                            self._ignore_next_result = False
                            self._last_wake_time = time.time()  # 记录唤醒时间，唤醒后保护期内跳过退出检测

                            for _ in range(20):
                                self._clear_queue()
                            recognition_result = ""
                            start_audio_stream()
                            time.sleep(0.05)
                            for _ in range(20):
                                self._clear_queue()
                            continue
                    else:
                        if self._is_openclaw_busy:
                            kw_result = None
                            keyword_stream.accept_waveform(self.sample_rate, samples)

                            while self.keyword_spotter.is_ready(keyword_stream):
                                self.keyword_spotter.decode_stream(keyword_stream)
                                kw_result = self.keyword_spotter.get_result(
                                    keyword_stream
                                )
                                if kw_result:
                                    print(f"\n[打断] 检测到唤醒词: {kw_result}")
                                    self._interrupt_openclaw()
                                    self._ignore_next_result = True
                                    time.sleep(0.1)
                                    self._clear_queue()
                                    self.keyword_spotter.reset_stream(keyword_stream)
                                    keyword_stream = (
                                        self.keyword_spotter.create_stream()
                                    )
                                    recognition_stream = self.recognizer.create_stream()
                                    recognition_result = ""
                                    print("\n请说出指令...")
                                    break
                        if not self.is_awake:
                            continue

                else:
                    # 已进入唤醒状态，需要持续检测唤醒词以支持打断
                    if self._is_openclaw_busy:
                        # OpenClaw 正在处理，检测唤醒词来打断
                        keyword_stream.accept_waveform(self.sample_rate, samples)
                        
                        while self.keyword_spotter.is_ready(keyword_stream):
                            self.keyword_spotter.decode_stream(keyword_stream)
                            kw_result = self.keyword_spotter.get_result(keyword_stream)
                            if kw_result:
                                # 只有当前assistant的唤醒词才能打断
                                detected_id = self._detect_assistant_from_keyword(kw_result)
                                if detected_id != self.current_cfg["id"]:
                                    continue
                                print(f"\n[打断] 检测到唤醒词: {kw_result}")
                                # 打断当前请求
                                self._interrupt_openclaw()
                                self._ignore_next_result = True
                                
                                time.sleep(0.1)
                                self._clear_queue()
                                self.keyword_spotter.reset_stream(keyword_stream)
                                keyword_stream = self.keyword_spotter.create_stream()
                                recognition_stream = self.recognizer.create_stream()
                                recognition_result = ""
                                print("\n请说出指令...")
                                break
                        # 打断后继续循环，不再处理识别
                        continue
                    
                    # OpenClaw 空闲，正常处理语音识别
                    if recognition_stream is None:
                        recognition_stream = self.recognizer.create_stream()
                    recognition_stream.accept_waveform(self.sample_rate, samples)

                    while self.recognizer.is_ready(recognition_stream):
                        self.recognizer.decode_stream(recognition_stream)

                    result = self.recognizer.get_result(recognition_stream)
                    if result and result != recognition_result:
                        recognition_result = result
                        self.last_voice_time = time.time()
                        if not self._suppress_recognition_until_tts_done:
                            print(f"\r✓ 识别: {result}", end="", flush=True)
                        self.visual.show_user_text(result)

                    _early_recog = (
                        recognition_result.strip() if recognition_result else ""
                    )
                    # 打断后 2 秒内、唤醒后 2 秒内跳过退出检测，避免残留音频误触发
                    _recent_interrupt = (time.time() - self._last_interrupt_time) < 2.0
                    _recent_wake = (time.time() - self._last_wake_time) < 2.0
                    _early_exit = _early_recog and not _recent_interrupt and not _recent_wake and (
                        _early_recog in EXIT_KEYWORDS
                        or any(
                            kw in _early_recog
                            for kw in INSTANT_EXIT_FUZZY
                        )
                    )
                    if _early_exit:
                        print(f"\n收到退出指令（延时1s执行）: {_early_recog}")
                        time.sleep(1.0)
                        self.exit_standby(instant=_is_instant_exit(_early_recog))
                        recognition_result = ""
                        recognition_stream = self.recognizer.create_stream()
                        stop_audio_stream()
                        self._clear_queue()
                        start_audio_stream()
                        keyword_stream = self.keyword_spotter.create_stream()
                        continue

                    current_time = time.time()
                    silence_duration = current_time - self.last_voice_time
                    idle_duration = current_time - self.last_activity_time

                    if self.continuous_mode and idle_duration > self.idle_timeout:
                        print(f"\n连续对话超时（{self.idle_timeout}秒无活动），已退出")
                        self.continuous_mode = False
                        self.visual.hide_effects()
                        self.visual.clear_texts()
                        self.is_awake = False
                        recognition_result = ""
                        print("\n请说出唤醒词来激活...")
                        self.keyword_spotter.reset_stream(keyword_stream)
                        keyword_stream = self.keyword_spotter.create_stream()
                        continue

                    if self.recognizer.is_endpoint(recognition_stream) or (
                        recognition_result and silence_duration > 3.0
                    ):
                        if recognition_result:
                            should_suppress = self._suppress_recognition_until_tts_done

                            if should_suppress:
                                print("[打断] TTS播放中/等待稳定，忽略识别结果")
                                recognition_result = ""
                                recognition_stream = self.recognizer.create_stream()
                                start_audio_stream()
                                continue

                            print("\n识别结果:", recognition_result)

                            stop_audio_stream()
                            self._clear_queue()

                            _recog = recognition_result.strip()
                            # 打断后 2 秒内、唤醒后 2 秒内跳过退出检测，避免残留音频误触发
                            _recent_interrupt = (time.time() - self._last_interrupt_time) < 2.0
                            _recent_wake = (time.time() - self._last_wake_time) < 2.0
                            _is_exit = not _recent_interrupt and not _recent_wake and (_recog in EXIT_KEYWORDS or any(
                                kw in _recog
                                for kw in INSTANT_EXIT_FUZZY
                            ))
                            if _is_exit:
                                print(f"收到退出指令: {recognition_result.strip()}")
                                self._interrupt_openclaw()
                                stop_audio_stream()
                                self._clear_queue()
                                self.jarvis.on_exit()
                                self.visual.clear_texts()
                                self.visual.hide_effects()
                                if not _is_instant_exit(_recog):
                                    play_prebuilt_voice("exit", _random_exit_line())
                                    while is_tts_playing():
                                        time.sleep(0.05)
                                self._clear_queue()
                                self.is_awake = False
                                self.continuous_mode = False
                                recognition_result = ""
                                print("\n已退出监听，等待唤醒词...")
                                start_audio_stream()
                                time.sleep(0.05)
                                self._clear_queue()
                                keyword_stream = self.keyword_spotter.create_stream()
                                continue

                            self.visual.show_user_text(recognition_result)
                            if not self._ignore_next_result:
                                threading.Thread(
                                    target=self._on_recognized,
                                    args=(recognition_result,),
                                    daemon=True,
                                ).start()
                            else:
                                self._ignore_next_result = False
                                print("[打断] 已忽略识别结果")

                            command_lower = recognition_result.lower()
                            exit_continuous = any(
                                kw in command_lower
                                for kw in [
                                    "退出连续对话",
                                    "退出连续模式",
                                    "退出对话模式",
                                ]
                            )

                            self._clear_queue()
                            start_audio_stream()

                            if self.continuous_mode and not exit_continuous:
                                recognition_result = ""
                                recognition_stream = self.recognizer.create_stream()
                                print("\n请继续说出指令...")
                            else:
                                self.visual.hide_effects()
                                self.visual.clear_texts()
                                self.is_awake = False
                                self.continuous_mode = False
                                recognition_result = ""
                                print("\n请说出唤醒词来激活...")
                                keyword_stream = self.keyword_spotter.create_stream()
                        else:
                            if self.continuous_mode:
                                recognition_stream = self.recognizer.create_stream()
                            else:
                                self.visual.hide_effects()
                                self.visual.clear_texts()
                                self.is_awake = False
                                print("\n请说出唤醒词来激活...")
                                keyword_stream = self.keyword_spotter.create_stream()

            except queue.Empty:
                continue
            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"错误: {e}")
                import traceback

                traceback.print_exc()
                print("[恢复] 正在尝试重建音频流...")
                reset_audio_stream()
                self._clear_queue()
                keyword_stream = self.keyword_spotter.create_stream()
                recognition_stream = self.recognizer.create_stream()
                recognition_result = ""
                speech_started = False
                time.sleep(1)
                try:
                    start_audio_stream()
                    print("[恢复] 音频流已重建，继续监听...")
                    continue
                except Exception as ne:
                    print(f"[恢复] 音频流重建失败: {ne}")
                    print("[恢复] 将尝试在下一循环重建...")
                    time.sleep(2)
                    continue

        stop_audio_stream()

    def _interrupt_openclaw(self):
        """执行打断操作：发送 /stop、取消当前请求、停止 TTS"""
        print("\n[打断] 检测到唤醒词，执行打断...")
        # 发送 /stop 命令（异步）
        self.openclaw.send_stop_command()
        # 取消当前请求（同步标记）
        self.openclaw.cancel_current_request()
        # 设置停止标志，用于阻塞等待循环
        self._stop_openclaw_request.set()
        # 立即重置状态，确保可以重新唤醒
        self._is_openclaw_busy = False
        if hasattr(self, "_waiting_active"):
            self._waiting_active.clear()
        # 停止 TTS 播放
        stop_tts()
        # 记录打断时间，用于防止后续误触发退出检测
        self._last_interrupt_time = time.time()
        print("[打断] 已发出中断信号，状态已重置")
    
    def _interrupt_openclaw_silent(self):
        """静默中断：仅取消请求和重置状态，不发送 /stop 命令
        用于 exit_standby 等已经明确要退出的场景，避免重复发送 /stop
        """
        self.openclaw.cancel_current_request()
        self._stop_openclaw_request.set()
        self._is_openclaw_busy = False
        if hasattr(self, "_waiting_active"):
            self._waiting_active.clear()
        stop_tts()
        # 同样记录打断时间，防止误触发退出检测
        self._last_interrupt_time = time.time()

    def _on_recognized(self, text: str):
        """识别结果 → 发送给 OpenClaw → 整体合成播报回复"""
        print(f"\n[→ OpenClaw] {text}")

        # 在发送给 OpenClaw 之前的一瞬间，还原特效大小
        self.visual.reset_speaking_scale()

        print("◈ 正在思考...", end="", flush=True)

        self._is_openclaw_busy = True
        self._stop_openclaw_request.clear()
        self._openclaw_request_active.set()

        import threading
        import queue

        result_queue = queue.Queue()

        def _openclaw_request():
            self._waiting_active = threading.Event()
            self._waiting_active.set()

            def _waiting_sound_loop():
                while self._waiting_active.is_set():
                    self.jarvis.play_sound("waiting")
                    for _ in range(10):
                        if not self._waiting_active.is_set():
                            return
                        time.sleep(0.3)

            waiting_thread = threading.Thread(target=_waiting_sound_loop, daemon=True)
            waiting_thread.start()

            received_chunks = []
            stop_requested = threading.Event()

            def _on_stream_start():
                if self._stop_openclaw_request.is_set():
                    stop_requested.set()
                    return
                self._waiting_active.clear()
                time.sleep(0.05)
                print("\n[← OpenClaw] ", end="", flush=True)

            def _on_stream_chunk(chunk):
                if self._stop_openclaw_request.is_set():
                    stop_requested.set()
                    return
                received_chunks.append(chunk)
                full_text = "".join(received_chunks)
                print(chunk, end="", flush=True)
                self.visual.show_ai_text(full_text)

            def _on_stream_end():
                if not stop_requested.is_set():
                    self._waiting_active.clear()

            try:
                reply = self.openclaw.send_and_wait_stream(
                    text,
                    on_chunk=_on_stream_chunk,
                    on_start=_on_stream_start,
                    on_end=_on_stream_end,
                )
                self._waiting_active.clear()
                waiting_thread.join(timeout=0.5)
                result_queue.put(("success", reply))
            except Exception as e:
                self._waiting_active.clear()
                result_queue.put(("error", str(e)))
            finally:
                # 确保无论发生什么都会重置状态
                self._is_openclaw_busy = False
                self._openclaw_request_active.clear()

        request_thread = threading.Thread(target=_openclaw_request, daemon=True)
        request_thread.start()

        while True:
            try:
                status, data = result_queue.get(timeout=0.5)
                break
            except queue.Empty:
                if self._stop_openclaw_request.is_set():
                    # 只在第一次检测到打断时发送 stop 命令
                    self.openclaw.send_stop_command()
                    self.openclaw.cancel_current_request()
                    print("\n[打断] OpenClaw 请求已中断")
                    self._is_openclaw_busy = False
                    return

        if status == "success":
            reply = data
            if reply:
                print()
                # 整体合成播放
                cleaned = _clean_for_tts(reply)
                if cleaned:
                    from tts import _tts_playing

                    _tts_playing.set()
                    try:
                        result = self.tts.synthesize_to_array(cleaned)
                        if result and not self._stop_openclaw_request.is_set():
                            import sounddevice as sd

                            audio_data, sample_rate = result
                            sd.play(audio_data * 1.5, samplerate=sample_rate)
                            sd.wait()
                    finally:
                        _tts_playing.clear()
                print("◈ 继续说吧，我在听着...", flush=True)
                self.jarvis.play_sound("continue")
                self._is_openclaw_busy = False
                return
            else:
                print("\n[← OpenClaw] (无回复)")
                self.jarvis.on_error("无回复")
        else:
            print(f"[OpenClaw] 异常: {data}")
            self.jarvis.on_error(data)

        self._is_openclaw_busy = False

    def run(self):
        """运行语音助手"""
        self.jarvis.system_ready()
        try:
            self._process_audio()
        except KeyboardInterrupt:
            print("\n收到中断信号，正在退出...")
            self.stop_event.set()
        finally:
            self.stop()

    def stop(self):
        """停止语音助手"""
        self.stop_event.set()
        print("语音助手已关闭。")

    def exit_standby(self, instant: bool = False):
        """执行退下操作：从连续对话模式回到待机模式"""
        # 已经处于待机状态，跳过重复退出（防止 TTS 回声反复触发）
        if not self.is_awake and not self.continuous_mode:
            print("[exit_standby] 已在待机状态，跳过")
            return
        print("\n[收到退下信号]")
        # 使用静默中断，避免重复发送 /stop 命令
        self._interrupt_openclaw_silent()
        if hasattr(self, "_waiting_active"):
            self._waiting_active.clear()
        self.jarvis.on_exit()
        self.visual.clear_texts()
        self.visual.hide_effects()
        self.is_awake = False
        self.continuous_mode = False
        if not instant:
            play_prebuilt_voice("exit", _random_exit_line())
            while is_tts_playing():
                time.sleep(0.05)
        self._clear_queue()
        print("\n已退出监听，等待唤醒词...")


def assert_file_exists(filename):
    """检查文件是否存在"""
    filename = os.path.expanduser(filename)
    assert Path(filename).is_file(), (
        f"{filename} 不存在！\n"
        "请参考 https://k2-fsa.github.io/sherpa/onnx/pretrained_models/index.html 下载模型"
    )


def get_args():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
        description="语音助手 - 基于 sherpa-onnx 的语音唤醒 + 识别",
    )

    # 关键词检测模型参数
    parser.add_argument(
        "--kws-tokens",
        type=str,
        default="models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01/tokens.txt",
    )
    parser.add_argument(
        "--kws-encoder",
        type=str,
        default="models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01/encoder-epoch-12-avg-2-chunk-16-left-64.onnx",
    )
    parser.add_argument(
        "--kws-decoder",
        type=str,
        default="models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01/decoder-epoch-12-avg-2-chunk-16-left-64.onnx",
    )
    parser.add_argument(
        "--kws-joiner",
        type=str,
        default="models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01/joiner-epoch-12-avg-2-chunk-16-left-64.onnx",
    )
    parser.add_argument("--keywords-file", type=str, default="keywords/lin-meimei.txt")
    parser.add_argument("--keywords-score", type=float, default=0.15)
    parser.add_argument("--keywords-threshold", type=float, default=0.15)

    # 语音识别模型参数
    parser.add_argument(
        "--asr-tokens",
        type=str,
        default="models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/tokens.txt",
    )
    parser.add_argument(
        "--asr-encoder",
        type=str,
        default="models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/encoder-epoch-99-avg-1.onnx",
    )
    parser.add_argument(
        "--asr-decoder",
        type=str,
        default="models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/decoder-epoch-99-avg-1.onnx",
    )
    parser.add_argument(
        "--asr-joiner",
        type=str,
        default="models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/joiner-epoch-99-avg-1.onnx",
    )

    # SenseVoice 模型参数（离线识别）
    _project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    _sense_voice_model_dir = os.path.join(
        _project_dir, "models", "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
    )
    parser.add_argument(
        "--sense-voice-model",
        type=str,
        default=os.path.join(_sense_voice_model_dir, "model.int8.onnx"),
    )
    parser.add_argument(
        "--sense-voice-tokens",
        type=str,
        default=os.path.join(_sense_voice_model_dir, "tokens.txt"),
    )
    parser.add_argument(
        "--sense-voice-use-itn",
        type=int,
        default=1,
        help="是否启用反向文本规范化（标点符号）",
    )
    parser.add_argument(
        "--sense-voice-language",
        type=str,
        default="auto",
        help="语言：auto, zh, en, ko, ja, yue",
    )
    
    # Qwen3-ASR 模型参数（离线识别）
    _qwen3_model_dir = os.path.join(
        _project_dir, "models", "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25"
    )
    parser.add_argument(
        "--qwen3-conv-frontend",
        type=str,
        default=os.path.join(_qwen3_model_dir, "conv_frontend.onnx"),
    )
    parser.add_argument(
        "--qwen3-encoder",
        type=str,
        default=os.path.join(_qwen3_model_dir, "encoder.int8.onnx"),
    )
    parser.add_argument(
        "--qwen3-decoder",
        type=str,
        default=os.path.join(_qwen3_model_dir, "decoder.int8.onnx"),
    )
    parser.add_argument(
        "--qwen3-tokenizer",
        type=str,
        default=os.path.join(_qwen3_model_dir, "tokenizer"),
    )
    parser.add_argument(
        "--vad-model",
        type=str,
        default=os.path.join(_project_dir, "models", "silero_vad.onnx"),
    )

    parser.add_argument(
        "--hotwords-file", type=str, default=os.path.join(_project_dir, "hotwords.txt")
    )
    parser.add_argument("--hotwords-score", type=float, default=1.5)

    parser.add_argument("--provider", type=str, default="cpu")

    return parser.parse_args()


def main():
    global _assistant_instance

    args = get_args()

    # 加载所有 assistant 配置
    default_cfg, all_assistants = _load_all_assistant_configs()
    print(f"[配置] 激活 assistant: {default_cfg['name']} ({default_cfg['id']})")

    # 使用 global.txt 作为唤醒词文件（由 start.sh 脚本合并生成）
    args.keywords_file = os.path.join(_PROJECT_DIR, "keywords", "global.txt")
    
    # 构建 keyword_to_assistant_id 映射（从所有 assistant 配置中读取）
    keyword_mapping = {}
    for assistant in all_assistants:
        assistant_id = assistant["id"]
        keywords_file = assistant.get("keywords_file")
        if keywords_file:
            full_path = os.path.join(_PROJECT_DIR, keywords_file)
            if os.path.exists(full_path):
                with open(full_path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        if "@" in line:
                            keyword_text = line.split("@")[-1].strip()
                            keyword_mapping[keyword_text] = assistant_id
                print(f"[配置] 加载 {assistant['name']} ({assistant_id}) 的唤醒词映射")
    
    print(f"[配置] 使用唤醒词文件: {args.keywords_file}")
    print(f"[配置] 唤醒词映射: {keyword_mapping}")

    for f in [
        args.kws_tokens,
        args.kws_encoder,
        args.kws_decoder,
        args.kws_joiner,
        args.keywords_file,
        args.asr_tokens,
        args.asr_encoder,
        args.asr_decoder,
        args.asr_joiner,
    ]:
        assert_file_exists(f)

    assistant = VoiceAssistant(args, default_cfg, all_assistants, keyword_mapping)
    _assistant_instance = assistant

    api_thread = threading.Thread(target=_start_api_server, daemon=True)
    api_thread.start()
    print(f"API server started on port {API_PORT}")

    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))

    try:
        assistant.run()
    finally:
        if os.path.exists(PID_FILE):
            os.remove(PID_FILE)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n程序被用户中断")
    except Exception as e:
        print(f"发生错误: {e}")
