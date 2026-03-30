#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
预生成固定 TTS 语料脚本
运行一次生成唤醒和退出的音频文件，后续直接复用
"""

import asyncio
import os
import sys

import edge_tts

# 配置
VOICE_EN = "en-US-GuyNeural"
RATE = "+15%"
VOICES_DIR = os.path.join(os.path.dirname(__file__), "voices")

# 固定语料
PROMPTS = {
    "wake": "At your service, sir.",
    "exit": "Very well. Standing by, sir.",
}


async def generate_voice(text: str, filename: str):
    """生成单个语音文件"""
    output_path = os.path.join(VOICES_DIR, filename)
    if os.path.exists(output_path):
        print(f"已存在: {output_path}")
        return

    try:
        communicate = edge_tts.Communicate(text, VOICE_EN, rate=RATE)
        await communicate.save(output_path)
        print(f"生成成功: {output_path}")
    except Exception as e:
        print(f"生成失败 [{filename}]: {e}")
        sys.exit(1)


async def main():
    # 创建目录
    os.makedirs(VOICES_DIR, exist_ok=True)
    print(f"语料目录: {VOICES_DIR}")

    # 生成所有语料
    tasks = [
        generate_voice(PROMPTS["wake"], "wake.mp3"),
        generate_voice(PROMPTS["exit"], "exit.mp3"),
    ]
    await asyncio.gather(*tasks)

    print("\n所有语料生成完成！")
    print("现在可以在 main.py 中使用 play_prebuilt_voice() 函数播放这些音频")


if __name__ == "__main__":
    asyncio.run(main())
