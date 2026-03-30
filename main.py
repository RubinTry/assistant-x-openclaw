#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
语音助手程序 - 基于 sherpa-onnx
语音唤醒 + 流式语音识别
为 OpenClaw 联动预留接口
"""

import argparse
import os
import sys
import time
import threading
import queue
from pathlib import Path

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

from tts import text_to_speech_play, is_tts_playing, play_prebuilt_voice
from openclaw_bridge import get_bridge
from jarvis_feedback import get_feedback
from jarvis_visual import get_visual_effects

# 退出连续对话的关键词（精确匹配）
EXIT_KEYWORDS = {"退下", "退下吧", "没事了", "没有了", "结束", "行了", "好了", "你可以退下了"}


def _clean_for_tts(text: str) -> str:
    """清理文本，适合 TTS 朗读"""
    import re
    # 去掉 markdown 符号
    text = re.sub(r'[*`#>\-]+', '', text)
    # 去掉 emoji
    text = re.sub(r'[\U0001f300-\U0001f9ff\u2600-\u26ff\u2700-\u27bf]', '', text)
    # 合并多余空白和换行
    text = re.sub(r'\s+', ' ', text).strip()
    # 截断过长文本（取前500字符，尽量在句号处截断）
    if len(text) > 500:
        cut = text[:500]
        last_period = max(cut.rfind('。'), cut.rfind('！'), cut.rfind('？'), cut.rfind('.'))
        if last_period > 100:
            text = cut[:last_period + 1]
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

        self.jarvis = get_feedback(sound_enabled=True, hud_enabled=True, notification_enabled=True)
        self.visual = get_visual_effects(enabled=True)

        self.keyword_spotter = self._create_keyword_spotter()
        self.recognizer = self._create_recognizer()
        self._check_microphone()

        self.openclaw = get_bridge()
        self.openclaw.precheck_async()

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
            name = device.get('name', f"设备 {i}") if hasattr(device, 'get') else f"设备 {i}"
            print(f"  {i}: {name}")

        default_idx = sd.default.device[0]
        if default_idx is not None and default_idx < len(devices):
            dev = devices[default_idx]
            name = dev.get('name', f"设备 {default_idx}") if hasattr(dev, 'get') else f"设备 {default_idx}"
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

    def _get_keywords(self):
        """获取关键词列表"""
        keywords = []
        if os.path.exists(self.args.keywords_file):
            with open(self.args.keywords_file, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if line and '@' in line:
                        keyword = line.split('@')[-1].strip()
                        keywords.append(keyword)
        return keywords

    def _audio_callback(self, indata, frames, time_info, status):
        """音频回调函数"""
        if status:
            print(status)
        if not is_tts_playing():
            self.audio_queue.put(indata.copy())

    def _clear_queue(self):
        """清空音频队列"""
        try:
            while True:
                self.audio_queue.get_nowait()
        except queue.Empty:
            pass

    def _process_audio(self):
        """主音频处理循环"""
        recognition_stream = self.recognizer.create_stream()
        recognition_result = ""
        keyword_stream = self.keyword_spotter.create_stream()
        audio_stream = None

        def start_audio_stream():
            nonlocal audio_stream
            if audio_stream is None:
                audio_stream = sd.InputStream(
                    channels=1, dtype='float32',
                    samplerate=self.sample_rate,
                    callback=self._audio_callback,
                )
                audio_stream.start()

        def stop_audio_stream():
            nonlocal audio_stream
            if audio_stream is not None:
                audio_stream.stop()
                audio_stream.close()
                audio_stream = None

        start_audio_stream()
        print("开始监听...")
        print("提示: 说出唤醒词后可进入连续对话模式")

        while not self.stop_event.is_set():
            try:
                # TTS 播放期间暂停录制
                if is_tts_playing():
                    stop_audio_stream()
                    self._clear_queue()
                    time.sleep(0.1)
                    continue

                # TTS 结束后恢复
                if self._last_tts_check and not is_tts_playing():
                    self._clear_queue()
                    start_audio_stream()
                    self._last_tts_check = False
                    continue

                if audio_stream is None:
                    start_audio_stream()

                self._last_tts_check = is_tts_playing()

                audio_data = self.audio_queue.get(timeout=0.5)
                samples = audio_data.reshape(-1)
                self.last_activity_time = time.time()

                if not self.is_awake:
                    # 唤醒模式
                    keyword_stream.accept_waveform(self.sample_rate, samples)

                    while self.keyword_spotter.is_ready(keyword_stream):
                        self.keyword_spotter.decode_stream(keyword_stream)
                        result = self.keyword_spotter.get_result(keyword_stream)
                        if result:
                            # 检查是否是退出关键词
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
                            print("已进入连续对话模式，可以连续说出指令...")
                            print("说\"退出连续对话模式\"可返回唤醒模式")

                            stop_audio_stream()
                            self._clear_queue()

                            import threading
                            self.visual.show_wake_effect()
                            tts_thread = threading.Thread(target=play_prebuilt_voice, args=("wake", "At your service, sir."), daemon=True)
                            tts_thread.start()
                            tts_thread.join()

                            time.sleep(0.05)
                            self._clear_queue()
                            start_audio_stream()
                            time.sleep(0.05)
                            self._clear_queue()

                            self.is_awake = True
                            self.continuous_mode = True
                            self.last_voice_time = time.time()
                            recognition_stream = self.recognizer.create_stream()
                            self.keyword_spotter.reset_stream(keyword_stream)
                else:
                    # 命令识别模式
                    recognition_stream.accept_waveform(self.sample_rate, samples)

                    while self.recognizer.is_ready(recognition_stream):
                        self.recognizer.decode_stream(recognition_stream)

                    result = self.recognizer.get_result(recognition_stream)
                    if result and result != recognition_result:
                        recognition_result = result
                        print(f"\r✓ 识别: {result}", end="", flush=True)
                        self.visual.show_user_text(result)
                        self.last_voice_time = time.time()

                    current_time = time.time()
                    silence_duration = current_time - self.last_voice_time
                    idle_duration = current_time - self.last_activity_time

                    # 连续对话超时
                    if self.continuous_mode and idle_duration > self.idle_timeout:
                        print(f"\n连续对话超时（{self.idle_timeout}秒无活动），已退出")
                        self.continuous_mode = False
                        self.visual.hide_effects()
                        self.visual.clear_texts()
                        self.is_awake = False
                        recognition_result = ""
                        print("\n请说出唤醒词来激活...")
                        # 重置关键词检测器状态
                        self.keyword_spotter.reset_stream(keyword_stream)
                        keyword_stream = self.keyword_spotter.create_stream()
                        continue

                    # 检测语音结束
                    if self.recognizer.is_endpoint(recognition_stream) or (recognition_result and silence_duration > 1.0):
                        if recognition_result:
                            print("\n识别结果:", recognition_result)

                            stop_audio_stream()
                            self._clear_queue()

                            # === 退出关键词处理 ===
                            if recognition_result.strip() in EXIT_KEYWORDS:
                                print(f"收到退出指令: {recognition_result.strip()}")
                                stop_audio_stream()
                                self._clear_queue()
                                self.jarvis.on_exit()
                                self.visual.hide_effects()
                                play_prebuilt_voice("exit", "Very well. Standing by, sir.")
                                while is_tts_playing():
                                    time.sleep(0.05)
                                time.sleep(0.1)
                                self._clear_queue()
                                self.visual.hide_effects()
                                self.visual.clear_texts()
                                self.is_awake = False
                                self.continuous_mode = False
                                recognition_result = ""
                                print("\n已退出监听，等待唤醒词...")
                                start_audio_stream()
                                time.sleep(0.05)
                                self._clear_queue()
                                keyword_stream = self.keyword_spotter.create_stream()
                                continue

                            # === 识别结果回调 ===
                            self.visual.show_user_text(recognition_result)
                            self._on_recognized(recognition_result)

                            # 检查退出连续对话
                            command_lower = recognition_result.lower()
                            exit_continuous = any(kw in command_lower for kw in [
                                "退出连续对话", "退出连续模式", "退出对话模式",
                            ])

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
                break

        stop_audio_stream()

    def _on_recognized(self, text: str):
        """识别结果 → 发送给 OpenClaw → TTS 播报回复"""
        print(f"\n[→ OpenClaw] {text}")
        print("◈ 正在思考...", end="", flush=True)

        import threading

        waiting_active = threading.Event()
        waiting_active.set()

        def _waiting_sound_loop():
            """每3秒播放一次waiting音效，直到AI开始回复"""
            while waiting_active.is_set():
                self.jarvis.play_sound("waiting")
                # 每3秒播放一次
                if waiting_active.wait(timeout=3.0):
                    break

        try:
            waiting_thread = threading.Thread(target=_waiting_sound_loop, daemon=True)
            waiting_thread.start()

            received_chunks = []

            def _on_stream_start():
                """AI开始回复时立即停止waiting音效"""
                waiting_active.clear()
                time.sleep(0.05)
                print("\n[← OpenClaw] ", end="", flush=True)

            def _on_stream_chunk(chunk):
                received_chunks.append(chunk)
                print(chunk, end="", flush=True)
                self.visual.show_ai_text("".join(received_chunks))

            def _on_stream_end():
                waiting_active.clear()

            reply = self.openclaw.send_and_wait_stream(
                text,
                on_chunk=_on_stream_chunk,
                on_start=_on_stream_start,
                on_end=_on_stream_end
            )

            waiting_active.clear()
            waiting_thread.join(timeout=0.5)

            if reply:
                print()
                tts_text = _clean_for_tts(reply)
                if tts_text:
                    print(f"[TTS] 合成 {len(tts_text)} 字...")
                    text_to_speech_play(tts_text)
                    self.jarvis.play_sound("continue")
                    print("◈ 继续说吧，我在听着...", flush=True)
            else:
                print("\n[← OpenClaw] (无回复)")
                self.jarvis.on_error("无回复")
        except Exception as e:
            waiting_active.clear()
            print(f"[OpenClaw] 异常: {e}")
            self.jarvis.on_error(str(e))

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


def assert_file_exists(filename):
    """检查文件是否存在"""
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
    parser.add_argument("--kws-tokens", type=str,
        default="models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01/tokens.txt")
    parser.add_argument("--kws-encoder", type=str,
        default="models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01/encoder-epoch-12-avg-2-chunk-16-left-64.onnx")
    parser.add_argument("--kws-decoder", type=str,
        default="models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01/decoder-epoch-12-avg-2-chunk-16-left-64.onnx")
    parser.add_argument("--kws-joiner", type=str,
        default="models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01/joiner-epoch-12-avg-2-chunk-16-left-64.onnx")
    parser.add_argument("--keywords-file", type=str, default="custom_keywords.txt")
    parser.add_argument("--keywords-score", type=float, default=0.15)
    parser.add_argument("--keywords-threshold", type=float, default=0.15)

    # 语音识别模型参数
    parser.add_argument("--asr-tokens", type=str,
        default="models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/tokens.txt")
    parser.add_argument("--asr-encoder", type=str,
        default="models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/encoder-epoch-99-avg-1.onnx")
    parser.add_argument("--asr-decoder", type=str,
        default="models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/decoder-epoch-99-avg-1.onnx")
    parser.add_argument("--asr-joiner", type=str,
        default="models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/joiner-epoch-99-avg-1.onnx")

    parser.add_argument("--provider", type=str, default="cpu")

    return parser.parse_args()


def main():
    args = get_args()

    # 检查模型文件
    for f in [args.kws_tokens, args.kws_encoder, args.kws_decoder, args.kws_joiner, args.keywords_file,
              args.asr_tokens, args.asr_encoder, args.asr_decoder, args.asr_joiner]:
        assert_file_exists(f)

    assistant = VoiceAssistant(args)
    assistant.run()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n程序被用户中断")
    except Exception as e:
        print(f"发生错误: {e}")
