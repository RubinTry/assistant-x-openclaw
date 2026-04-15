#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
VITS MeloTTS 后端 - 中英文单说话人 TTS
模型: vits-melo-tts-zh_en (MeloTTS-Chinese, 44100Hz)
"""

import logging
import os
import re
import tempfile
import threading

import numpy as np
import sherpa_onnx
import soundfile as sf

logger = logging.getLogger(__name__)

_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VITS_DIR = os.path.join(_PROJECT_DIR, "models", "vits-melo-tts-zh_en")

# 规则 FST 用于文本规范化（日期、数字、电话号码）
_RULE_FSTS = ",".join(
    os.path.join(VITS_DIR, f)
    for f in ["date.fst", "number.fst", "phone.fst"]
    if os.path.isfile(os.path.join(VITS_DIR, f))
)

_tts = None


def _create_tts():
    global _tts
    if _tts is not None:
        return _tts

    tts_config = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            vits=sherpa_onnx.OfflineTtsVitsModelConfig(
                model=f"{VITS_DIR}/model.onnx",
                lexicon=f"{VITS_DIR}/lexicon.txt",
                tokens=f"{VITS_DIR}/tokens.txt",
            ),
            debug=False,
            num_threads=4,
            provider="cpu",
        ),
        rule_fsts=_RULE_FSTS,
    )

    if not tts_config.validate():
        raise ValueError("VITS MeloTTS 配置验证失败")

    _tts = sherpa_onnx.OfflineTts(tts_config)
    return _tts


def is_available():
    return (
        os.path.isfile(f"{VITS_DIR}/model.onnx")
        and os.path.isfile(f"{VITS_DIR}/lexicon.txt")
        and os.path.isfile(f"{VITS_DIR}/tokens.txt")
    )


def _trim_silence(audio_samples, sample_rate, threshold=0.01, keep_ms=150):
    if len(audio_samples) == 0:
        return audio_samples

    keep_samples = int(sample_rate * keep_ms / 1000)

    abs_audio = np.abs(audio_samples)
    last_idx = len(audio_samples)
    for i in range(len(audio_samples) - 1, -1, -1):
        if abs_audio[i] > threshold:
            last_idx = min(len(audio_samples), i + keep_samples)
            break

    trimmed = audio_samples[:last_idx]

    trimmed_ms = (len(audio_samples) - len(trimmed)) * 1000 / sample_rate
    if trimmed_ms > 10:
        logger.debug(f"修剪尾部静音: {trimmed_ms:.1f}ms")

    return trimmed


# ── 标点停顿处理 ──────────────────────────────────────────

# 句末标点 → 较长停顿(ms)；句中标点 → 较短停顿(ms)
_PAUSE_LONG = 380   # 。！？…
_PAUSE_SHORT = 200  # ，、；：,;:

# 含点号的技术术语 → 可发音形式（不区分大小写匹配）
_DOT_TERM_MAP = {
    "node.js": "Node点JS",
    "vue.js": "Vue点JS",
    "next.js": "Next点JS",
    "nuxt.js": "Nuxt点JS",
    "react.js": "React点JS",
    "express.js": "Express点JS",
    "nest.js": "Nest点JS",
    "three.js": "Three点JS",
    "d3.js": "D3点JS",
    "p5.js": "P5点JS",
    "bun.js": "Bun点JS",
    "deno.js": "Deno点JS",
    "electron.js": "Electron点JS",
    "ember.js": "Ember点JS",
    "backbone.js": "Backbone点JS",
    "asp.net": "ASP点NET",
    ".net": "点NET",
    "vb.net": "VB点NET",
    ".env": "点env",
    ".gitignore": "点git ignore",
    ".dockerignore": "点docker ignore",
    ".bashrc": "点bashrc",
    ".zshrc": "点zshrc",
    ".vscode": "点VS Code",
    ".config": "点config",
    ".yaml": "点yaml",
    ".yml": "点yml",
    ".json": "点JSON",
    ".toml": "点toml",
    ".xml": "点XML",
    ".csv": "点CSV",
    ".md": "点MD",
    ".py": "点py",
    ".ts": "点TS",
    ".js": "点JS",
    ".go": "点go",
    ".rs": "点rs",
    ".rb": "点rb",
    ".sh": "点sh",
    ".css": "点CSS",
    ".html": "点HTML",
    ".vue": "点vue",
    ".jsx": "点JSX",
    ".tsx": "点TSX",
    ".swift": "点swift",
    ".kt": "点kt",
    ".dart": "点dart",
    ".wasm": "点wasm",
    ".sql": "点SQL",
    ".txt": "点TXT",
    ".log": "点log",
    ".zip": "点zip",
    ".tar.gz": "点tar点gz",
    ".png": "点PNG",
    ".jpg": "点JPG",
    ".svg": "点SVG",
    ".pdf": "点PDF",
    ".mp3": "点MP3",
    ".mp4": "点MP4",
    ".wav": "点WAV",
    ".exe": "点EXE",
    ".app": "点app",
    ".dmg": "点DMG",
    ".ipa": "点IPA",
    ".apk": "点APK",
    # 常见域名后缀
    ".com": "点com",
    ".cn": "点cn",
    ".org": "点org",
    ".io": "点io",
    ".dev": "点dev",
    ".ai": "点ai",
    ".app": "点app",
    ".co": "点co",
    ".me": "点me",
    ".cc": "点cc",
    ".top": "点top",
    ".xyz": "点xyz",
    ".info": "点info",
    ".tech": "点tech",
    ".edu": "点edu",
    ".gov": "点gov",
}
# 按长度降序排列，优先匹配更长的术语
_DOT_TERM_PATTERN = re.compile(
    "|".join(re.escape(k) for k in sorted(_DOT_TERM_MAP, key=len, reverse=True)),
    re.IGNORECASE,
)


# 兜底：匹配域名中的点（字母/数字.字母/数字 的模式，如 www.baidu.com）
_DOMAIN_DOT_RE = re.compile(r'(?<=[A-Za-z0-9])\.(?=[A-Za-z0-9])')


def _replace_dot_terms(text: str) -> str:
    """将含点号的技术术语替换为可发音形式"""
    # 先替换已知术语
    text = _DOT_TERM_PATTERN.sub(lambda m: _DOT_TERM_MAP[m.group().lower()], text)
    # 兜底：剩余的 字母.字母 模式视为域名/术语，点读"点"
    # 但跳过已经替换过的（含"点"字的不会再匹配）
    # 仅匹配看起来像域名的模式（至少一个点两侧都是字母数字）
    text = _DOMAIN_DOT_RE.sub('点', text)
    return text


# 不可发音的符号 → 标准标点/移除
# 规则：连续破折号/省略号 → 句末停顿；括号引号等配对符号 → 句中停顿或移除
_NORMALIZE_MAP = [
    # Markdown 格式符号 → 移除
    (re.compile(r'\*{1,3}'), ''),
    (re.compile(r'`{1,3}'), ''),
    (re.compile(r'^#{1,6}\s*', re.MULTILINE), ''),
    (re.compile(r'~~'), ''),
    # 破折号 / 长横线 → 逗号（产生句中停顿）
    (re.compile(r'[—–\-]{2,}'), '，'),
    # 省略号变体 → 单个 …
    (re.compile(r'\.{3,}'), '…'),
    (re.compile(r'。{2,}'), '…'),
    # 配对引号/括号 → 移除（内容保留）
    (re.compile(r'[「」『』【】\[\]{}《》〈〉]'), ''),
    (re.compile(r'["""\'\']'), ''),
    # 分隔线/装饰符 → 移除
    (re.compile(r'[│┃┆┇╎╏|]'), ''),
    (re.compile(r'[★☆●◎◆◇■□▲△▼▽♦♠♣♥]'), ''),
    (re.compile(r'[→←↑↓⇒⇐⇑⇓➜➤▶►◀◄]'), ''),
    (re.compile(r'[─━┈┉═]{2,}'), ''),
    # 数学/特殊 → 移除
    (re.compile(r'[§†‡※◈]'), ''),
    # 连续空白/换行 → 单空格
    (re.compile(r'\s+'), ' '),
]


def _normalize_for_tts(text: str) -> str:
    """将不可发音的符号规范化为标准标点或移除"""
    # 先处理含点号的术语和域名（在省略号规则之前）
    text = _replace_dot_terms(text)
    for pattern, replacement in _NORMALIZE_MAP:
        text = pattern.sub(replacement, text)
    return text.strip()


# 按标点拆分文本，保留标点归属到前一段
_SPLIT_RE = re.compile(r'(?<=[。！？…，、；：,;:!?～])')


def _split_with_pauses(text: str) -> list[tuple[str, int]]:
    """将文本按标点拆分，返回 [(片段, 后续停顿ms), ...]"""
    segments = _SPLIT_RE.split(text)
    result = []
    for seg in segments:
        seg = seg.strip()
        if not seg:
            continue
        # 根据片段末尾标点决定停顿时长
        if seg[-1] in "。！？…!?":
            pause = _PAUSE_LONG
        elif seg[-1] in "，、；：,;:～":
            pause = _PAUSE_SHORT
        else:
            pause = 0
        result.append((seg, pause))
    # 最后一段不需要额外停顿
    if result:
        result[-1] = (result[-1][0], 0)
    return result


def _generate_with_pauses(tts, text: str, speed: float, sid: int = 0,
                          callback=None) -> tuple[np.ndarray, int] | None:
    """分段合成并在标点处插入静音停顿"""
    text = _normalize_for_tts(text)
    segments = _split_with_pauses(text)
    if not segments:
        return None

    all_audio = []
    sample_rate = None

    for seg_text, pause_ms in segments:
        if callback:
            result = tts.generate(seg_text, sid=sid, speed=speed, callback=callback)
        else:
            result = tts.generate(seg_text, sid=sid, speed=speed)

        if len(result.samples) == 0:
            continue

        sample_rate = result.sample_rate
        audio_arr = np.array(result.samples, dtype=np.float32)
        audio_arr = _trim_silence(audio_arr, sample_rate)
        all_audio.append(audio_arr)

        if pause_ms > 0:
            silence = np.zeros(int(sample_rate * pause_ms / 1000), dtype=np.float32)
            all_audio.append(silence)

    if not all_audio or sample_rate is None:
        return None

    return (np.concatenate(all_audio), sample_rate)


def synthesize(text: str, output_path: str = None, speed: float = 0.85) -> str | None:
    if not is_available():
        logger.error("VITS MeloTTS 不可用")
        return None

    if not text or not text.strip():
        return None

    if output_path is None:
        fd, output_path = tempfile.mkstemp(suffix=".wav")
        os.close(fd)

    try:
        tts = _create_tts()
        result = _generate_with_pauses(tts, text, speed)

        if result is None:
            logger.error("合成失败，返回音频为空")
            return None

        trimmed_audio, sample_rate = result
        actual_duration = len(trimmed_audio) / sample_rate

        sf.write(
            output_path, trimmed_audio, samplerate=sample_rate, subtype="PCM_16"
        )
        logger.info(f"合成成功: {output_path} ({actual_duration:.2f}s)")
        return output_path

    except Exception as e:
        logger.error(f"合成异常: {e}")
        return None


def synthesize_to_array(text: str, speed: float = 0.85) -> tuple[np.ndarray, int] | None:
    if not is_available():
        logger.error("VITS MeloTTS 不可用")
        return None

    if not text or not text.strip():
        return None

    try:
        tts = _create_tts()
        result = _generate_with_pauses(tts, text, speed)

        if result is None:
            logger.error("合成失败，返回音频为空")
            return None

        return result

    except Exception as e:
        logger.error(f"预合成异常: {e}")
        return None


def synthesize_streaming(text: str, stop_event: threading.Event = None, volume: float = 1.5) -> bool:
    if not is_available():
        logger.error("VITS MeloTTS 不可用")
        return False

    if not text or not text.strip():
        return False

    try:
        import sounddevice as sd

        tts = _create_tts()

        def on_stop_check(samples, progress):
            if stop_event and stop_event.is_set():
                return 1
            return 0

        result = _generate_with_pauses(tts, text, 0.85, callback=on_stop_check)

        if stop_event and stop_event.is_set():
            return False

        if result is None:
            return False

        audio_data, sample_rate = result

        if len(audio_data) == 0:
            return False

        sd.play(audio_data * volume, samplerate=sample_rate)
        sd.wait()
        return True

    except Exception as e:
        logger.warning(f"合成播放失败: {e}")
        return False
