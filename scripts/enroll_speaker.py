#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
声纹录入脚本
单独运行，用于录制和注册声纹样本
"""

import os
import sys
import time
import argparse
import json
import numpy as np
import soundfile as sf
import sherpa_onnx

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SAMPLE_DIR = os.path.join(PROJECT_DIR, "data", "enrollment")
SPEAKERS_FILE = os.path.join(SAMPLE_DIR, "speakers.json")
MODEL_PATH = os.path.join(
    PROJECT_DIR, "models", "3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx"
)
ASR_MODEL_DIR = os.path.join(
    PROJECT_DIR, "models", "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17"
)


def log(msg):
    """打印日志并立即刷新"""
    print(msg)
    sys.stdout.flush()


def set_dnd_mode(enabled: bool):
    """通过 HTTP 请求启用/禁用 DND 模式"""
    sys.path.insert(0, os.path.join(PROJECT_DIR, "src"))
    from local_api_auth import post_local_api
    try:
        path = "dnd" if enabled else "dnd/disable"
        with post_local_api(path, timeout=2) as resp:
            resp.read()
    except Exception:
        pass


def load_speakers():
    """加载已注册的声纹列表"""
    if os.path.exists(SPEAKERS_FILE):
        with open(SPEAKERS_FILE, 'r') as f:
            return json.load(f)
    return []


def save_speakers(speakers):
    """保存声纹列表到文件"""
    with open(SPEAKERS_FILE, 'w') as f:
        json.dump(speakers, f, indent=2)


def create_recognizer():
    """创建与主程序共用的 SenseVoice 离线识别器。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--asr-tokens", default=os.path.join(ASR_MODEL_DIR, "tokens.txt"))
    parser.add_argument("--asr-model", default=os.path.join(ASR_MODEL_DIR, "model.int8.onnx"))
    args = parser.parse_args([])
    return sherpa_onnx.OfflineRecognizer.from_sense_voice(
        model=args.asr_model,
        tokens=args.asr_tokens,
        num_threads=2,
        use_itn=True,
        language="auto",
    )


def recognize_audio(recognizer, samples, sample_rate=16000):
    """识别一段已经按静音切好的音频，空段返回空字符串。"""
    samples = np.asarray(samples, dtype=np.float32).reshape(-1)
    if len(samples) < int(sample_rate * 0.2):
        return ""
    stream = recognizer.create_stream()
    stream.accept_waveform(sample_rate, samples)
    recognizer.decode_stream(stream)
    return (stream.result.text or "").strip()


def completed_speech_segments(samples, sample_rate=16000, *, final=False):
    """返回当前缓冲中已被尾部静音封口的语音区间。

    录制仍在继续时保留最后 0.45 秒作为判定窗口，避免把一句尚未说完的话
    提前送去离线识别；录制结束时则刷新最后一段。
    """
    import librosa

    samples = np.asarray(samples, dtype=np.float32).reshape(-1)
    if not len(samples):
        return []
    raw_intervals = librosa.effects.split(
        samples,
        top_db=28,
        frame_length=512,
        hop_length=160,
    )
    # SenseVoice 对完整短句明显优于零碎音节。合并 180ms 内的小停顿，避免
    # “Is JARVIS here”被呼吸、爆破音切成数段后分别产生无意义结果。
    merge_gap = int(sample_rate * 0.18)
    max_segment = int(sample_rate * 4.5)
    intervals = []
    for start, end in raw_intervals:
        start, end = int(start), int(end)
        if (
            intervals
            and start - intervals[-1][1] <= merge_gap
            and end - intervals[-1][0] <= max_segment
        ):
            intervals[-1] = (intervals[-1][0], end)
        else:
            intervals.append((start, end))
    cutoff = len(samples) if final else max(0, len(samples) - int(sample_rate * 0.45))
    minimum = int(sample_rate * 0.25)
    return [
        (start, end)
        for start, end in intervals
        if end <= cutoff and end - start >= minimum
    ]


def enroll_speaker():
    """执行声纹录入流程"""
    log("\n" + "=" * 50)
    log("声纹录入模式")
    log("=" * 50)
    log("请在 20 秒内重复朗读「Is JARVIS here」")
    log("每次朗读都会识别成文字显示")
    log("=" * 50)

    os.makedirs(SAMPLE_DIR, exist_ok=True)

    # 启用勿扰模式，暂停唤醒词监听
    set_dnd_mode(True)
    log("已暂停唤醒词监听")

    try:
        log("初始化声纹提取器...")
        config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(
            model=MODEL_PATH, num_threads=2
        )
        extractor = sherpa_onnx.SpeakerEmbeddingExtractor(config)
        dim = extractor.dim
        manager = sherpa_onnx.SpeakerEmbeddingManager(dim)
        log(f"声纹提取器初始化成功，维度: {dim}")

        log("初始化语音识别器...")
        recognizer = create_recognizer()
        log("语音识别器初始化成功")

        import sounddevice as sd
    except ImportError:
        log("错误：需要安装 sounddevice")
        log("请运行: pip install sounddevice")
        set_dnd_mode(False)
        sys.exit(1)

    try:
        sample_rate = 16000
        duration = 20

        log("\n" + "=" * 50)
        log("请在 20 秒内重复朗读「Is JARVIS here」")
        log("=" * 50)

        for i in range(3, 0, -1):
            log(f"准备录音: {i}...")
            time.sleep(1)

        log("开始录音，请重复朗读「Is JARVIS here」！")
        log(f"录音时长: {duration} 秒")

        recording = sd.rec(
            int(duration * sample_rate), samplerate=sample_rate, channels=1, dtype="float32"
        )

        recognized_texts = []
        recognized_until = 0

        for i in range(duration, 0, -1):
            log(f"录音中... {i}秒")
            time.sleep(1)

            # sd.rec 非阻塞地持续填充 recording；每秒扫描一次已经结束于静音的
            # 语音段，使用 SenseVoice 离线识别。最后一段未结束时暂不抢跑。
            current_pos = min(int((duration - i + 1) * sample_rate), len(recording))
            captured = recording[:current_pos].flatten().copy()
            for start, end in completed_speech_segments(captured, sample_rate):
                if end <= recognized_until:
                    continue
                text = recognize_audio(recognizer, captured[start:end], sample_rate)
                recognized_until = end
                if text:
                    recognized_texts.append(text)
                    log(f"  识别: {text}")

        log("录音完成！")
        sd.wait()

        # 刷新包括最后一秒在内的完整录音，确保最后一句不会因缺少尾部轮询而丢失。
        complete_recording = recording.flatten().copy()
        for start, end in completed_speech_segments(
            complete_recording, sample_rate, final=True
        ):
            if end <= recognized_until:
                continue
            text = recognize_audio(
                recognizer, complete_recording[start:end], sample_rate
            )
            recognized_until = end
            if text:
                recognized_texts.append(text)
                log(f"  识别: {text}")

        log("\n" + "=" * 50)
        log("识别结果:")
        for t in recognized_texts:
            log(f"  - {t}")
        if not recognized_texts:
            log("  [错误] 未识别到有效语音，请检查麦克风后重新录入")
            raise RuntimeError("声纹录入未通过语音识别检查")
        log("=" * 50)

        timestamp = int(time.time() * 1000)
        wav_path = os.path.join(SAMPLE_DIR, f"{timestamp}.wav")
        sf.write(wav_path, recording, sample_rate)
        log(f"录音已保存: {wav_path}")

        # 用 ffmpeg 去除静音部分，只保留有声音的片段
        log("正在去除静音片段...")
        import librosa
        samples, _ = sf.read(wav_path, dtype='float32')
        samples = samples.flatten()
        trimmed, _ = librosa.effects.trim(samples, top_db=20)
        if len(trimmed) < len(samples):
            log(f"静音已去除，剩余音频长度: {len(trimmed)} samples ({len(trimmed)/sample_rate:.1f}s)")
            samples = trimmed
        stream = extractor.create_stream()
        stream.accept_waveform(sample_rate=sample_rate, waveform=samples)
        stream.input_finished()
        embedding = extractor.compute(stream)
        embedding = np.array(embedding)
        log(f"声纹提取成功，shape: {embedding.shape}")

        username = f"user_{timestamp}"
        success = manager.add(username, embedding)
        if success:
            speakers = load_speakers()
            speakers.append({
                "name": username,
                "timestamp": timestamp,
                "wav_file": f"{timestamp}.wav"
            })
            save_speakers(speakers)
            log(f"✓ 声纹注册成功: {username}")
            log("\n声纹录入完成！")
        else:
            log("✗ 声纹注册失败")
    finally:
        set_dnd_mode(False)
        log("已恢复唤醒词监听")


def clear_all_speakers():
    """清空所有声纹"""
    log("正在清空所有声纹...")
    
    # 删除所有 WAV 文件
    if os.path.exists(SAMPLE_DIR):
        for file in os.listdir(SAMPLE_DIR):
            if file.endswith('.wav'):
                file_path = os.path.join(SAMPLE_DIR, file)
                os.remove(file_path)
                log(f"  已删除: {file}")
    
    # 清空 speakers.json
    if os.path.exists(SPEAKERS_FILE):
        save_speakers([])
    
    log("✓ 所有声纹已清空")


def list_speakers():
    """列出所有已注册的声纹"""
    speakers = load_speakers()
    if not speakers:
        log("暂无已注册的声纹")
        return
    
    log(f"已注册声纹 ({len(speakers)} 个):")
    for speaker in speakers:
        log(f"  - {speaker['name']}")


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='声纹录入工具')
    parser.add_argument('--clear', action='store_true', help='清空所有声纹')
    parser.add_argument('--list', action='store_true', help='列出所有声纹')
    args = parser.parse_args()
    
    if args.clear:
        clear_all_speakers()
    elif args.list:
        list_speakers()
    else:
        enroll_speaker()
