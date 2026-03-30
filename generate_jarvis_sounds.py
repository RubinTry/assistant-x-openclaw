#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
现代柔和风格音效生成器 v2
更平滑、自然、柔和的音色
使用 sine + 轻声敲击波 + 柔和噪音
"""

import os
import math
import wave
import array
import random

SAMPLE_RATE = 22050
VOICES_DIR = os.path.join(os.path.dirname(__file__), "voices")


def ensure_dir():
    os.makedirs(VOICES_DIR, exist_ok=True)


def generate_soft_tone(freq, duration, volume=0.2, detune=0.002):
    """生成柔和双振荡器音色"""
    n_samples = int(SAMPLE_RATE * duration)
    samples = array.array('h')

    for i in range(n_samples):
        t = i / SAMPLE_RATE
        attack = min(0.05, duration * 0.1)
        release = min(0.1, duration * 0.2)

        if t < attack:
            env = t / attack
        elif t > duration - release:
            env = (duration - t) / release
        else:
            env = 1.0

        osc1 = math.sin(2 * math.pi * freq * t)
        osc2 = math.sin(2 * math.pi * freq * (1 + detune) * t)
        val = (osc1 * 0.7 + osc2 * 0.3) * env * volume

        samples.append(int(32767 * max(-1, min(1, val))))
    return samples


def generate_soft_bell(freq, duration, volume=0.2):
    """生成柔和钟声音色"""
    n_samples = int(SAMPLE_RATE * duration)
    samples = array.array('h')

    for i in range(n_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 2.5)
        val = 0
        for h, amp in [(1, 1), (2.1, 0.5), (3.5, 0.25), (5.0, 0.1)]:
            val += math.sin(2 * math.pi * freq * h * t) * amp
        val *= env * volume
        samples.append(int(32767 * max(-1, min(1, val))))
    return samples


def generate_soft_noise(duration, volume=0.05):
    """生成极轻柔的白噪音"""
    n_samples = int(SAMPLE_RATE * duration)
    samples = array.array('h')

    for i in range(n_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 3)
        val = (random.random() * 2 - 1) * env * volume
        samples.append(int(32767 * max(-1, min(1, val))))
    return samples


def generate_breath(duration, volume=0.08):
    """生成呼吸般的气流声"""
    n_samples = int(SAMPLE_RATE * duration)
    samples = array.array('h')

    for i in range(n_samples):
        t = i / SAMPLE_RATE
        attack, decay, sustain, release = 0.08, 0.1, 0.6, 0.15
        if t < attack:
            env = t / attack
        elif t < attack + decay:
            env = 1.0 - (1.0 - sustain) * (t - attack) / decay
        elif t < duration - release:
            env = sustain
        else:
            env = sustain * (duration - t) / release

        val = (random.random() * 2 - 1) * env * volume
        samples.append(int(32767 * max(-1, min(1, val))))
    return samples


def blend(s1, s2, ratio=0.5):
    min_len = min(len(s1), len(s2))
    result = array.array('h')
    for i in range(min_len):
        val = int(s1[i] * ratio + s2[i] * (1 - ratio))
        result.append(max(-32768, min(32767, val)))
    return result


def save_wav(filename, samples):
    filepath = os.path.join(VOICES_DIR, filename)
    with wave.open(filepath, 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(samples.tobytes())
    print(f"生成: {filepath}")


def generate_sounds():
    ensure_dir()

    # 1. system_ready.wav - 系统就绪（极轻柔上行泛音）
    print("生成 system_ready.wav...")
    s1 = generate_soft_tone(330, 0.3, 0.15)
    s2 = generate_soft_tone(440, 0.25, 0.12)
    s3 = generate_soft_tone(550, 0.4, 0.15)
    combined = blend(s1, s2, 0.5)
    combined = blend(combined, s3, 0.7)
    save_wav("system_ready.wav", combined)

    # 2. wake.wav - 唤醒（柔和明亮上升）
    print("生成 wake.wav...")
    s1 = generate_soft_tone(440, 0.12, 0.15)
    s2 = generate_soft_tone(550, 0.12, 0.15)
    s3 = generate_soft_tone(660, 0.12, 0.15)
    s4 = generate_soft_tone(880, 0.5, 0.18)
    combined = blend(s1, s2, 0.5)
    combined = blend(combined, s3, 0.6)
    combined = blend(combined, s4, 0.8)
    save_wav("wake.wav", combined)

    # 3. processing.wav - 处理中（轻柔脉冲）
    print("生成 processing.wav...")
    samples = array.array('h')
    for i in range(5):
        freq = 480 + i * 20
        s = generate_soft_tone(freq, 0.08, 0.12)
        samples.extend(s)
        samples.extend(array.array('h', [0] * int(SAMPLE_RATE * 0.06)))
    save_wav("processing.wav", samples)

    # 4. thinking.wav - 思考中（柔和下行）
    print("生成 thinking.wav...")
    samples = array.array('h')
    for freq in [420, 380, 350, 300]:
        s = generate_soft_tone(freq, 0.18, 0.12)
        samples.extend(s)
        samples.extend(array.array('h', [0] * int(SAMPLE_RATE * 0.05)))
    save_wav("thinking.wav", samples)

    # 5. execute.wav - 执行（柔和完成）
    print("生成 execute.wav...")
    s1 = generate_soft_tone(440, 0.15, 0.15)
    s2 = generate_soft_tone(554, 0.2, 0.15)
    s3 = generate_soft_tone(659, 0.35, 0.18)
    combined = blend(s1, s2, 0.6)
    combined = blend(combined, s3, 0.8)
    save_wav("execute.wav", combined)

    # 6. success.wav - 成功（轻柔三和弦）
    print("生成 success.wav...")
    c = generate_soft_tone(523, 0.2, 0.12)
    e = generate_soft_tone(659, 0.2, 0.12)
    g = generate_soft_tone(784, 0.35, 0.15)
    combined = blend(c, e, 0.5)
    combined = blend(combined, g, 0.7)
    save_wav("success.wav", combined)

    # 7. error.wav - 错误（柔和下降）
    print("生成 error.wav...")
    s1 = generate_soft_tone(380, 0.2, 0.15)
    s2 = generate_soft_tone(320, 0.25, 0.13)
    s3 = generate_soft_tone(260, 0.35, 0.1)
    combined = blend(s1, s2, 0.6)
    combined = blend(combined, s3, 0.7)
    save_wav("error.wav", combined)

    # 8. exit.wav - 退出（渐隐柔和）
    print("生成 exit.wav...")
    s1 = generate_soft_tone(550, 0.2, 0.13)
    s2 = generate_soft_tone(440, 0.25, 0.11)
    s3 = generate_soft_tone(330, 0.4, 0.08)
    combined = blend(s1, s2, 0.6)
    combined = blend(combined, s3, 0.7)
    save_wav("exit.wav", combined)

    # 9. blaster.wav - 命令识别（极轻柔提示音）
    print("生成 blaster.wav...")
    s1 = generate_soft_bell(880, 0.12, 0.15)
    s2 = generate_soft_bell(1100, 0.1, 0.12)
    combined = blend(s1, s2, 0.7)
    save_wav("blaster.wav", combined)

    # 10. waiting.wav - 等待中（轻柔流水/水滴声，自然舒缓）
    print("生成 waiting.wav...")
    samples = array.array('h')
    random.seed(42)
    
    # 生成轻柔的水滴声 - 更低频、更柔和
    for i in range(6):
        # 随机间隔，模拟自然水滴
        drop_delay = int(SAMPLE_RATE * (0.3 + random.random() * 0.2))
        # 更低的频率，更柔和
        freq = 400 + random.random() * 200
        freq_end = freq * 0.6
        drop_len = 0.15 + random.random() * 0.1
        
        for j in range(int(SAMPLE_RATE * drop_len)):
            t = j / SAMPLE_RATE
            # 更慢的衰减，更自然
            env = math.exp(-t * 8)
            # 频率滑动模拟水滴效果
            freq_cur = freq + (freq_end - freq) * (t / drop_len)
            # 使用正弦波 + 轻微谐波，模拟水滴的泛音
            val = math.sin(2 * math.pi * freq_cur * t) * 0.8
            val += math.sin(2 * math.pi * freq_cur * 1.5 * t) * 0.2
            val *= env * 0.08  # 更低的音量
            samples.append(int(32767 * max(-1, min(1, val))))
        
        samples.extend(array.array('h', [0] * drop_delay))
    
    # 添加极轻柔的背景氛围音（类似微风/流水）
    bg_duration = len(samples) / SAMPLE_RATE
    bg_samples = array.array('h')
    for i in range(len(samples)):
        t = i / SAMPLE_RATE
        # 极低频的随机波动，模拟自然背景
        noise = (random.random() * 2 - 1) * 0.03
        # 添加缓慢变化的低频正弦波
        lfo = math.sin(2 * math.pi * 0.5 * t) * 0.02
        val = (noise + lfo) * 0.5
        bg_samples.append(int(32767 * max(-1, min(1, val))))
    
    # 混合水滴声和背景音
    final_samples = array.array('h')
    for i in range(len(samples)):
        val = samples[i] * 0.9 + bg_samples[i] * 0.1
        final_samples.append(int(max(-32768, min(32767, val))))
    
    save_wav("waiting.wav", final_samples)

    # 11. continue.wav - 继续说话（轻柔提示）
    print("生成 continue.wav...")
    s1 = generate_soft_bell(523, 0.08, 0.12)
    s2 = generate_soft_bell(659, 0.1, 0.12)
    combined = blend(s1, s2, 0.6)
    save_wav("continue.wav", combined)

    print("\n所有现代柔和音效生成完成！")


if __name__ == "__main__":
    generate_sounds()
