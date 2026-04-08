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
import numpy as np
import soundfile as sf
import sherpa_onnx

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
SAMPLE_DIR = os.path.join(PROJECT_DIR, "data", "enrollment")
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

    try:
        import sounddevice as sd
    except ImportError:
        log("错误：需要安装 sounddevice")
        log("请运行: pip install sounddevice")
        sys.exit(1)

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
    start_time = time.time()

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

    log("正在提取声纹...")
    samples = recording.flatten()
    stream = extractor.create_stream()
    stream.accept_waveform(sample_rate=sample_rate, waveform=samples)
    stream.input_finished()
    embedding = extractor.compute(stream)
    embedding = np.array(embedding)
    log(f"声纹提取成功，shape: {embedding.shape}")

    username = f"user_{timestamp}"
    success = manager.add(username, embedding)
    if success:
        log(f"✓ 声纹注册成功: {username}")
        log("\n声纹录入完成！")
    else:
        log("✗ 声纹注册失败")
        sys.exit(1)


if __name__ == "__main__":
    enroll_speaker()
