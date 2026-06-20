#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
将 AASIST / AASIST-L 权重导出为 ONNX，供本项目的 src/anti_spoof.py 使用。

==============================================================================
使用步骤
==============================================================================
1) 克隆官方仓库并装依赖：
       git clone https://github.com/clovaai/aasist
       cd aasist
       pip install torch numpy

   仓库自带预训练权重：
       models/weights/AASIST.pth        （完整版，效果最好）
       models/weights/AASIST-L.pth      （轻量版，85K 参数，适合实时/CPU）

2) 把本脚本拷到 aasist 仓库根目录下运行（它需要 import 仓库里的 models 包）：
       # 导出轻量版（推荐，实时场景）
       python export_aasist_onnx.py \
           --config config/AASIST-L.conf \
           --weights models/weights/AASIST-L.pth \
           --out aasist-l.onnx

       # 或导出完整版
       python export_aasist_onnx.py \
           --config config/AASIST.conf \
           --weights models/weights/AASIST.pth \
           --out aasist.onnx

3) 把导出的 aasist-l.onnx 放到本项目：
       <项目根>/models/aasist-l.onnx
   语音助手下次启动会自动检测并启用活体检测。

==============================================================================
说明
==============================================================================
- 输入：16kHz 单声道原始波形，长度固定 64600 采样点（≈4.04s）。
  src/anti_spoof.py 已按此规格做补齐/截断，无需改动。
- 输出：形状 (1, 2) 的二分类 logits，列 1 为 bonafide(活体)。
  anti_spoof.py 会做 softmax 取该列作为活体概率。
- 重要：官方权重在 ASVspoof LA(合成语音检测) 上训练。对"音箱重放真人录音"(PA)
  效果会弱一些。若主要威胁是音箱重放，建议用 PA/replay 数据微调后再导出，
  或采集自己设备的正负样本做阈值校准（调整 anti_spoof 的 threshold）。
"""

import argparse
import sys


def main():
    parser = argparse.ArgumentParser(description="Export AASIST checkpoint to ONNX")
    parser.add_argument("--config", required=True, help="AASIST 配置文件，如 config/AASIST-L.conf")
    parser.add_argument("--weights", required=True, help="权重 .pth，如 models/weights/AASIST-L.pth")
    parser.add_argument("--out", default="aasist-l.onnx", help="输出 ONNX 路径")
    parser.add_argument("--length", type=int, default=64600, help="导出用的固定输入长度（采样点）")
    parser.add_argument("--opset", type=int, default=14, help="ONNX opset 版本")
    args = parser.parse_args()

    try:
        import json
        import torch
        import importlib
    except Exception as e:
        print(f"缺少依赖（需要 torch）：{e}")
        sys.exit(1)

    # 读取配置并动态加载仓库内的 Model 定义（与 aasist/main.py 一致的方式）
    try:
        with open(args.config, "r") as f:
            config = json.load(f)
        model_config = config["model_config"]
        module = importlib.import_module("models.{}".format(model_config["architecture"]))
        Model = getattr(module, "Model")
    except Exception as e:
        print(f"加载模型定义失败，请确认本脚本在 clovaai/aasist 仓库根目录运行：{e}")
        sys.exit(1)

    device = "cpu"
    model = Model(model_config)
    state = torch.load(args.weights, map_location=device)
    # 兼容 DataParallel 前缀
    if any(k.startswith("module.") for k in state.keys()):
        state = {k.replace("module.", "", 1): v for k, v in state.items()}
    model.load_state_dict(state, strict=False)
    model.eval()

    dummy = torch.randn(1, args.length, dtype=torch.float32, device=device)

    # AASIST.forward 返回 (last_hidden, output)；我们只导出 output(二分类 logits)
    class _Wrapper(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x):
            out = self.m(x)
            if isinstance(out, (tuple, list)):
                return out[-1]
            return out

    wrapped = _Wrapper(model)

    torch.onnx.export(
        wrapped,
        dummy,
        args.out,
        input_names=["waveform"],
        output_names=["logits"],
        opset_version=args.opset,
        dynamic_axes=None,  # 固定 batch=1、长度固定，利于推理稳定
    )
    print(f"✓ 已导出 ONNX: {args.out}")
    print("  放入 <项目根>/models/aasist-l.onnx 即可启用活体检测")


if __name__ == "__main__":
    main()
