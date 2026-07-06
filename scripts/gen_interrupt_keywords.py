#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
手动生成打断词文件（keywords/interrupt/<id>.txt）——调试/预览用。

正常无需运行：语音助手启动时会自动生成（见 src/main.py 调用 interrupt_keywords.generate_all）。
本脚本只是同一逻辑的手动入口，方便改 assistants.json 后立即预览生成结果。

真源：assistants.json 里每个助手的 `interrupt_words`（中文/英文短语）。
中文走 pypinyin，英文查 KWS 模型的 en.phone。用法：
  python scripts/gen_interrupt_keywords.py
"""

import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(_ROOT, "src"))

from interrupt_keywords import generate_all  # noqa: E402

# 默认 KWS 模型目录（含 en.phone，供英文打断词查表）；与 main.py 的 --kws-tokens 默认一致。
_DEFAULT_KWS_MODEL_DIR = os.path.join(
    _ROOT, "models", "sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
)


def main() -> None:
    model_dir = sys.argv[1] if len(sys.argv) > 1 else _DEFAULT_KWS_MODEL_DIR
    result = generate_all(_ROOT, model_dir, verbose=True)
    if not result:
        print("assistants.json 未配置任何 interrupt_words，无文件生成")


if __name__ == "__main__":
    main()
