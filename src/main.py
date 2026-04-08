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
import sys
import time
import threading
import queue
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

_assistant_instance = None
PID_FILE = "/tmp/voice_assistant.pid"
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

from tts import text_to_speech_play, is_tts_playing, play_prebuilt_voice, stop_tts
from openclaw_bridge import get_bridge
from jarvis_feedback import get_feedback
from jarvis_visual import get_visual_effects

# 退出连续对话的关键词（精确匹配）
EXIT_KEYWORDS = {
    "退下",
    "退下吧",
    "没事了",
    "没有了",
    "结束",
    "行了",
    "好了",
    "你可以退下了",
    "QUIT",
    "quit",
    "EXIT",
    "exit",
}


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
    def __init__(self, args):
        self.args = args
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

        self.jarvis = get_feedback(
            sound_enabled=True, hud_enabled=True, notification_enabled=True
        )
        self.visual = get_visual_effects(enabled=True)

        self.keyword_spotter = self._create_keyword_spotter()
        self.recognizer = self._create_recognizer()
        self.offline_recognizer, self.vad_config, _ = self._create_offline_recognizer()
        self._use_offline_asr = (
            self.offline_recognizer is not None and self.vad_config is not None
        )
        if self._use_offline_asr:
            print("[配置] 使用 Qwen3-ASR 离线识别模式")
        else:
            print("[配置] 使用流式识别模式")
        self._check_microphone()

        self.openclaw = get_bridge()
        self.openclaw.precheck_async()

        # print("正在发送 /compact 指令...")
        # compact_result = self.openclaw.send_and_wait("/compact")
        # if compact_result:
        #     print(f"[初始化] /compact 响应: {compact_result[:100]}...")
        # else:
        #     print("[初始化] /compact 无响应或失败（不影响启动）")

        print("语音助手初始化完成！")
        print(f"唤醒词: {self._get_keywords()}")
        print("正在检测 OpenClaw 连接...")
        print("提示: 说出唤醒词后可进入连续对话模式")

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
        return sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=self.args.asr_tokens,
            encoder=self.args.asr_encoder,
            decoder=self.args.asr_decoder,
            joiner=self.args.asr_joiner,
            num_threads=1,
            sample_rate=self.sample_rate,
            feature_dim=80,
            decoding_method="greedy_search",
            provider=self.args.provider,
        )

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
            kw in _recog for kw in ("退一下", "推一下", "退一退", "推一推")
        )
        if _is_exit:
            print(f"收到退出指令: {recognition_result.strip()}")
            self._interrupt_openclaw()
            self.jarvis.on_exit()
            self.visual.clear_texts()
            self.visual.hide_effects()
            play_prebuilt_voice("exit", "Very well. Standing by, sir.")
            while is_tts_playing():
                time.sleep(0.05)
            time.sleep(0.1)
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
            """使用 Qwen3-ASR 识别音频片段"""
            if not self._use_offline_asr or not self.offline_recognizer:
                return None

            try:
                import soundfile as sf
                import tempfile

                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                    temp_path = f.name

                sf.write(temp_path, audio_samples, samplerate=16000, subtype="PCM_16")

                stream = self.offline_recognizer.create_stream()
                audio, sr = sf.read(temp_path, dtype="float32")
                if audio.ndim > 1:
                    audio = audio[:, 0]
                stream.accept_waveform(sr, audio.tolist())
                self.offline_recognizer.decode_stream(stream)
                result = stream.result.text

                os.unlink(temp_path)
                return result
            except Exception as e:
                print(f"[Qwen3-ASR] 识别失败: {e}")
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
                                self._vad_stream = None
                                self._audio_buffer = []
                                self._speech_started = False

                            import threading

                            self.visual.show_wake_effect()
                            self._suppress_recognition_until_tts_done = True
                            self._tts_start_time = time.time()
                            tts_thread = threading.Thread(
                                target=play_prebuilt_voice,
                                args=("wake", "At your service, sir."),
                                daemon=True,
                            )
                            tts_thread.start()
                            tts_thread.join()

                            self._suppress_recognition_until_tts_done = False
                            self._ignore_next_result = False

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
                    if self._is_openclaw_busy:
                        continue
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
                            _is_exit = _recog in EXIT_KEYWORDS or any(
                                kw in _recog
                                for kw in (
                                    "退一下",
                                    "推一下",
                                    "退一退",
                                    "推一推",
                                )
                            )
                            if _is_exit:
                                print(f"收到退出指令: {recognition_result.strip()}")
                                self._interrupt_openclaw()
                                stop_audio_stream()
                                self._clear_queue()
                                self.jarvis.on_exit()
                                self.visual.clear_texts()
                                self.visual.hide_effects()
                                play_prebuilt_voice(
                                    "exit", "Very well. Standing by, sir."
                                )
                                while is_tts_playing():
                                    time.sleep(0.05)
                                    time.sleep(0.1)
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
        self.openclaw.send_stop_command()
        self.openclaw.cancel_current_request()
        self._stop_openclaw_request.set()
        self._is_openclaw_busy = False
        if hasattr(self, "_waiting_active"):
            self._waiting_active.clear()
        stop_tts()
        print("[打断] 已发出中断信号")

    def _on_recognized(self, text: str):
        """识别结果 → 发送给 OpenClaw → TTS 播报回复"""
        print(f"\n[→ OpenClaw] {text}")
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
                print(chunk, end="", flush=True)
                self.visual.show_ai_text("".join(received_chunks))

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

        request_thread = threading.Thread(target=_openclaw_request, daemon=True)
        request_thread.start()

        while True:
            try:
                status, data = result_queue.get(timeout=0.5)
                break
            except queue.Empty:
                if self._stop_openclaw_request.is_set():
                    self.openclaw.send_stop_command()
                    self.openclaw.cancel_current_request()
                    print("\n[打断] OpenClaw 请求已中断")
                    self._is_openclaw_busy = False
                    return

        if status == "success":
            reply = data
            if reply:
                print()
                tts_text = _clean_for_tts(reply)
                if tts_text:
                    text_to_speech_play(tts_text)
                    self.jarvis.play_sound("continue")
                    print("◈ 继续说吧，我在听着...", flush=True)
                    while is_tts_playing():
                        time.sleep(0.1)
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

    def exit_standby(self):
        """执行退下操作：从连续对话模式回到待机模式"""
        print("\n[收到退下信号]")
        self._interrupt_openclaw()
        if hasattr(self, "_waiting_active"):
            self._waiting_active.clear()
        self.jarvis.on_exit()
        self.visual.clear_texts()
        self.visual.hide_effects()
        play_prebuilt_voice("exit", "Very well. Standing by, sir.")
        while is_tts_playing():
            time.sleep(0.05)
        self._clear_queue()
        self.is_awake = False
        self.continuous_mode = False
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
    parser.add_argument("--keywords-file", type=str, default="custom_keywords.txt")
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

    # Qwen3-ASR 模型参数（离线识别）
    parser.add_argument(
        "--qwen3-conv-frontend",
        type=str,
        default="~/.openclaw/tools/sherpa-onnx-tts/models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25/conv_frontend.onnx",
    )
    parser.add_argument(
        "--qwen3-encoder",
        type=str,
        default="~/.openclaw/tools/sherpa-onnx-tts/models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25/encoder.int8.onnx",
    )
    parser.add_argument(
        "--qwen3-decoder",
        type=str,
        default="~/.openclaw/tools/sherpa-onnx-tts/models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25/decoder.int8.onnx",
    )
    parser.add_argument(
        "--qwen3-tokenizer",
        type=str,
        default="~/.openclaw/tools/sherpa-onnx-tts/models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25/tokenizer",
    )
    parser.add_argument(
        "--vad-model",
        type=str,
        default="~/.openclaw/tools/sherpa-onnx-tts/models/silero_vad.onnx",
    )

    parser.add_argument("--provider", type=str, default="cpu")

    return parser.parse_args()


def main():
    global _assistant_instance

    args = get_args()

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

    assistant = VoiceAssistant(args)
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
