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
    PROJECT_DIR, "models", "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20"
)


def log(msg):
    """打印日志并立即刷新"""
    print(msg)
    sys.stdout.flush()


def set_dnd_mode(enabled: bool):
    """通过 HTTP 请求启用/禁用 DND 模式"""
    import urllib.request
    try:
        url = f"http://127.0.0.1:18790/{'dnd' if enabled else 'dnd/disable'}"
        req = urllib.request.Request(url, method='POST')
        with urllib.request.urlopen(req, timeout=2) as resp:
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
    """创建语音识别器"""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--asr-tokens",
        default=os.path.join(ASR_MODEL_DIR, "tokens.txt"),
    )
    parser.add_argument(
        "--asr-encoder",
        default=os.path.join(ASR_MODEL_DIR, "encoder-epoch-99-avg-1.onnx"),
    )
    parser.add_argument(
        "--asr-decoder",
        default=os.path.join(ASR_MODEL_DIR, "decoder-epoch-99-avg-1.onnx"),
    )
    parser.add_argument(
        "--asr-joiner",
        default=os.path.join(ASR_MODEL_DIR, "joiner-epoch-99-avg-1.onnx"),
    )
    parser.add_argument("--provider", default="cpu")
    args = parser.parse_args([])
    return sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=args.asr_tokens,
        encoder=args.asr_encoder,
        decoder=args.asr_decoder,
        joiner=args.asr_joiner,
        num_threads=1,
        sample_rate=16000,
        feature_dim=80,
        decoding_method="greedy_search",
        provider=args.provider,
    )


def recognize_audio(samples, sample_rate, recognizer):
    """识别音频为文字"""
    stream = recognizer.create_stream()
    stream.accept_waveform(sample_rate, samples)
    while recognizer.is_ready(stream):
        recognizer.decode_stream(stream)
    result = recognizer.get_result(stream)
    return result if result else ""


def enroll_speaker():
    """执行声纹录入流程"""
    log("\n" + "=" * 50)
    log("声纹录入模式")
    log("=" * 50)
    log("请在 20 秒内重复朗读「贾维斯」")
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
        log("请在 20 秒内重复朗读「贾维斯」")
        log("=" * 50)

        for i in range(3, 0, -1):
            log(f"准备录音: {i}...")
            time.sleep(1)

        log("开始录音，请重复朗读「贾维斯」！")
        log(f"录音时长: {duration} 秒")

        recording = sd.rec(
            int(duration * sample_rate), samplerate=sample_rate, channels=1, dtype="float32"
        )

        recognized_texts = []
        chunk_size = sample_rate

        for i in range(duration, 0, -1):
            log(f"录音中... {i}秒")
            time.sleep(1)

            current_pos = int((duration - i) * sample_rate)
            if current_pos > 0:
                chunk = recording[:current_pos].flatten()
                if len(chunk) >= chunk_size:
                    text = recognize_audio(chunk, sample_rate, recognizer)
                    if text and text not in recognized_texts:
                        recognized_texts.append(text)
                        log(f"  识别: {text}")

        log("录音完成！")
        sd.wait()

        log("\n" + "=" * 50)
        log("识别结果:")
        for t in recognized_texts:
            log(f"  - {t}")
        log("=" * 50)

        timestamp = int(time.time() * 1000)
        wav_path = os.path.join(SAMPLE_DIR, f"{timestamp}.wav")
        sf.write(wav_path, recording, sample_rate)
        log(f"录音已保存: {wav_path}")

        # 用 ffmpeg 去除静音部分，只保留有声音的片段
        log("正在去除静音片段...")
        import subprocess
        trimmed_path = os.path.join(SAMPLE_DIR, f"{timestamp}_trimmed.wav")
        try:
            result = subprocess.run([
                'ffmpeg', '-y', '-i', wav_path,
                '-af', 'silenceremove=start_periods=1:start_duration=0.1:start_threshold=-50dB:detection=peak,areverse,silenceremove=start_periods=1:start_duration=0.1:start_threshold=-50dB:detection=peak,areverse',
                '-ac', '1', '-ar', '16000',
                trimmed_path
            ], capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                os.remove(wav_path)
                os.rename(trimmed_path, wav_path)
                # 重新加载处理后的音频
                samples, _ = sf.read(wav_path, dtype='float32')
                log(f"静音已去除，剩余音频长度: {len(samples)} samples ({len(samples)/sample_rate:.1f}s)")
            else:
                log(f"ffmpeg 处理失败: {result.stderr}")
        except FileNotFoundError:
            log("警告: ffmpeg 未安装，跳过静音去除")
        except Exception as e:
            log(f"ffmpeg 处理出错: {e}")

        log("正在提取声纹...")
        # 重新加载（可能被 ffmpeg 修剪过的）音频
        samples, _ = sf.read(wav_path, dtype='float32')
        samples = samples.flatten()
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