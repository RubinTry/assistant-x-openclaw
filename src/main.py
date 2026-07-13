#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
语音助手程序 - 基于 sherpa-onnx
语音唤醒 + 流式语音识别
为 OpenClaw 联动预留接口
"""

import argparse
import difflib
import json
import os
import platform
import random
import signal
import sys
import time
import threading
import queue
import tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path


def _detect_best_provider() -> str:
    """根据硬件平台自动选择最优 provider"""
    if platform.system() != "Darwin":
        return "cpu"
    if platform.machine() == "arm64":
        return "coreml"
    return "mps"

_assistant_instance = None
PID_FILE = os.path.join(tempfile.gettempdir(), "voice_assistant.pid")
API_PORT = 18790


class _ExitAPIHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        global _dnd_mode
        # 注：模型表读写不在此 HTTP server 上——它只在助手启动时监听，而模型配置
        # 需在启动前就能做。改由 Control Center 直接调 venv 子进程 scripts/model_cli.py
        # 读写 model_table.json（助手运行时每轮读文件，配置改动自动生效）。
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
        elif self.path in ("/heavy/add", "/heavy/remove"):
            self.send_response(410)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "error": "heavy_patterns deprecated",
                "message": "Fast path now uses light_patterns.json as an allowlist.",
            }).encode())
        elif self.path == "/dnd":
            _dnd_mode = True
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "dnd": True}).encode())
        elif self.path == "/dnd/disable":
            _dnd_mode = False
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "dnd": False}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path == "/heavy/list":
            self.send_response(410)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "error": "heavy_patterns deprecated",
                "patterns": [],
                "message": "Fast path now uses light_patterns.json as an allowlist.",
            }).encode())
            return

        # 摄像头抓帧：抓一帧 JPEG 直接回给调用方（Hermes 用 curl -o 落地后交 vision_analyze）
        if self.path.startswith("/camera/snapshot"):
            import tempfile
            from camera import get_camera_controller

            cam = get_camera_controller()
            if not cam.is_available():
                self.send_response(503)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "camera unavailable"}).encode())
                return
            out = os.path.join(tempfile.gettempdir(), "jarvis_cam_snapshot.jpg")
            path = cam.capture(out)
            if path and os.path.exists(path) and os.path.getsize(path) > 0:
                data = open(path, "rb").read()
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_response(500)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(
                    {"error": "capture failed (摄像头未授权？首次需在控制中心授权)"}
                ).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass


def _start_api_server():
    # start.sh 清理端口与本进程绑定之间存在竞争窗口（僵尸进程刚退出、TIME_WAIT
    # 未释放等），单次绑定失败不代表端口长期不可用，重试几次再放弃。
    server = None
    last_err = None
    for attempt in range(5):
        try:
            server = HTTPServer(("127.0.0.1", API_PORT), _ExitAPIHandler)
            break
        except OSError as e:
            last_err = e
            time.sleep(0.5)
    if server is None:
        print(f"[API] 退出/勿扰接口启动失败：端口 {API_PORT} 持续被占用 ({last_err})。"
              f"/exit 与声纹录入的勿扰联动将不可用，可 lsof -ti:{API_PORT} | xargs kill 后重启。")
        return
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

try:
    import soxr as _soxr
except ImportError:
    _soxr = None  # 无 soxr 时退回原始采样率，ASR 精度会下降

from tts import (
    text_to_speech_play,
    is_tts_playing,
    play_prebuilt_voice,
    stop_tts,
    set_tts,
)
from log_setup import setup_logging, get_diag_logger
from lifecycle import get_lifecycle_manager
from media_pause import MediaPauseHook
from dock_control import DockAutohideHook

# 文件级诊断/错误日志（只落盘，不进控制中心）
_diag = get_diag_logger()
from assistants import (
    AssistantManager,
    AssistantInstance,
    get_manager,
)

# ── assistants.json 配置加载 ─────────────────────────────────
_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ASSISTANTS_CFG_PATH = os.path.join(_PROJECT_DIR, "assistants.json")
_ENV_PATH = os.path.join(_PROJECT_DIR, ".env")


def _load_dotenv(path: str = _ENV_PATH):
    """轻量加载 .env，不覆盖外部已设置的环境变量。"""
    if not os.path.exists(path):
        return
    try:
        with open(path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())
    except Exception as e:
        print(f"[配置] .env 加载失败（忽略）: {e}")


def _env_float(name: str, default: float) -> float:
    value = os.environ.get(name)
    if value is None or str(value).strip() == "":
        return default
    try:
        return float(value)
    except ValueError:
        print(f"[配置] {name}={value!r} 无效，使用默认值 {default}")
        return default


def _env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None or str(value).strip() == "":
        return default
    try:
        return int(value)
    except ValueError:
        print(f"[配置] {name}={value!r} 无效，使用默认值 {default}")
        return default


def _env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None or str(value).strip() == "":
        return default
    return str(value).strip().lower() in ("1", "true", "yes", "on", "y")


_load_dotenv()


# ── 主脑引擎选择（assistants.json 顶层 engine 字段，默认 openclaw）──────────
def _load_engine() -> str:
    """读取 assistants.json 顶层 engine：openclaw（默认）| hermes。"""
    try:
        with open(_ASSISTANTS_CFG_PATH, "r", encoding="utf-8") as f:
            return (json.load(f).get("engine") or "openclaw").strip().lower()
    except Exception:
        return "openclaw"


def _load_overlay_debug() -> bool:
    """读取 assistants.json 顶层 overlay_debug_mode：true 时特效召唤后不隐藏。"""
    try:
        with open(_ASSISTANTS_CFG_PATH, "r", encoding="utf-8") as f:
            return bool(json.load(f).get("overlay_debug_mode", False))
    except Exception:
        return False


def _load_fast_mode() -> bool:
    """读取 assistants.json 顶层 fastMode：true 时启用快路径分流。"""
    try:
        with open(_ASSISTANTS_CFG_PATH, "r", encoding="utf-8") as f:
            return bool(json.load(f).get("fastMode", False))
    except Exception:
        return False


def _load_dock_autohide() -> bool:
    """读取 assistants.json 顶层 dock_autohide_on_wake：true 时激活期自动隐藏 Dock。"""
    try:
        with open(_ASSISTANTS_CFG_PATH, "r", encoding="utf-8") as f:
            return bool(json.load(f).get("dock_autohide_on_wake", False))
    except Exception:
        return False


_ENGINE = _load_engine()
if _ENGINE == "hermes":
    from hermes_bridge import get_bridge  # noqa: E402

    print("[引擎] 主脑：Hermes（一角色一 profile 一网关）")
else:
    from openclaw_bridge_websocket import get_bridge  # noqa: E402

    if _ENGINE != "openclaw":
        print(f"[引擎] 未知 engine='{_ENGINE}'，回退 OpenClaw")
    else:
        print("[引擎] 主脑：OpenClaw")

# ── 声纹验证配置 ────────────────────────────────────────────
_SPEAKER_MODEL_PATH = os.path.join(_PROJECT_DIR, "models", "3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx")
_SPEAKER_DIR = os.path.join(_PROJECT_DIR, "data", "enrollment")
_SPEAKER_FILE = os.path.join(_SPEAKER_DIR, "speakers.json")
_SPEAKER_THRESHOLD = _env_float("VOICE_ASSISTANT_SPEAKER_THRESHOLD", 0.55)  # 声纹相似度阈值
_SPEAKER_NOTIFY_PORT = 18792  # control_center TCP 通知端口

# ── 活体检测配置（实验期默认 shadow mode：记录分数，不拦截唤醒）─────────────
_LIVENESS_ENABLED = _env_bool("VOICE_ASSISTANT_LIVENESS_ENABLED", True)
_LIVENESS_ENFORCE = _env_bool("VOICE_ASSISTANT_LIVENESS_ENFORCE", False)
_LIVENESS_THRESHOLD = _env_float("VOICE_ASSISTANT_LIVENESS_THRESHOLD", 0.5)
_LIVENESS_MODEL_PATH = os.path.join(
    _PROJECT_DIR,
    os.environ.get("VOICE_ASSISTANT_LIVENESS_MODEL", "models/aasist-l.onnx"),
)

# 本机媒体播放门禁：AASIST 对“电脑扬声器重放”可能给高活体分，
# 用 Now Playing 状态作为额外信号。默认 shadow，只记录不拦截。
_MEDIA_WAKE_GUARD_ENABLED = _env_bool("VOICE_ASSISTANT_MEDIA_WAKE_GUARD_ENABLED", True)
_MEDIA_WAKE_GUARD_ENFORCE = _env_bool("VOICE_ASSISTANT_MEDIA_WAKE_GUARD_ENFORCE", False)

# 音频流假死看门狗：macOS CoreAudio 在反复关停/重开 InputStream 后偶发
# "start 成功但回调不再送帧"。健康时即使无人说话也会持续产生静音帧，
# 因此"持续 N 秒拿不到任何帧"是死流的可靠信号，不会被正常静默误触发。
_AUDIO_STALL_TIMEOUT = 15  # 秒
_AUDIO_DEVICE_WATCH_ENABLED = _env_bool("VOICE_ASSISTANT_AUDIO_DEVICE_WATCH_ENABLED", True)
_AUDIO_DEVICE_POLL_INTERVAL = _env_float("VOICE_ASSISTANT_AUDIO_DEVICE_POLL_INTERVAL_SECONDS", 1.5)

_dnd_mode = False  # Do Not Disturb 模式，注册时不响应唤醒词


# ── 文本纠错表（兜底修复 sherpa-onnx ASR 误识别人名/术语）──────────────────
# 加载逻辑：读取 text_corrections.txt，每行格式 `<错误> : <正确>`，
# 在 ASR 最终结果（_process_recognition_result）送视觉/送 LLM 之前整词大小写
# 不敏感替换。sherpa hotwords 对 cjkchar+bpe 模型下 OOV 英文整词的偏置几乎
# 无效（整词 token 找不到就静默跳过），所以这条兜底是真正的可靠修复路径。
# 文件与 hotwords.txt 同级，main 启动时一次性加载，运行期可热重载（按需）。
import re as _re_corrections

_TEXT_CORRECTIONS_PATH = os.path.join(_PROJECT_DIR, "text_corrections.txt")
_TEXT_CORRECTIONS = []  # list[(compiled_pattern, replacement)]


def _load_text_corrections(path=None):
    """加载 text_corrections.txt 到 _TEXT_CORRECTIONS，返回加载条数。

    文件不存在时静默返回 0（纠错是可选功能）。运行期可重复调用做热重载。
    """
    global _TEXT_CORRECTIONS
    p = path or _TEXT_CORRECTIONS_PATH
    rules = []
    if not os.path.exists(p):
        _TEXT_CORRECTIONS = []
        return 0
    try:
        with open(p, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if ":" not in line:
                    continue
                bad, good = line.split(":", 1)
                bad = bad.strip()
                good = good.strip()
                if not bad:
                    continue
                # 整词大小写不敏感：re.escape 后用 \b...\b 包裹
                # flags 设为 re.IGNORECASE，匹配时保形替换为 good（good 自带期望大小写）
                pat = _re_corrections.compile(
                    r"(?<![A-Za-z0-9_])" + _re_corrections.escape(bad) + r"(?![A-Za-z0-9_])",
                    _re_corrections.IGNORECASE,
                )
                rules.append((pat, good))
    except Exception as e:
        print(f"[文本纠错] 加载失败: {e}")
        _TEXT_CORRECTIONS = []
        return 0
    _TEXT_CORRECTIONS = rules
    return len(rules)


def _apply_text_corrections(text):
    """应用所有纠错规则到 text，返回修正后字符串。无规则时返回原串。"""
    if not _TEXT_CORRECTIONS or not text:
        return text
    out = text
    for pat, repl in _TEXT_CORRECTIONS:
        out = pat.sub(repl, out)
    return out


_load_text_corrections()


def _notify_wake_rejected(payload=None):
    """通知 control_center 唤醒验证被拒绝"""
    import socket
    try:
        if payload:
            message = json.dumps(
                {"type": "wake_rejected", **payload},
                ensure_ascii=False,
            ).encode("utf-8") + b"\n"
        else:
            message = b"speaker_rejected\n"
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        sock.connect(("127.0.0.1", _SPEAKER_NOTIFY_PORT))
        sock.sendall(message)
        sock.close()
    except Exception:
        pass


def _set_dnd_mode(enabled: bool):
    """设置勿扰模式"""
    global _dnd_mode
    _dnd_mode = enabled
    print(f"[勿扰] 唤醒词监听{'已暂停' if _dnd_mode else '已恢复'}")


def _check_speaker_model():
    """检查声纹模型是否存在"""
    return os.path.exists(_SPEAKER_MODEL_PATH)


def _load_speakers():
    """加载已注册的声纹列表"""
    if os.path.exists(_SPEAKER_FILE):
        with open(_SPEAKER_FILE, 'r') as f:
            return json.load(f)
    return []


def _save_speakers(speakers):
    """保存声纹列表到文件"""
    with open(_SPEAKER_FILE, 'w') as f:
        json.dump(speakers, f, indent=2)


def _create_speaker_extractor():
    """创建声纹提取器"""
    if not _check_speaker_model():
        return None
    try:
        config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(
            model=_SPEAKER_MODEL_PATH, num_threads=2
        )
        return sherpa_onnx.SpeakerEmbeddingExtractor(config)
    except Exception as e:
        print(f"[声纹] 初始化提取器失败: {e}")
        return None


def _create_speaker_manager(dim):
    """创建声纹管理器"""
    return sherpa_onnx.SpeakerEmbeddingManager(dim)


def _extract_embedding(extractor, samples, sample_rate=16000):
    """从音频样本中提取声纹嵌入"""
    try:
        # 检查样本是否有效
        if not samples or len(samples) == 0:
            print("[声纹] 提取嵌入失败: 样本为空")
            return None
        
        # 确保样本是列表类型
        if hasattr(samples, 'tolist'):
            samples = samples.tolist()
        elif not isinstance(samples, list):
            samples = list(samples)
        
        stream = extractor.create_stream()
        stream.accept_waveform(sample_rate=sample_rate, waveform=samples)
        stream.input_finished()
        
        # 检查是否就绪
        if not extractor.is_ready(stream):
            print(f"[声纹调试] 提取嵌入失败: 流未就绪 (样本过短)，samples={len(samples)}")
            return None

        embedding = extractor.compute(stream)
        embedding = np.array(embedding)
        print(f"[声纹调试] 嵌入提取成功，shape: {embedding.shape}, 前5值: {embedding[:5].tolist()}")
        return embedding
    except Exception as e:
        print(f"[声纹] 提取嵌入失败: {e}")
        import traceback
        traceback.print_exc()
        return None


def _verify_speaker(extractor, manager, samples, sample_rate=16000):
    """验证说话人身份
    
    Returns:
        (is_verified, speaker_name, score)
    """
    if extractor is None or manager is None:
        return False, None, 0.0
    
    embedding = _extract_embedding(extractor, samples, sample_rate)
    if embedding is None:
        return False, None, 0.0
    
    # 搜索最匹配的声纹
    try:
        emb_list = embedding.tolist()
        print(f"[声纹调试] 嵌入向量前5值: {emb_list[:5]}")
        print(f"[声纹调试] 已注册声纹: {manager.all_speakers}")
        result = manager.search(emb_list, _SPEAKER_THRESHOLD)
        print(f"[声纹调试] search result: '{result}', threshold: {_SPEAKER_THRESHOLD}")
        if result:
            # 计算相似度分数
            score = manager.score(result, emb_list)
            print(f"[声纹调试] score for '{result}': {score}")
            return True, result, score
    except Exception as e:
        print(f"[声纹] 验证失败: {e}")
    
    return False, None, 0.0


def _load_all_assistant_configs() -> tuple[dict, list]:
    """加载所有启用的 assistant 配置

    Returns:
        (default_config, list_of_all_enabled_configs)
    """
    with open(_ASSISTANTS_CFG_PATH, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    default_id = cfg.get("default")
    all_assistants = cfg.get("assistants", [])

    # 过滤启用的 assistant
    enabled_assistants = [a for a in all_assistants if a.get("enabled", True)]

    if not enabled_assistants:
        raise ValueError("assistants.json 中没有启用的 assistant")

    # 找到默认配置
    default_config = None
    for a in enabled_assistants:
        if a["id"] == default_id:
            default_config = a
            break

    # 如果默认不在启用列表中，使用第一个启用的
    if default_config is None:
        default_config = enabled_assistants[0]

    return default_config, enabled_assistants


def _load_assistant_config(assistant_id: str = None) -> dict:
    """从 assistants.json 加载指定 assistant 的配置，返回 dict（兼容旧代码）"""
    with open(_ASSISTANTS_CFG_PATH, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    target_id = assistant_id or cfg.get("default")
    for a in cfg.get("assistants", []):
        if a["id"] == target_id:
            return a
    raise ValueError(f"assistants.json 中未找到 assistant: {target_id}")


# _merge_keywords_files 函数已废弃
# 唤醒词合并逻辑已移至 start.sh 脚本中
# 程序直接使用 global.txt 文件


# ── 运行时变量（由 _apply_assistant_config 填充） ────────────
EXIT_KEYWORDS: set = set()
INSTANT_EXIT_KEYWORDS: set = set()
INSTANT_EXIT_FUZZY: tuple = ()
RESTART_KEYWORDS: set = set()
WAKE_LINES: list = []
EXIT_LINES: list = []


def _apply_assistant_config(cfg: dict):
    """将 assistant 配置写入模块级变量"""
    global EXIT_KEYWORDS, INSTANT_EXIT_KEYWORDS, INSTANT_EXIT_FUZZY
    global RESTART_KEYWORDS
    global WAKE_LINES, EXIT_LINES

    EXIT_KEYWORDS = set(cfg.get("exit_keywords", []))
    EXIT_KEYWORDS.update({"QUIT", "quit", "EXIT", "exit"})
    INSTANT_EXIT_KEYWORDS = set(cfg.get("instant_exit_keywords", []))
    INSTANT_EXIT_FUZZY = tuple(cfg.get("instant_exit_fuzzy", []))
    RESTART_KEYWORDS = set(cfg.get("restart_keywords", []))
    WAKE_LINES = list(cfg.get("wake_lines", []))
    EXIT_LINES = list(cfg.get("exit_lines", []))


def _is_instant_exit(text: str) -> bool:
    return text in INSTANT_EXIT_KEYWORDS or text in INSTANT_EXIT_FUZZY


# ── 唤醒 / 退出随机话术 ──────────────────────────────────────


def _random_wake_line() -> str:
    return random.choice(WAKE_LINES)


def _random_exit_line() -> str:
    return random.choice(EXIT_LINES)


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


def _batch_sentences(text: str, sent_end: str, max_sentences: int = 4):
    """把一段文本按句末标点切分，每 max_sentences 句合成一批。

    长句/长段落不再一次性整段合成，而是每 4 句切一刀，逐批送去合成播放，
    降低首句延迟并避免长文合成阻塞。返回若干文本片段（保留原标点）。
    """
    batches = []
    cur = []
    count = 0
    for ch in text:
        cur.append(ch)
        if ch in sent_end:
            count += 1
            if count >= max_sentences:
                batches.append("".join(cur))
                cur = []
                count = 0
    tail = "".join(cur)
    if tail.strip():
        batches.append(tail)
    return batches


def _short_log_text(text: str, limit: int = 160) -> str:
    import re

    text = re.sub(r"\s+", " ", (text or "")).strip()
    if len(text) <= limit:
        return text
    return text[:limit] + "..."


class VoiceAssistant:
    def __init__(
        self, args, default_cfg: dict, all_assistants: list, keyword_mapping: dict
    ):
        self.args = args
        self.default_cfg = default_cfg
        self.all_assistants = {a["id"]: a for a in all_assistants}
        self.keyword_mapping = keyword_mapping  # keyword_text -> assistant_id

        # 初始化 assistant manager
        self.assistant_manager = get_manager()

        # 注册所有启用的 assistant
        for cfg in all_assistants:
            assistant_id = cfg["id"]
            self.assistant_manager.register(
                assistant_id,
                cfg,
                sound_enabled=True,
                hud_enabled=True,
                notification_enabled=True,
            )

        # 切换到默认 assistant
        self.current_cfg = default_cfg
        self._switch_assistant(default_cfg["id"])

        self.sample_rate = 48000
        # sherpa-onnx 模型训练采样率为 16kHz，accept_waveform 必须喂 16kHz 数据；
        # 输入流保持 48kHz 兼容其他应用，在处理循环里用 soxr 重采样到 16kHz 再喂模型。
        self._asr_rate = 16000
        # 激活生命周期联动：is_awake 是 property（见下），在 False↔True
        # 边沿自动派发钩子。先建注册表并接入已有联动（暂停媒体），
        # 再触发首次赋值——此时 manager 已就绪。
        self._is_awake = False
        self._lifecycle = get_lifecycle_manager()
        self._lifecycle.register(MediaPauseHook())
        if _load_dock_autohide():
            self._lifecycle.register(DockAutohideHook())
            print("[Dock] 激活期自动隐藏 Dock：已启用（dock_autohide_on_wake）")
        self.is_awake = False
        self.continuous_mode = False
        self.audio_queue = queue.Queue()
        self.stop_event = threading.Event()
        self.last_voice_time = time.time()
        self.idle_timeout = _env_float("VOICE_ASSISTANT_IDLE_TIMEOUT_SECONDS", 30.0)
        self.last_activity_time = time.time()
        self._wake_audio_buffer = []  # 用于声纹验证的音频缓冲区
        self._wake_buffer_max_samples = int(self._asr_rate * 3)  # 最多存3秒（16kHz）
        # 实验：待机时以完整 ASR 话语替代专用 KWS。保留旧 KWS 路径作为回退，
        # VOICE_ASSISTANT_CONTINUOUS_WAKE_ASR=false 可随时关闭。
        self._continuous_wake_asr = _env_bool(
            "VOICE_ASSISTANT_CONTINUOUS_WAKE_ASR", True
        )
        self._standby_utterance_max_samples = int(
            self._asr_rate
            * _env_float("VOICE_ASSISTANT_STANDBY_UTTERANCE_MAX_SECONDS", 8.0)
        )
        self._prev_dnd_mode = False  # 上一轮勿扰状态，用于检测 DND 解除瞬间清流

        # VAD 前置缓存（用于待机时轻量级语音检测）
        self._vad_buffer = []
        self._vad_buffer_max_seconds = 2
        self._vad_buffer_max_samples = int(self._asr_rate * self._vad_buffer_max_seconds)

        # 连续对话模式音频缓冲（用于声纹验证）
        self._conv_audio_buffer = []
        self._conv_buffer_max_seconds = 3
        self._conv_buffer_max_samples = int(self._asr_rate * self._conv_buffer_max_seconds)
        self._speaker_verified = False  # 标记唤醒者是否已通过声纹验证
        self._speaker_embeddings = {}  # name -> embedding array，用于渐进更新
        self._verified_speaker_name = None  # 当前验证通过的说话人
        self._media_playing_on_wake = False  # 唤醒瞬间本机是否正在播放媒体
        self._last_wake_rejection = None  # 最近一次唤醒拒绝原因，供 control_center 弹窗展示

        self._is_openclaw_busy = False
        self._is_processing = False  # True: 从指令发出到TTS播报完毕的全流程
        self._processing_turn_id = 0
        self._processing_turn_lock = threading.Lock()
        self._openclaw_request_active = threading.Event()
        self._stop_openclaw_request = threading.Event()
        self._ignore_next_result = False
        self._suppress_recognition_until_tts_done = False
        self._suppress_recognition_during_tts = _env_bool(
            "VOICE_ASSISTANT_SUPPRESS_RECOGNITION_DURING_TTS", True
        )
        # 唤醒待决策：退下后台任务仍在跑时，唤醒不主动接续，改问"要不要继续"。
        # 置位后，下一句用户话被当作 是/否 决策处理（见 _on_recognized 开头）。
        self._pending_resume_decision = False
        self._last_diag_log = 0.0  # 监听循环诊断日志节流时间戳（文件级，不进控制中心）
        self._last_interrupt_time = 0  # 记录上次打断时间，用于防止误触发
        self._last_wake_time = 0  # 记录上次唤醒时间，唤醒后保护期内跳过退出检测
        # KWS 已验证并激活，但“唤醒词+指令”这一整句话仍在同一 ASR 流中收尾。
        self._wake_prefixed_command_pending = False
        self._wake_command_prefix = ""
        self._wake_asr_prefix = ""
        self._wake_canonical_name = ""
        self._keyword_stream_reset_event = (
            threading.Event()
        )  # 用于通知主循环重置 keyword_stream
        self._audio_device_changed_event = threading.Event()
        self._audio_device_signature = None
        self._audio_device_watch_thread = None
        # 打断词 spotter（分流方案 B）：播放期只用"打断词"触发 barge-in，避免助手
        # 自己的 TTS 回声命中唤醒词把自己切断。按当前助手异步加载 keywords/interrupt/<id>.txt。
        self._interrupt_spotter = None
        self._interrupt_spotter_id = None
        # 启动时按 assistants.json 的 interrupt_words 自动生成打断词文件（中英双语），
        # 唤醒对应助手时再加载。改 assistants.json 后重启即生效，无需手动跑脚本。
        try:
            from interrupt_keywords import generate_all
            _gen = generate_all(
                _PROJECT_DIR, os.path.dirname(self.args.kws_tokens), verbose=True
            )
            if _gen:
                print(f"[打断词] 启动自动生成: {_gen}")
        except Exception as e:  # noqa: BLE001 — 生成失败不拖垮启动
            print(f"[打断词] 启动生成失败（忽略）: {e}")

        self.keyword_spotter = self._create_keyword_spotter()
        # 始终创建流式识别器（用于连续对话模式）
        self.recognizer = self._create_recognizer()

        # 根据 assistant 配置决定使用哪种识别模式
        asr_mode = self.current_cfg.get("asr_mode", "streaming")
        if asr_mode == "sense_voice_en":
            # 使用 SenseVoice 英文模式
            sense_result = self._create_sense_voice_recognizer(language="en")
            if sense_result and sense_result[0] is not None:
                self.offline_recognizer, self.vad_config = sense_result
                self._use_offline_asr = True
                print("[配置] 贾维斯使用 SenseVoice 英文识别模式 (English only)")
            else:
                self._use_offline_asr = False
                print("[配置] SenseVoice 不可用，使用流式识别模式（热词增强）")
        elif asr_mode == "sense_voice":
            # 使用 SenseVoice 自动语言检测
            sense_result = self._create_sense_voice_recognizer(language="auto")
            if sense_result and sense_result[0] is not None:
                self.offline_recognizer, self.vad_config = sense_result
                self._use_offline_asr = True
                print("[配置] 使用 SenseVoice 多语言识别模式")
            else:
                self._use_offline_asr = False
                print("[配置] SenseVoice 不可用，使用流式识别模式（热词增强）")
        elif asr_mode == "offline":
            # 尝试创建 Qwen3-ASR 离线识别器
            offline_result = self._create_offline_recognizer()
            if offline_result and offline_result[0] is not None:
                self.offline_recognizer, self.vad_config, _ = offline_result
                self._use_offline_asr = True
                print("[配置] 使用 Qwen3-ASR 离线识别模式")
            else:
                self._use_offline_asr = False
                print("[配置] Qwen3-ASR 不可用，使用流式识别模式（热词增强）")
        else:
            self._use_offline_asr = False
            print("[配置] 使用流式识别模式（热词增强）")

        self._check_microphone()

        # ── 声纹验证初始化 ──────────────────────────────────────
        self._speaker_extractor = None
        self._speaker_manager = None
        self._speaker_enabled = False
        self._init_speaker_verification()

        # ── VAD 配置初始化（用于待机时轻量级语音检测）───────────
        self._init_vad_config()

        # OpenClaw bridge 会在切换 assistant 时动态创建
        self.openclaw = None
        self._init_openclaw()

        print("语音助手初始化完成！")
        print(
            f"已加载 {len(all_assistants)} 个 assistant: {[a['name'] for a in all_assistants]}"
        )
        print(f"唤醒词: {self._get_keywords()}")
        print(
            "[实验] 待机持续 ASR 唤醒: "
            + ("已启用" if self._continuous_wake_asr else "已关闭（使用 KWS）")
        )
        print("正在检测 OpenClaw 连接...")
        print("提示: 说出任意唤醒词即可唤醒对应的 assistant，支持连续对话")

    def _init_speaker_verification(self):
        """初始化声纹验证系统"""
        speakers = _load_speakers()

        if not speakers:
            print("[声纹] 未检测到已注册的声纹样本")
            print("[声纹] 声纹验证已启用（强制模式）")
            print("[声纹] 请使用 control_center 应用注册声纹")
            print("[声纹] 在未注册声纹前，语音助手将拒绝唤醒")
            self._speaker_enabled = True
            self._speaker_extractor = None
            self._speaker_manager = None
            self._speaker_embeddings = {}
            self._verified_speaker_name = None
            return

        if not _check_speaker_model():
            print("[声纹] 声纹模型不存在，跳过声纹验证")
            print(f"[声纹] 请下载模型: {_SPEAKER_MODEL_PATH}")
            return

        print(f"[声纹] 发现 {len(speakers)} 个已注册声纹，初始化验证系统...")

        self._speaker_extractor = _create_speaker_extractor()
        if self._speaker_extractor is None:
            print("[声纹] 提取器初始化失败，禁用声纹验证")
            return

        dim = self._speaker_extractor.dim
        self._speaker_manager = _create_speaker_manager(dim)
        self._speaker_embeddings = {}
        self._verified_speaker_name = None

        import soundfile as sf
        loaded_count = 0
        for speaker_info in speakers:
            wav_file = os.path.join(_SPEAKER_DIR, speaker_info.get('wav_file', ''))
            if not os.path.exists(wav_file):
                print(f"[声纹] 警告: 音频文件不存在: {wav_file}")
                continue

            try:
                name = speaker_info.get('name', f"user_{speaker_info.get('timestamp', 0)}")
                emb_list = None

                if 'embedding' in speaker_info and speaker_info['embedding']:
                    emb_list = speaker_info['embedding']
                    print(f"[声纹调试] 从JSON加载嵌入: {name}, 前5值: {emb_list[:5]}")
                else:
                    samples, sr = sf.read(wav_file, dtype='float32')
                    if len(samples.shape) > 1:
                        samples = samples.mean(axis=1)
                    print(f"[声纹调试] 加载声纹文件: {wav_file}, 样本长度: {len(samples)}")
                    embedding = _extract_embedding(self._speaker_extractor, samples.tolist(), sr)
                    if embedding is not None:
                        emb_list = embedding.tolist()
                        speaker_info['embedding'] = emb_list
                        _save_speakers(speakers)
                        print(f"[声纹] 已提取并保存嵌入: {name}")

                if emb_list is not None:
                    success = self._speaker_manager.add(name, emb_list)
                    if success:
                        self._speaker_embeddings[name] = np.array(emb_list)
                        loaded_count += 1
                        print(f"[声纹] 已加载: {name}")
                        print(f"[声纹调试] 当前已注册: {self._speaker_manager.all_speakers}")
                    else:
                        print(f"[声纹] 加载失败: {name}")
            except Exception as e:
                print(f"[声纹] 处理文件失败 {wav_file}: {e}")

        if loaded_count > 0:
            self._speaker_enabled = True
            print(f"[声纹] 验证系统已启用（{loaded_count} 个声纹已加载）")
            print(f"[声纹] 唤醒时将验证说话人身份")
        else:
            print("[声纹] 没有成功加载任何声纹，禁用验证")

    @property
    def is_awake(self) -> bool:
        return self._is_awake

    @is_awake.setter
    def is_awake(self, value: bool):
        """激活态写入口：仅在 False↔True 边沿派发生命周期联动钩子。

        全项目所有 `self.is_awake = X` 都经由此处，重复赋值不会重复触发，
        看门狗强制回待机、重启等角落也天然纳管。新增联动只需 register，
        主流程无需改动。
        """
        value = bool(value)
        changed = value != self._is_awake
        self._is_awake = value
        if not value and hasattr(self, "_wake_prefixed_command_pending"):
            self._wake_prefixed_command_pending = False
            self._wake_command_prefix = ""
            self._wake_asr_prefix = ""
            self._wake_canonical_name = ""
        if changed:
            self._lifecycle.notify(value)

    def _init_vad_config(self):
        """初始化 VAD 配置（用于待机时轻量级语音检测）"""
        vad_model = os.path.expanduser(self.args.vad_model)
        if not os.path.exists(vad_model):
            print("[VAD] VAD 模型不存在: {}，待机时将不使用 VAD 预检测".format(vad_model))
            self.vad_config = None
            return

        try:
            self.vad_config = sherpa_onnx.VadModelConfig(
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
            print("[VAD] VAD 配置创建成功（待机预检测模式）")
        except Exception as e:
            print("[VAD] provider={} 不可用，回退到 cpu: {}".format(self.args.provider, e))
            try:
                self.vad_config = sherpa_onnx.VadModelConfig(
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
                    provider="cpu",
                )
                print("[VAD] VAD 配置创建成功（cpu fallback）")
            except Exception as e2:
                print("[VAD] VAD 配置创建失败: {}".format(e2))
                self.vad_config = None

    def _verify_speaker_on_wake(self, samples, sample_rate=16000):
        """唤醒时验证声纹
        
        Returns:
            bool: 验证是否通过
        """
        self._last_wake_rejection = None
        if not self._speaker_enabled:
            return True  # 未启用时默认通过
        
        # 检查是否有注册声纹
        speakers = _load_speakers()
        if not speakers:
            print("\n[声纹] ⚠️ 拒绝唤醒: 未检测到已注册声纹")
            print("[声纹] 请先使用 control_center 应用注册声纹")
            print("[声纹] 注册完成后请重启语音助手")
            self._set_wake_rejection(
                "speaker_unregistered",
                "声纹未注册",
                "未检测到已注册的声纹样本，请先在控制中心注册声纹。",
                action="speaker",
            )
            return False
        
        if self._speaker_extractor is None or self._speaker_manager is None:
            print("[声纹] 验证系统未就绪，拒绝唤醒")
            self._set_wake_rejection(
                "speaker_not_ready",
                "声纹系统未就绪",
                "声纹模型或注册样本尚未成功加载，请检查启动日志后重启语音助手。",
                action="none",
            )
            return False
        
        # 检查音频样本是否有效
        if not samples or len(samples) == 0:
            print("[声纹] 警告: 音频样本为空，跳过验证")
            return True  # 空样本时允许唤醒，避免阻塞
        
        # 样本过短时允许唤醒（暂不强制验证，唤醒词本身已提供基本安全）
        min_samples = int(sample_rate * 0.1)  # 0.1秒最低要求（约1600采样点）
        if len(samples) < min_samples:
            print(f"[声纹] 警告: 音频样本过短 ({len(samples)} samples, 需要{min_samples})，跳过验证")
            return True
        
        # 本机媒体播放是“电脑自己放出唤醒音频”的强信号。先记录/可选拦截，
        # 避免 AASIST 对电脑扬声器重放给出高活体分时仍进入声纹更新。
        if not self._verify_media_wake_guard():
            return False

        # 实验期需要采集“手机/音箱重放但声纹未必通过”的活体分数，
        # 因此活体检测放在声纹比对之前。默认 shadow mode 只打日志不拦截；
        # enforce=true 时，疑似重放会在进入声纹/渐进更新前被拒绝。
        if not self._verify_liveness_on_wake(samples, sample_rate):
            return False

        is_verified, speaker_name, score = _verify_speaker(
            self._speaker_extractor, self._speaker_manager, samples, sample_rate
        )

        if is_verified:
            print(f"[声纹] 验证通过: {speaker_name} (score: {score:.3f})")
            self._verified_speaker_name = speaker_name
            self._update_speaker_progressive(samples, sample_rate)
            return True
        else:
            print(f"[声纹] 验证失败: 未识别到已注册声纹 (score: {score:.3f})")
            print("[声纹] 请使用已注册声纹的用户唤醒，或使用 control_center 注册新声纹")
            self._set_wake_rejection(
                "speaker_failed",
                "声纹验证失败",
                f"未识别到已注册声纹。本次相似度分数: {score:.3f}。",
                action="speaker",
            )
            return False

    def _set_wake_rejection(self, reason: str, title: str, message: str, action: str = "none") -> None:
        self._last_wake_rejection = {
            "reason": reason,
            "title": title,
            "message": message,
            "action": action,
        }

    def _verify_media_wake_guard(self) -> bool:
        """唤醒瞬间检测本机是否正在播放媒体。

        这是电脑本机重放攻击的强特征；默认 shadow 只记录，不改变体验。
        enforce=true 时直接拒绝本次唤醒，且不会进入声纹渐进更新。
        """
        self._media_playing_on_wake = False
        if not _MEDIA_WAKE_GUARD_ENABLED:
            return True
        try:
            from media_pause import get_media_controller

            media = get_media_controller()
            playing = bool(media.is_playing()) if media.is_available() else False
        except Exception as e:  # noqa: BLE001 - 媒体检测不能阻塞唤醒
            print(f"[媒体门禁] 检测异常，软失败放行: {e}")
            return True

        self._media_playing_on_wake = playing
        mode = "enforce" if _MEDIA_WAKE_GUARD_ENFORCE else "shadow"
        print(f"[媒体门禁] {mode}: playing={playing}")
        if playing and _MEDIA_WAKE_GUARD_ENFORCE:
            print("[媒体门禁] 拒绝唤醒: 检测到本机正在播放媒体，疑似电脑重放")
            self._set_wake_rejection(
                "media_playing",
                "检测到本机媒体播放",
                "唤醒时电脑正在播放媒体，疑似本机重放录音。已拒绝本次唤醒。",
                action="none",
            )
            return False
        return True

    def _verify_liveness_on_wake(self, samples, sample_rate=16000) -> bool:
        """唤醒时做被动活体检测。

        实验期支持 shadow mode：VOICE_ASSISTANT_LIVENESS_ENFORCE=false 时只记录分数，
        不改变唤醒体验；模型缺失/推理失败由 anti_spoof.py 软失败放行。
        """
        if not _LIVENESS_ENABLED:
            return True

        try:
            from anti_spoof import get_anti_spoof_detector

            detector = get_anti_spoof_detector(
                model_path=_LIVENESS_MODEL_PATH,
                threshold=_LIVENESS_THRESHOLD,
            )
            is_live, live_score = detector.is_live(samples, sample_rate)
        except Exception as e:  # noqa: BLE001 - 活体检测不能拖垮唤醒主链路
            if _LIVENESS_ENFORCE:
                print(f"[活体] 检测异常，拒绝唤醒: {e}")
                self._set_wake_rejection(
                    "liveness_error",
                    "活体检测异常",
                    f"活体检测推理异常，已拒绝本次唤醒。详情: {e}",
                    action="none",
                )
                return False
            print(f"[活体] 检测异常，软失败放行: {e}")
            return True

        mode = "enforce" if _LIVENESS_ENFORCE else "shadow"
        if live_score < 0:
            if _LIVENESS_ENFORCE:
                print(f"[活体] {mode}: 模型不可用或推理失败，拒绝唤醒")
                self._set_wake_rejection(
                    "liveness_unavailable",
                    "活体检测不可用",
                    "活体检测模型不可用或推理失败，已拒绝本次唤醒。请检查 AASIST ONNX 模型与 onnxruntime。",
                    action="none",
                )
                return False
            print(f"[活体] {mode}: 模型不可用或推理失败，软失败放行")
            return True

        print(
            f"[活体] {mode}: score={live_score:.3f}, "
            f"threshold={_LIVENESS_THRESHOLD:.3f}, pass={is_live}"
        )
        if not is_live and _LIVENESS_ENFORCE:
            print("[活体] 拒绝唤醒: 疑似录音/合成/重放音频")
            self._set_wake_rejection(
                "liveness_failed",
                "活体检测失败",
                f"疑似录音、合成或重放音频。本次活体分数: {live_score:.3f}，阈值: {_LIVENESS_THRESHOLD:.3f}。",
                action="none",
            )
            return False
        return True


    def _update_speaker_progressive(self, samples, sample_rate=16000):
        """用最新对话音频渐进更新已验证用户的声纹嵌入

        取前5秒音频，静音过滤后提取嵌入，与旧嵌入各50%平均融合，
        然后持久化到文件并更新内存中的manager。
        """
        if not self._speaker_enabled or self._verified_speaker_name is None:
            return

        if self._media_playing_on_wake:
            print("[声纹] 渐进更新跳过: 唤醒时检测到本机媒体播放")
            return

        if self._speaker_extractor is None or self._speaker_manager is None:
            return

        import soundfile as sf
        import librosa

        max_samples = int(sample_rate * 5)
        if len(samples) > max_samples:
            samples = samples[-max_samples:]

        try:
            trimmed, _ = librosa.effects.trim(samples, top_db=20)
        except Exception:
            trimmed = samples

        if len(trimmed) < sample_rate * 0.5:
            print(f"[声纹] 渐进更新跳过: 静音过滤后音频太短 ({len(trimmed)} samples)")
            return

        embedding = _extract_embedding(self._speaker_extractor, trimmed, sample_rate)
        if embedding is None:
            print("[声纹] 渐进更新跳过: 嵌入提取失败")
            return

        name = self._verified_speaker_name
        old_emb = self._speaker_embeddings.get(name)
        if old_emb is not None:
            new_emb = 0.5 * old_emb + 0.5 * embedding
        else:
            new_emb = embedding

        new_emb_list = new_emb.tolist()
        self._speaker_embeddings[name] = new_emb

        self._speaker_manager.remove(name)
        success = self._speaker_manager.add(name, new_emb_list)
        if success:
            print(f"[声纹] 渐进更新成功: {name}")
        else:
            print(f"[声纹] 渐进更新失败: manager更新失败")

        speakers = _load_speakers()
        for sp in speakers:
            if sp.get('name') == name:
                sp['embedding'] = new_emb_list
                wav_file = os.path.join(_SPEAKER_DIR, sp.get('wav_file', ''))
                if wav_file:
                    sf.write(wav_file, trimmed, sample_rate)
                    print(f"[声纹] 已更新音频文件: {wav_file}")
                break
        _save_speakers(speakers)

    def _verify_current_speaker(self) -> bool:
        """连续对话模式中验证当前说话人是否为已注册用户

        Returns:
            bool: 验证是否通过
        """
        if not self._speaker_enabled:
            return True

        if self._speaker_extractor is None or self._speaker_manager is None:
            return True  # 验证系统未就绪时允许通过，避免阻塞对话

        # 合并缓冲音频
        audio_samples = []
        for buf in self._conv_audio_buffer:
            audio_samples.extend(buf)

        if len(audio_samples) < self._conv_buffer_max_samples // 2:
            return True  # 音频不足，跳过验证

        is_verified, name, score = _verify_speaker(
            self._speaker_extractor,
            self._speaker_manager,
            audio_samples,
            self._asr_rate
        )

        if is_verified:
            print("[声纹] 连续对话验证通过: {} (score: {:.3f})".format(name, score))
            if self._verified_speaker_name is None:
                self._verified_speaker_name = name
            elif self._verified_speaker_name != name:
                self._verified_speaker_name = name
                print("[声纹] 警告: 检测到说话人变更，更新验证用户")
            return True
        else:
            print("[声纹] 连续对话验证失败: 陌生人声音已忽略 (score: {:.3f})".format(score))
            self._conv_audio_buffer.clear()
            return False

    def _switch_assistant(self, assistant_id: str):
        """切换到指定的 assistant"""
        if assistant_id not in self.all_assistants:
            print(f"[错误] 未知的 assistant: {assistant_id}")
            return False

        # 切换到新的 assistant
        instance = self.assistant_manager.switch_to(assistant_id)
        if not instance:
            return False

        self.current_cfg = self.all_assistants[assistant_id]
        _apply_assistant_config(self.current_cfg)

        # 根据 assistant 配置决定使用哪种识别模式
        asr_mode = self.current_cfg.get("asr_mode", "streaming")
        if asr_mode == "sense_voice_en":
            if (
                hasattr(self, "offline_recognizer")
                and self.offline_recognizer is not None
            ):
                self._use_offline_asr = True
                print(f"[配置] {self.current_cfg['name']} 使用 SenseVoice 英文模式")
            else:
                sense_result = self._create_sense_voice_recognizer(language="en")
                if sense_result and sense_result[0] is not None:
                    self.offline_recognizer, self.vad_config = sense_result
                    self._use_offline_asr = True
                    print(
                        f"[配置] {self.current_cfg['name']} 使用 SenseVoice 英文模式 (English only)"
                    )
                else:
                    self._use_offline_asr = False
                    print(
                        f"[配置] {self.current_cfg['name']} SenseVoice 不可用，使用流式识别"
                    )
        elif asr_mode == "sense_voice":
            if (
                hasattr(self, "offline_recognizer")
                and self.offline_recognizer is not None
            ):
                self._use_offline_asr = True
                print(f"[配置] {self.current_cfg['name']} 使用 SenseVoice 多语言模式")
            else:
                sense_result = self._create_sense_voice_recognizer(language="auto")
                if sense_result and sense_result[0] is not None:
                    self.offline_recognizer, self.vad_config = sense_result
                    self._use_offline_asr = True
                    print(
                        f"[配置] {self.current_cfg['name']} 使用 SenseVoice 多语言模式"
                    )
                else:
                    self._use_offline_asr = False
                    print(
                        f"[配置] {self.current_cfg['name']} SenseVoice 不可用，使用流式识别"
                    )
        elif asr_mode == "offline":
            if (
                hasattr(self, "offline_recognizer")
                and self.offline_recognizer is not None
            ):
                self._use_offline_asr = True
                print(f"[配置] {self.current_cfg['name']} 使用 Qwen3-ASR 离线识别模式")
            else:
                offline_result = self._create_offline_recognizer()
                if offline_result and offline_result[0] is not None:
                    self.offline_recognizer, self.vad_config, _ = offline_result
                    self._use_offline_asr = True
                    print(
                        f"[配置] {self.current_cfg['name']} 使用 Qwen3-ASR 离线识别模式"
                    )
                else:
                    self._use_offline_asr = False
                    print(
                        f"[配置] {self.current_cfg['name']} Qwen3-ASR 不可用，使用流式识别"
                    )
        else:
            self._use_offline_asr = False
            print(f"[配置] {self.current_cfg['name']} 使用流式识别模式")

        # 更新当前使用的组件
        self.jarvis = instance.feedback
        self.visual = instance.visual
        self.tts = instance.tts
        set_tts(self.tts)

        # 特效调试模式（assistants.json 顶层 overlay_debug_mode）：
        # 开启后，召唤出来的特效不再被隐藏/清空，方便调样式
        if hasattr(self.visual, "set_debug_mode"):
            self.visual.set_debug_mode(_load_overlay_debug())

        print(f"[切换] 已切换到: {self.current_cfg['name']} ({assistant_id})")
        return True

    def _init_openclaw(self):
        """初始化 OpenClaw bridge"""
        assistant_id = self.current_cfg["id"]
        # 按当前助手异步加载打断词 spotter（启动与切换都经过这里）
        self._load_interrupt_spotter_async(assistant_id)
        if self.openclaw:
            # 如果有旧的，先发送停止，再关闭其 WebSocket 长连接（避免切换时连接泄漏）
            self.openclaw.send_stop_command()
            close = getattr(self.openclaw, "close", None)
            if callable(close):
                close()
        # namespace 与 agent_id 一致 → session key = agent:<id>:<id>（如 agent:jarvis:jarvis），
        # 与历史会话 lane 保持一致；WS 桥用 chat.abort/sessions.reset 控制面 RPC，
        # 不再把 /stop、/clear 作为聊天消息排进同一 lane，从根上消除 "Command lane cleared"。
        agent_id = assistant_id.replace("-", "_")
        self.openclaw = get_bridge(agent_id=agent_id, namespace=agent_id)
        self.openclaw.precheck_async()

        # 快路径（分流第一线）：直连 Control Center 配置的快模型。
        # fastMode=false 或未配置模型表时，_route_stream 自动全走 agent。
        if not _load_fast_mode():
            self._fast_path = None
            print("[分流] fastMode=false，快路径已关闭（全走 agent）")
            return

        try:
            from fast_path import FastPathClient
            engine = _load_engine()
            self._fast_path = FastPathClient(
                should_stop=self._stop_openclaw_request.is_set,
                agent_name=self.current_cfg.get("name") or assistant_id,
                agent_id=assistant_id,
            )
            # 人设跟随当前引擎 + 当前角色：从 SOUL 文件取精简人格注入快路径，
            # 让闲聊也像 jarvis / 林妹妹本人（openclaw 与 hermes 各自 SOUL 位置不同）。
            try:
                from persona_loader import load_persona
                persona = load_persona(engine, assistant_id)
                if persona:
                    self._fast_path.set_persona(persona)
                    print(f"[分流] 已注入 {assistant_id} 人设（{len(persona)} 字，引擎 {engine}）")
            except Exception as e:  # noqa: BLE001 — 人设可选，失败退化为无人格
                print(f"[分流] 人设加载失败（忽略）: {e}")
            # session/memory 读取器：让轻消息也能拿到 agent lane 的近期对话与长期记忆，
            # 消除"轻消息丢往期上下文"的分叉（本地直读，fail-open）。
            try:
                from history_reader import get_history_reader
                reader = get_history_reader(engine, assistant_id)
                if reader is not None:
                    self._fast_path.set_history_reader(reader)
                    print(f"[分流] 已挂载 {engine} 历史读取器（available={reader.is_available()}）")
            except Exception as e:  # noqa: BLE001 — 历史读取可选，失败退化为无引擎上下文
                print(f"[分流] 历史读取器挂载失败（忽略）: {e}")
        except Exception as e:  # noqa: BLE001 — 快路径不可用绝不能拖垮桥初始化
            print(f"[分流] 快路径初始化失败（忽略，全走 agent）: {e}")
            self._fast_path = None

    @staticmethod
    def _agent_label():
        return "Hermes" if _ENGINE == "hermes" else "OpenClaw"

    def _detect_assistant_from_keyword(self, keyword_result: str) -> str:
        """从唤醒词检测结果识别是哪个 assistant"""
        if not keyword_result:
            return self.current_cfg["id"]

        # 在 keyword_mapping 中查找
        for keyword_text, assistant_id in self.keyword_mapping.items():
            if keyword_text in keyword_result or keyword_result in keyword_text:
                return assistant_id

        # 如果没找到，返回当前 assistant
        return self.current_cfg["id"]

    def _extract_standby_wake_command(self, text: str):
        """从完整待机话语提取 (assistant_id, wake_word, command)。

        比较时忽略空白、标点和大小写，但 command 保留 ASR 原文。为减少讨论中偶然
        提及助手名字造成的验证开销，唤醒词只允许出现在话语开头很短的前导语之后。
        """
        raw = _apply_text_corrections((text or "").strip())
        if not raw:
            return None

        compact = []
        raw_indexes = []
        for index, char in enumerate(raw):
            if char.isalnum() or "\u4e00" <= char <= "\u9fff":
                compact.append(char.casefold())
                raw_indexes.append(index)
        normalized = "".join(compact)
        max_prefix = _env_int("VOICE_ASSISTANT_WAKE_MAX_PREFIX_CHARS", 2)

        best = None
        for wake_word, assistant_id in self.keyword_mapping.items():
            wake_normalized = "".join(
                char.casefold()
                for char in wake_word
                if char.isalnum() or "\u4e00" <= char <= "\u9fff"
            )
            if not wake_normalized:
                continue
            position = normalized.find(wake_normalized)
            if position < 0 or position > max_prefix:
                continue
            end_position = position + len(wake_normalized) - 1
            raw_end = raw_indexes[end_position] + 1
            command = raw[raw_end:].lstrip(" \t\r\n，,。.!！?？:：、")
            candidate = (position, -len(wake_normalized), assistant_id, wake_word, command)
            if best is None or candidate[:2] < best[:2]:
                best = candidate

        if best is None:
            return None
        return best[2], best[3], best[4]

    def _is_complete_wake_phrase_tail(self, text: str) -> bool:
        """判断 ASR 尾部是否只是完整唤醒短语的一部分，而非真实指令。"""
        if self.current_cfg.get("id") != "jarvis":
            return False
        normalized = "".join(char.casefold() for char in (text or "") if char.isalnum())
        # "Is Jarvis here?" 中 KWS 从 Jarvis 命中；在线 ASR 常把 here 写成 care。
        return normalized in {"here", "care"}

    def _strip_kws_confirmed_wake_prefix(self, text: str):
        """KWS 已确认身份后，从 ASR 整句中稳健剥离可能漂移的唤醒词转写。

        在线 ASR 的 partial 可能从 JAVAS 漂移成 JAVAIS，不能依赖命中瞬间文本与
        final 完全一致。固定格式是“唤醒词+指令”，因此可对句首英文 token 与
        Jarvis/KWS 时转写做相似度判断；只有高相似时才剥离。
        """
        raw = (text or "").strip()
        extracted = self._extract_standby_wake_command(raw)
        if extracted is not None:
            return extracted[2], True

        prefix = (self._wake_asr_prefix or "").strip()
        if prefix and raw.casefold().startswith(prefix.casefold()):
            return raw[len(prefix):].lstrip(" \t\r\n，,。.!！?？:：、"), True

        match = _re_corrections.match(r"^([A-Za-z]+)", raw)
        if match:
            token = match.group(1).casefold()
            candidates = ["jarvis"]
            if prefix and prefix.isascii():
                candidates.append(prefix.casefold())
            similarity = max(
                difflib.SequenceMatcher(None, token, candidate).ratio()
                for candidate in candidates
            )
            if similarity >= 0.65:
                command = raw[match.end():].lstrip(" \t\r\n，,。.!！?？:：、")
                return command, True

        return raw, False

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

    def _get_default_input_device_signature(self):
        """返回当前默认输入设备签名；查询失败时返回可比较的错误签名。"""
        try:
            default_idx = sd.default.device[0]
            info = None
            if default_idx is not None and default_idx >= 0:
                try:
                    info = sd.query_devices(default_idx)
                except Exception:
                    info = None
            if info is None:
                info = sd.query_devices(kind="input")

            name = (
                info.get("name", "unknown")
                if hasattr(info, "get")
                else str(info)
            )
            max_inputs = (
                info.get("max_input_channels", 0)
                if hasattr(info, "get")
                else 0
            )
            samplerate = (
                info.get("default_samplerate", 0)
                if hasattr(info, "get")
                else 0
            )
            return (default_idx, name, int(max_inputs or 0), int(float(samplerate or 0)))
        except Exception as e:
            return ("unavailable", str(e))

    def _format_audio_device_signature(self, sig) -> str:
        try:
            if isinstance(sig, tuple) and len(sig) >= 4:
                idx, name, channels, rate = sig[:4]
                return f"{name} (idx={idx}, ch={channels}, sr={rate})"
            return str(sig)
        except Exception:
            return "unknown"

    def _start_audio_device_watcher(self):
        """监听默认输入设备变化。

        轮询线程只发事件，实际重建音频流在主音频循环中完成，避免跨线程操作
        PortAudio/CoreAudio 对象。
        """
        if not _AUDIO_DEVICE_WATCH_ENABLED:
            return
        if self._audio_device_watch_thread and self._audio_device_watch_thread.is_alive():
            return

        interval = max(0.5, float(_AUDIO_DEVICE_POLL_INTERVAL))
        self._audio_device_signature = self._get_default_input_device_signature()
        print(
            "[音频设备] 默认输入设备: "
            + self._format_audio_device_signature(self._audio_device_signature)
        )

        def _watch():
            while not self.stop_event.wait(interval):
                sig = self._get_default_input_device_signature()
                if sig == self._audio_device_signature:
                    continue
                old = self._audio_device_signature
                self._audio_device_signature = sig
                print(
                    "[音频设备] 默认输入设备变化: "
                    + self._format_audio_device_signature(old)
                    + " -> "
                    + self._format_audio_device_signature(sig)
                )
                self._audio_device_changed_event.set()

        self._audio_device_watch_thread = threading.Thread(
            target=_watch,
            name="audio-device-watch",
            daemon=True,
        )
        self._audio_device_watch_thread.start()

    def _create_keyword_spotter(self):
        """创建关键词检测器"""
        try:
            spotter = sherpa_onnx.KeywordSpotter(
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
            print(f"[KWS] 使用 provider: {self.args.provider}")
            return spotter
        except Exception as e:
            print(f"[KWS] provider={self.args.provider} 不可用，回退到 cpu: {e}")
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
                provider="cpu",
            )

    def _interrupt_keywords_path(self, assistant_id):
        return os.path.join(
            _PROJECT_DIR, "keywords", "interrupt", f"{assistant_id}.txt"
        )

    def _create_spotter_from_file(self, keywords_file):
        """用指定关键词文件构建 KWS spotter（复用唤醒词 spotter 的模型参数）。
        文件缺失/为空/构建失败返回 None。"""
        if not keywords_file or not os.path.exists(keywords_file):
            return None
        try:
            if os.path.getsize(keywords_file) == 0:
                return None
        except OSError:
            return None
        for provider in (self.args.provider, "cpu"):
            try:
                return sherpa_onnx.KeywordSpotter(
                    tokens=self.args.kws_tokens,
                    encoder=self.args.kws_encoder,
                    decoder=self.args.kws_decoder,
                    joiner=self.args.kws_joiner,
                    num_threads=1,
                    keywords_file=keywords_file,
                    keywords_score=self.args.keywords_score,
                    keywords_threshold=self.args.keywords_threshold,
                    max_active_paths=8,
                    num_trailing_blanks=2,
                    provider=provider,
                )
            except Exception as e:  # noqa: BLE001
                print(f"[打断词] provider={provider} 构建失败: {e}")
        return None

    def _load_interrupt_spotter_async(self, assistant_id):
        """异步加载指定助手的打断词 spotter（方案 B）。

        同一助手已加载则跳过；切换助手时立即失效旧的，后台加载新的；无打断词文件
        则置空（该助手播放期不支持语音打断）。异步以免拖慢唤醒/切换。
        """
        if assistant_id == self._interrupt_spotter_id:
            return
        self._interrupt_spotter_id = assistant_id
        self._interrupt_spotter = None  # 立即失效旧的，避免播放期误用别的助手打断词
        path = self._interrupt_keywords_path(assistant_id)

        def _load():
            spotter = self._create_spotter_from_file(path)
            # 加载期间若又切换了助手，丢弃本次结果
            if self._interrupt_spotter_id != assistant_id:
                return
            self._interrupt_spotter = spotter
            if spotter is not None:
                print(f"[打断词] 已加载 {assistant_id} 的打断词: {path}")
            else:
                print(f"[打断词] {assistant_id} 无打断词文件，播放期不支持语音打断: {path}")

        threading.Thread(target=_load, daemon=True).start()

    def _create_recognizer(self):
        """创建语音识别器"""
        hotwords_file = os.path.expanduser(self.args.hotwords_file)
        use_hotwords = os.path.exists(hotwords_file)
        if use_hotwords:
            print(f"[ASR] 加载热词文件: {hotwords_file}")
        else:
            print(f"[ASR] 热词文件不存在: {hotwords_file}，不启用热词")

        return sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=self.args.asr_tokens,
            encoder=self.args.asr_encoder,
            decoder=self.args.asr_decoder,
            joiner=self.args.asr_joiner,
            num_threads=1,
            sample_rate=self._asr_rate,
            feature_dim=80,
            decoding_method="modified_beam_search" if use_hotwords else "greedy_search",
            hotwords_file=hotwords_file if use_hotwords else "",
            hotwords_score=self.args.hotwords_score,
            modeling_unit="cjkchar+bpe",
            bpe_vocab=self.args.asr_tokens,
            provider=self.args.provider,
        )

    def _create_sense_voice_recognizer(self, language="auto"):
        """创建 SenseVoice 离线识别器和 VAD 配置

        Args:
            language: 语言参数，auto/zh/en/ko/ja/yue
        """
        sense_voice_model = os.path.expanduser(self.args.sense_voice_model)
        sense_voice_tokens = os.path.expanduser(self.args.sense_voice_tokens)
        vad_model = os.path.expanduser(self.args.vad_model)

        if not os.path.exists(sense_voice_model):
            print(f"[警告] SenseVoice 模型不存在: {sense_voice_model}")
            return None, None

        print(f"[SenseVoice] 初始化离线识别器 (language={language})...")
        print(f"  model: {sense_voice_model}")
        print(f"  tokens: {sense_voice_tokens}")
        print(f"  use_itn: {self.args.sense_voice_use_itn}")

        try:
            recognizer = (
                sherpa_onnx.offline_recognizer.OfflineRecognizer.from_sense_voice(
                    model=sense_voice_model,
                    tokens=sense_voice_tokens,
                    num_threads=2,
                    use_itn=bool(self.args.sense_voice_use_itn),
                    language=language,
                )
            )
            print("[SenseVoice] 离线识别器创建成功")
        except Exception as e:
            print(f"[SenseVoice] 创建离线识别器失败: {e}")
            return None, None

        if not os.path.exists(vad_model):
            print(f"[警告] VAD 模型不存在: {vad_model}")
            print("[警告] 无法使用 SenseVoice")
            return recognizer, None

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
            print(f"[VAD] provider={self.args.provider} 不可用，回退到 cpu: {e}")
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
                provider="cpu",
            )

        return recognizer, vad_config

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
            print(f"[VAD] provider={self.args.provider} 不可用，回退到 cpu: {e}")
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
                provider="cpu",
            )

        return recognizer, vad_config, None

    def _process_recognition_result(self, recognition_result):
        """处理识别结果，返回是否继续循环"""
        if not recognition_result:
            return True

        _recog = recognition_result.strip()
        # 文本纠错：兜底修复 sherpa hotwords 救不了的 OOV 英文整词误识别
        # （如 "TONY STOCK" → "Tony Stark"）。幂等安全，流式中间态替换不影响 final。
        _corrected = _apply_text_corrections(_recog)
        if _corrected != _recog:
            print(f"[文本纠错] {_recog!r} → {_corrected!r}")
        _recog = _corrected
        _is_exit = _recog in EXIT_KEYWORDS or _recog in INSTANT_EXIT_FUZZY
        if _is_exit:
            print(f"收到退出指令: {recognition_result.strip()}")
            self._interrupt_openclaw()
            # self._clear_openclaw_context()
            self.jarvis.on_exit()
            self.visual.clear_texts()
            self.visual.hide_effects()
            if not _is_instant_exit(_recog):
                play_prebuilt_voice("exit", _random_exit_line())
                while is_tts_playing():
                    time.sleep(0.05)
            self._clear_queue()
            self.is_awake = False
            self.continuous_mode = False
            self._vad_stream = None
            self._audio_buffer = []
            self._speech_started = False
            print("\n已退出监听，等待唤醒词...")
            return False

        self.visual.show_user_text(_recog)
        if not self._ignore_next_result:
            threading.Thread(
                target=self._on_recognized,
                args=(_recog,),
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

    def _resample_for_asr(self, samples):
        """将输入流采样率的音频重采样到 ASR 模型期望的 16kHz。
        输入流保持 48kHz 兼容其他应用，sherpa-onnx 模型训练时为 16kHz，
        必须重采样才能正确提取 fbank 特征。"""
        if self.sample_rate == self._asr_rate:
            return samples
        if _soxr is not None:
            return _soxr.resample(samples, self.sample_rate, self._asr_rate).astype(np.float32)
        # 无 soxr 时退回：简单每 N 取 1（粗略降采样，精度差但不会像错采样率那样完全乱套）
        ratio = self.sample_rate // self._asr_rate
        return samples[::ratio]

    def _audio_callback(self, indata, frames, time_info, status):
        """音频回调函数"""
        if status:
            print(status)
        # 始终入队音频，保证处理期间（含TTS播报）也能检测唤醒词打断
        if self.audio_queue.qsize() < _env_int("VOICE_ASSISTANT_AUDIO_QUEUE_MAXSIZE", 100):
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
        standby_recognition_stream = (
            self.recognizer.create_stream() if self._continuous_wake_asr else None
        )
        standby_recognition_result = ""
        standby_last_result_time = time.time()
        standby_audio_buffer = []

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
            # 【不要再调用 PortAudio 的 stop()/close()】——它们在 macOS CoreAudio 上
            # 会偶发永久死锁（卡在 C 调用里，try/except 兜不住），是"说完话后一直卡在
            # listening、不重启不恢复"的根因（尤其打断后 stop→start→端点→又 stop 的
            # 快速开关流场景）。而 _audio_callback 本就【始终入队】（TTS/处理期间也要
            # 检测唤醒词打断），即麦克风流本应常开。故这里改为"保持流常开、只清空已
            # 缓冲音频"——语义等价于原来的"丢弃这段输入"，并彻底规避死锁。
            # 真正的释放在进程退出时由系统回收。
            self._clear_queue()

        def reset_audio_stream():
            # 错误恢复路径：可能卡住的 stop()/close() 丢到后台守护线程执行（不阻塞
            # 主循环），立即置空并重建一个新流。即使旧流的 close 在后台卡死，主循环也
            # 不受影响。
            nonlocal audio_stream
            old = audio_stream
            audio_stream = None
            if old is not None:
                def _close_old(s):
                    try:
                        s.stop()
                        s.close()
                    except Exception:
                        pass
                threading.Thread(target=_close_old, args=(old,), daemon=True).start()
            self._clear_queue()
            start_audio_stream()

        def _create_vad_stream():
            nonlocal vad_stream
            if self.vad_config:
                try:
                    vad_stream = sherpa_onnx.VoiceActivityDetector(
                        config=self.vad_config,
                        buffer_size_in_seconds=60,
                    )
                    return True
                except Exception as e:
                    print("[VAD] 创建失败: {}".format(e))
                    return False
            return False

        def _do_recognize(audio_samples):
            """使用 SenseVoice 离线识别器识别音频片段"""
            if not self._use_offline_asr or not self.offline_recognizer:
                return None

            try:
                stream = self.offline_recognizer.create_stream()
                if hasattr(audio_samples, "tolist"):
                    samples_list = audio_samples.tolist()
                else:
                    samples_list = list(audio_samples)
                stream.accept_waveform(16000, samples_list)
                self.offline_recognizer.decode_stream(stream)
                return stream.result.text
            except Exception as e:
                print(f"[离线识别] 识别失败: {e}")
                return None

        self._start_audio_device_watcher()
        start_audio_stream()
        print("开始监听...")
        print("提示: 说出唤醒词后可进入连续对话模式")

        # 创建 VAD 流（用于待机时轻量级语音检测）
        vad_stream = None
        if self.vad_config:
            if _create_vad_stream():
                print("[VAD] VAD 流已创建（待机预检测模式）")
            else:
                print("[VAD] VAD 流创建失败，待机时将不使用预检测")

        # 打断词流（方案 B）：与 self._interrupt_spotter 配对的本地流，spotter 异步
        # 变更时重建。仅在本音频线程内创建/解码，避免跨线程用同一个流。
        _interrupt_spotter_ref = None
        _interrupt_stream = None

        while not self.stop_event.is_set():
            try:
                if self._audio_device_changed_event.is_set():
                    self._audio_device_changed_event.clear()
                    print("[音频设备] 检测到输入设备变化，正在重建音频流...")
                    reset_audio_stream()
                    time.sleep(0.1)
                    self._clear_queue()
                    keyword_stream = self.keyword_spotter.create_stream()
                    recognition_stream = (
                        self.recognizer.create_stream() if self.is_awake else None
                    )
                    recognition_result = ""
                    if self._continuous_wake_asr:
                        standby_recognition_stream = self.recognizer.create_stream()
                        standby_recognition_result = ""
                        standby_last_result_time = time.time()
                        standby_audio_buffer = []
                    if self._use_offline_asr:
                        vad_stream = None
                        _create_vad_stream()
                        audio_buffer = []
                        speech_started = False
                    elif self.vad_config:
                        vad_stream = None
                        _create_vad_stream()
                    self._wake_audio_buffer.clear()
                    self._vad_buffer.clear()
                    self._conv_audio_buffer.clear()
                    self.last_activity_time = time.time()
                    print("[音频设备] 音频流已切换到当前默认输入设备")
                    continue

                # 检查是否需要重置 keyword_stream（由 exit_standby 触发）
                if self._keyword_stream_reset_event.is_set():
                    self._keyword_stream_reset_event.clear()
                    print(
                        "[重置] 检测到退出信号，正在重置 keyword_stream 和 audio_stream..."
                    )
                    stop_audio_stream()
                    time.sleep(0.05)
                    self._clear_queue()
                    keyword_stream = self.keyword_spotter.create_stream()
                    if self._continuous_wake_asr:
                        standby_recognition_stream = self.recognizer.create_stream()
                        standby_recognition_result = ""
                        standby_last_result_time = time.time()
                        standby_audio_buffer = []
                    start_audio_stream()
                    time.sleep(0.05)
                    self._clear_queue()
                    print("[重置] 已完成，继续等待唤醒词...")
                    continue

                # 处理中（OpenClaw请求→TTS播报完毕），只检测唤醒词以支持打断
                if self._is_processing and self._suppress_recognition_during_tts:
                    try:
                        audio_data = self.audio_queue.get(timeout=0.5)
                    except queue.Empty:
                        # 处理期间麦克风假死会让打断监听失效；重建音频流以恢复，
                        # 但不动 _is_processing 等标志（由请求/TTS 线程负责复位）。
                        if time.time() - self.last_activity_time > _AUDIO_STALL_TIMEOUT:
                            print("[看门狗] 处理期间音频流假死，重建以恢复打断监听...")
                            stop_audio_stream()
                            time.sleep(0.1)
                            self._clear_queue()
                            keyword_stream = self.keyword_spotter.create_stream()
                            start_audio_stream()
                            time.sleep(0.1)
                            self._clear_queue()
                            self.last_activity_time = time.time()
                        continue

                    self.last_activity_time = time.time()
                    samples = audio_data.reshape(-1)
                    asr_samples = self._resample_for_asr(samples)

                    # 方案 B：播放期只用"打断词"触发 barge-in，不喂唤醒词 KWS——
                    # 避免助手自己的 TTS 回声命中唤醒词、把自己念到一半切断。
                    # 打断 spotter 由唤醒/切换时异步加载；配对的流随 spotter 变化重建。
                    cur_spotter = self._interrupt_spotter
                    if cur_spotter is not _interrupt_spotter_ref:
                        _interrupt_spotter_ref = cur_spotter
                        _interrupt_stream = (
                            cur_spotter.create_stream() if cur_spotter is not None else None
                        )

                    if cur_spotter is not None and _interrupt_stream is not None:
                        _interrupt_stream.accept_waveform(self._asr_rate, asr_samples)
                        while cur_spotter.is_ready(_interrupt_stream):
                            cur_spotter.decode_stream(_interrupt_stream)
                            hit = cur_spotter.get_result(_interrupt_stream)
                            if hit:
                                print(f"\n[打断] 检测到打断词: {hit}")
                                # 打断整个处理流程：停止TTS + 中断OpenClaw
                                stop_tts()
                                self._interrupt_openclaw()
                                # 保持唤醒状态，允许直接继续说话
                                self.is_awake = True
                                self.continuous_mode = True
                                # 打断后重置空闲计时，避免立即触发 30s 空闲超时退出
                                self.last_voice_time = time.time()
                                # 重置识别器与打断流，准备接收新指令
                                recognition_stream = self.recognizer.create_stream()
                                recognition_result = ""
                                cur_spotter.reset_stream(_interrupt_stream)
                                _interrupt_stream = cur_spotter.create_stream()
                                print("\n请说出指令...")
                                break

                    self._clear_queue()
                    continue

                if audio_stream is None:
                    start_audio_stream()

                try:
                    audio_data = self.audio_queue.get(timeout=0.5)
                except queue.Empty:
                    # 音频流假死兜底：不论待机还是已唤醒，只要持续拿不到帧就重建。
                    # 旧逻辑仅在 not is_awake 时重建，导致"唤醒态麦克风假死"时主循环
                    # 在此处静默空转——既不打印日志、回不了待机、也唤不醒。
                    stalled = time.time() - self.last_activity_time
                    if stalled > _AUDIO_STALL_TIMEOUT:
                        was_awake = self.is_awake
                        print(
                            f"[看门狗] 音频流 {stalled:.0f}s 无数据，判定假死，正在重建"
                            + ("（并强制回到待机）..." if was_awake else "...")
                        )
                        # 死流期间可能卡住的状态全部复位，确保能重新被唤醒
                        if was_awake:
                            self.is_awake = False
                            self.continuous_mode = False
                            recognition_stream = None
                            recognition_result = ""
                        stop_audio_stream()
                        time.sleep(0.1)
                        self._clear_queue()
                        keyword_stream = self.keyword_spotter.create_stream()
                        start_audio_stream()
                        time.sleep(0.1)
                        self._clear_queue()
                        self.last_activity_time = time.time()
                        print("[看门狗] 音频流已重建，等待唤醒词...")
                    continue

                samples = audio_data.reshape(-1)
                asr_samples = self._resample_for_asr(samples)
                self.last_activity_time = time.time()

                if not self.is_awake:
                    # 持续缓冲音频用于声纹验证（16kHz，与模型匹配）
                    self._wake_audio_buffer.append(asr_samples.tolist())
                    total_len = sum(len(b) for b in self._wake_audio_buffer)
                    while total_len > self._wake_buffer_max_samples:
                        removed = self._wake_audio_buffer.pop(0)
                        total_len -= len(removed)

                    # 维护 VAD 前后缓存（最近 2 秒，16kHz）
                    self._vad_buffer.append(asr_samples.tolist())
                    vad_total = sum(len(b) for b in self._vad_buffer)
                    while vad_total > self._vad_buffer_max_samples:
                        self._vad_buffer.pop(0)
                        vad_total = sum(len(b) for b in self._vad_buffer)

                    # VAD 检测：有语音时才继续处理，抑制非人声（如电脑播放的人声/TTS）
                    vad_has_speech = False
                    if vad_stream is not None:
                        vad_stream.accept_waveform(asr_samples)
                        if vad_stream.is_speech_detected():
                            vad_has_speech = True

                    # DND 解除瞬间：重建 KWS 流，清掉跨越勿扰边界残留的半个唤醒词，
                    # 避免声纹录入刚结束就被尾音误唤醒（边沿触发，仅在 True→False 时执行一次）
                    if self._prev_dnd_mode and not _dnd_mode:
                        keyword_stream = self.keyword_spotter.create_stream()
                        if self._continuous_wake_asr:
                            standby_recognition_stream = self.recognizer.create_stream()
                            standby_recognition_result = ""
                            standby_last_result_time = time.time()
                            standby_audio_buffer = []
                    self._prev_dnd_mode = _dnd_mode

                    # 实验路径：VAD 后的完整话语持续进入普通 ASR，endpoint 后再从
                    # 文本中提取“唤醒词 + 指令”。验证使用同一句的音频；失败静默丢弃。
                    # 此分支开启时不再并行跑 KWS，避免 KWS 提前命中并清掉后续指令。
                    if self._continuous_wake_asr:
                        standby_audio_buffer.append(asr_samples.tolist())
                        standby_total = sum(len(buf) for buf in standby_audio_buffer)
                        while standby_total > self._standby_utterance_max_samples:
                            standby_total -= len(standby_audio_buffer.pop(0))

                        standby_recognition_stream.accept_waveform(
                            self._asr_rate, asr_samples
                        )
                        while self.recognizer.is_ready(standby_recognition_stream):
                            self.recognizer.decode_stream(standby_recognition_stream)
                        standby_result = self.recognizer.get_result(
                            standby_recognition_stream
                        )
                        if (
                            standby_result
                            and standby_result != standby_recognition_result
                        ):
                            standby_recognition_result = standby_result
                            standby_last_result_time = time.time()
                            print(
                                f"\r[待机 ASR] {standby_recognition_result}",
                                end="",
                                flush=True,
                            )

                        # KWS 与待机 ASR 并行：KWS 一命中就验证并激活，但绝不清空
                        # 音频队列或重建 ASR 流。后半句继续进入同一个识别 stream。
                        keyword_stream.accept_waveform(self._asr_rate, asr_samples)
                        early_wake_result = ""
                        while self.keyword_spotter.is_ready(keyword_stream):
                            self.keyword_spotter.decode_stream(keyword_stream)
                            early_wake_result = self.keyword_spotter.get_result(
                                keyword_stream
                            )
                            if early_wake_result:
                                break

                        if early_wake_result and not _dnd_mode:
                            is_assistant_wake = any(
                                wake_word in early_wake_result
                                or early_wake_result in wake_word
                                for wake_word in self.keyword_mapping
                            )
                            if not is_assistant_wake:
                                keyword_stream = self.keyword_spotter.create_stream()
                                continue
                            if vad_stream is not None and not vad_has_speech:
                                keyword_stream = self.keyword_spotter.create_stream()
                                continue

                            print(f"\n[实验] KWS 提前命中: {early_wake_result}")
                            wake_samples = [
                                sample
                                for buf in self._wake_audio_buffer
                                for sample in buf
                            ]
                            if self._speaker_enabled:
                                print(
                                    "[声纹] 唤醒词阶段立即进行声纹+活体验证 "
                                    f"(样本长度: {len(wake_samples)})"
                                )
                                if not self._verify_speaker_on_wake(
                                    wake_samples, self._asr_rate
                                ):
                                    print("[实验] 验证未通过，静默忽略")
                                    keyword_stream = self.keyword_spotter.create_stream()
                                    standby_recognition_stream = (
                                        self.recognizer.create_stream()
                                    )
                                    standby_recognition_result = ""
                                    standby_last_result_time = time.time()
                                    standby_audio_buffer = []
                                    continue
                                self._speaker_verified = True

                            detected_assistant_id = self._detect_assistant_from_keyword(
                                early_wake_result
                            )
                            if detected_assistant_id != self.current_cfg["id"]:
                                self._switch_assistant(detected_assistant_id)
                                self._init_openclaw()

                            self.is_awake = True
                            self.continuous_mode = True
                            self._wake_prefixed_command_pending = True
                            # 通用 ASR 可能把 KWS 已确认的 JARVIS 写成 JOVI 等近音词。
                            # 记住命中瞬间的 ASR 前缀，显示时用标准助手名替换，提交时剥离。
                            self._wake_asr_prefix = standby_recognition_result.strip()
                            target_cfg = self.all_assistants.get(
                                detected_assistant_id, self.current_cfg
                            )
                            self._wake_canonical_name = (
                                target_cfg.get("name")
                                or detected_assistant_id
                            )
                            wake_timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
                            self._wake_command_prefix = (
                                f"voice-assistant-wake-up-{wake_timestamp}"
                            )
                            self.last_voice_time = time.time()
                            self._last_wake_time = time.time()
                            # 关键：沿用待机阶段已经接收“唤醒词”的同一个 ASR 流。
                            recognition_stream = standby_recognition_stream
                            recognition_result = standby_recognition_result
                            keyword_stream = self.keyword_spotter.create_stream()
                            self.visual.show_wake_effect()
                            print("[实验] 身份验证通过，立即激活并继续听取本句指令...")
                            continue

                        standby_endpoint = self.recognizer.is_endpoint(
                            standby_recognition_stream
                        )
                        standby_stable_timeout = (
                            bool(standby_recognition_result)
                            and time.time() - standby_last_result_time
                            > _env_float(
                                "VOICE_ASSISTANT_STANDBY_SILENCE_SECONDS", 1.5
                            )
                        )
                        if standby_endpoint or standby_stable_timeout:
                            final_text = standby_recognition_result.strip()
                            if final_text:
                                print(f"\n[待机 ASR] 完整话语: {final_text}")
                            wake_command = self._extract_standby_wake_command(final_text)
                            utterance_samples = [
                                sample
                                for buf in standby_audio_buffer
                                for sample in buf
                            ]
                            standby_recognition_stream = self.recognizer.create_stream()
                            standby_recognition_result = ""
                            standby_last_result_time = time.time()
                            standby_audio_buffer = []

                            if _dnd_mode or not wake_command:
                                continue

                            detected_assistant_id, wake_word, command = wake_command
                            print(
                                f"\n[实验] 完整话语命中唤醒词: {wake_word}; "
                                f"指令: {command or '(空)'}"
                            )
                            if self._speaker_enabled:
                                print(
                                    "[声纹] 使用完整待机话语进行声纹+活体验证 "
                                    f"(样本长度: {len(utterance_samples)})"
                                )
                                if not self._verify_speaker_on_wake(
                                    utterance_samples, self._asr_rate
                                ):
                                    print("[实验] 验证未通过，静默忽略")
                                    continue
                                self._speaker_verified = True

                            if detected_assistant_id != self.current_cfg["id"]:
                                self._switch_assistant(detected_assistant_id)
                                self._init_openclaw()

                            self.is_awake = True
                            self.continuous_mode = True
                            self.last_voice_time = time.time()
                            self._last_wake_time = time.time()
                            recognition_result = ""
                            recognition_stream = self.recognizer.create_stream()
                            keyword_stream = self.keyword_spotter.create_stream()
                            self.visual.show_wake_effect()
                            print("[实验] 验证通过，助手已激活")

                            if command:
                                self.visual.show_user_text(command)
                                threading.Thread(
                                    target=self._on_recognized,
                                    args=(command,),
                                    daemon=True,
                                ).start()
                            elif self._has_inflight_task():
                                self._ask_resume_decision()
                            else:
                                print("[实验] 未附带指令，等待下一句话...")
                            continue

                        # endpoint 前留在待机 ASR 分支，不让旧 KWS 提前抢占。
                        continue

                    # KWS 实时检测
                    keyword_stream.accept_waveform(self._asr_rate, asr_samples)

                    while self.keyword_spotter.is_ready(keyword_stream):
                        self.keyword_spotter.decode_stream(keyword_stream)
                        result = self.keyword_spotter.get_result(keyword_stream)
                        if result:
                            if _dnd_mode:
                                keyword_stream = self.keyword_spotter.create_stream()
                                continue
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

                            # VAD 前置过滤：KWS 检测到候选唤醒词时，用 VAD 确认是否有真实语音
                            if vad_stream is not None and not vad_has_speech:
                                self.keyword_spotter.reset_stream(keyword_stream)
                                keyword_stream = self.keyword_spotter.create_stream()
                                continue

                            print(f"\n检测到唤醒词: {result}")

                            # ── 声纹验证 ──────────────────────────────────────
                            if self._speaker_enabled:
                                # 从缓冲区取出最近 3 秒音频用于验证
                                wake_samples = []
                                for buf in self._wake_audio_buffer:
                                    wake_samples.extend(buf)
                                if len(wake_samples) > self._wake_buffer_max_samples:
                                    wake_samples = wake_samples[-self._wake_buffer_max_samples:]
                                print(f"[声纹] 唤醒词检测成功，准备验证声纹 (样本长度: {len(wake_samples)})")
                                is_verified = self._verify_speaker_on_wake(wake_samples, self._asr_rate)
                                if not is_verified:
                                    reason = self._last_wake_rejection or {}
                                    title = reason.get("title", "验证未通过")
                                    print(f"[唤醒] 唤醒被拒绝: {title}")
                                    # 异步发送通知，避免 2 秒 connect 超时阻塞主循环
                                    threading.Thread(
                                        target=_notify_wake_rejected,
                                        args=(reason,),
                                        daemon=True,
                                    ).start()
                                    self._wake_audio_buffer.clear()
                                    self.keyword_spotter.reset_stream(keyword_stream)
                                    print("[声纹] 继续监听...")
                                    continue
                                self._wake_audio_buffer.clear()
                                self._speaker_verified = True  # 标记唤醒者已通过声纹验证

                            # 识别是哪个 assistant 的唤醒词，并切换
                            detected_assistant_id = self._detect_assistant_from_keyword(
                                result
                            )
                            if detected_assistant_id != self.current_cfg["id"]:
                                print(
                                    f"[切换] 检测到 {self.keyword_mapping.get(result, detected_assistant_id)} 的唤醒词，正在切换..."
                                )
                                self._switch_assistant(detected_assistant_id)
                                self._init_openclaw()

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
                                vad_stream = None
                                _create_vad_stream()
                                audio_buffer = []
                                speech_started = False

                            self.visual.show_wake_effect()
                            # 唤醒后发"voice-assistant-wake-up"给后端引擎，由引擎返回
                            # 问候播报。改为在线程里跑 + 立即恢复音频流，支持唤醒后打断。
                            # 例外：退下时软停的后台任务仍在跑 → 不发问候（问候会让模型
                            # 顺着 session 里的未完成任务继续），改问"要不要继续"，
                            # 下一句话按 是/否 决策处理（见 _on_recognized）。
                            if self._has_inflight_task():
                                self._ask_resume_decision()
                            else:
                                # 清掉可能残留的待决策标志（上次问了没答就睡了），
                                # 否则问候标记会被误判成 是/否 回答。
                                self._pending_resume_decision = False
                                _wake_ts = time.strftime("%Y-%m-%d %H:%M:%S")
                                wake_thread = threading.Thread(
                                    target=self._on_recognized,
                                    args=(f"voice-assistant-wake-up-{_wake_ts}",),
                                    daemon=True,
                                )
                                wake_thread.start()

                            # 唤醒线程在后台跑，主循环恢复音频流后检测打断。
                            # 返回后必须复位 suppress（它在上方 1597 行附近被置 True），否则
                            # 后续用户每句识别结果都会被丢弃，最终静音超时误退出。
                            self._suppress_recognition_until_tts_done = False
                            self._ignore_next_result = False
                            self._last_wake_time = (
                                time.time()
                            )  # 记录唤醒时间，唤醒后保护期内跳过退出检测

                            for _ in range(20):
                                self._clear_queue()
                            recognition_result = ""
                            start_audio_stream()
                            time.sleep(0.05)
                            for _ in range(20):
                                self._clear_queue()
                            continue
                    if not self.is_awake:
                        continue

                else:
                    # 已唤醒且不在处理中，正常处理语音识别
                    if recognition_stream is None:
                        recognition_stream = self.recognizer.create_stream()

                    # 持续缓冲音频用于声纹渐进更新（16kHz，与模型匹配）
                    self._conv_audio_buffer.append(asr_samples.tolist())
                    conv_total = sum(len(b) for b in self._conv_audio_buffer)
                    while conv_total > self._conv_buffer_max_samples:
                        removed = self._conv_audio_buffer.pop(0)
                        conv_total -= len(removed)

                    recognition_stream.accept_waveform(self._asr_rate, asr_samples)

                    while self.recognizer.is_ready(recognition_stream):
                        self.recognizer.decode_stream(recognition_stream)

                    result = self.recognizer.get_result(recognition_stream)
                    if result and result != recognition_result:
                        recognition_result = result
                        self.last_voice_time = time.time()
                        display_result = result
                        if self._wake_prefixed_command_pending:
                            display_tail, prefix_stripped = (
                                self._strip_kws_confirmed_wake_prefix(result)
                            )
                            if prefix_stripped:
                                display_result = (
                                    self._wake_canonical_name + display_tail
                                )
                            if self._is_complete_wake_phrase_tail(display_tail):
                                display_result = "Is Jarvis here?"
                        if not self._suppress_recognition_until_tts_done:
                            print(f"\r✓ 识别: {display_result}", end="", flush=True)
                        self.visual.show_user_text(display_result)

                    _early_recog = (
                        recognition_result.strip() if recognition_result else ""
                    )
                    # 打断后 2 秒内、唤醒后 2 秒内跳过退出检测，避免残留音频误触发
                    _recent_interrupt = (time.time() - self._last_interrupt_time) < 2.0
                    _recent_wake = (time.time() - self._last_wake_time) < 2.0
                    _early_exit = (
                        _early_recog
                        and not _recent_interrupt
                        and not _recent_wake
                        and (
                            _early_recog in EXIT_KEYWORDS
                            or _early_recog in INSTANT_EXIT_FUZZY
                        )
                    )
                    if _early_exit:
                        _is_instant = _is_instant_exit(_early_recog)
                        if _is_instant:
                            print(f"\n收到退出指令（立即执行）: {_early_recog}")
                        else:
                            print(f"\n收到退出指令（延时1s执行）: {_early_recog}")
                            time.sleep(1.0)
                        self.exit_standby(instant=_is_instant)
                        recognition_result = ""
                        recognition_stream = self.recognizer.create_stream()
                        stop_audio_stream()
                        self._clear_queue()
                        start_audio_stream()
                        keyword_stream = self.keyword_spotter.create_stream()
                        continue

                    current_time = time.time()
                    silence_duration = current_time - self.last_voice_time
                    idle_duration = current_time - self.last_activity_time

                    if (
                        self.continuous_mode
                        and silence_duration > self.idle_timeout
                        # 任务执行中（OpenClaw 请求/TTS 播报）不计空闲超时，
                        # 防止线程标志设置窗口或回复延迟期间被误判待机
                        and not self._is_processing
                        and not self._is_openclaw_busy
                    ):
                        print(
                            f"\n连续对话超时（{self.idle_timeout}秒无活动），自动退出"
                        )
                        self.exit_standby()
                        recognition_result = ""
                        self.keyword_spotter.reset_stream(keyword_stream)
                        keyword_stream = self.keyword_spotter.create_stream()
                        continue

                    _ep = self.recognizer.is_endpoint(recognition_stream)
                    # 文件级诊断（节流 2s，仅落盘、不进控制中心）：专抓"说完话后
                    # 一直卡在 listening"的现行——记录决定断句的全部变量，下次卡住
                    # 看 jarvis_diag_*.log 即可判明是哪个条件没满足。
                    if self.is_awake and (current_time - self._last_diag_log) > 2.0:
                        self._last_diag_log = current_time
                        _diag.info(
                            "LISTEN ep=%s sil=%.1f res_len=%d sup=%s proc=%s busy=%s cont=%s",
                            _ep, silence_duration, len(recognition_result or ""),
                            self._suppress_recognition_until_tts_done,
                            self._is_processing, self._is_openclaw_busy,
                            self.continuous_mode,
                        )

                    if _ep or (
                        recognition_result
                        and silence_duration > _env_float("VOICE_ASSISTANT_SILENCE_DURATION_SECONDS", 1.5)
                    ):
                        if recognition_result:
                            should_suppress = self._suppress_recognition_until_tts_done

                            if should_suppress:
                                print("[打断] TTS播放中/等待稳定，忽略识别结果")
                                _diag.warning(
                                    "断句命中但 suppress=True → 丢弃结果(%r)并继续监听"
                                    "（若反复出现即 suppress 标志卡死）",
                                    (recognition_result or "")[:40],
                                )
                                recognition_result = ""
                                recognition_stream = self.recognizer.create_stream()
                                start_audio_stream()
                                continue

                            print("\n识别结果:", recognition_result)

                            stop_audio_stream()
                            self._clear_queue()

                            _recog = recognition_result.strip()
                            if self._wake_prefixed_command_pending:
                                self._wake_prefixed_command_pending = False
                                command, prefix_stripped = (
                                    self._strip_kws_confirmed_wake_prefix(_recog)
                                )
                                if prefix_stripped:
                                    recognition_result = command
                                    _recog = command.strip()
                                    print(
                                        "[实验] KWS 已确认唤醒，移除 ASR 句首唤醒转写，"
                                        f"最终指令: {_recog or '(空)'}"
                                    )
                                if self._is_complete_wake_phrase_tail(_recog):
                                    print(
                                        f"[实验] {_recog!r} 识别为完整唤醒短语尾部，"
                                        "不作为指令提交"
                                    )
                                    recognition_result = ""
                                    _recog = ""
                                # 若 ASR 从唤醒词之后才开始产出文本，则保留原结果。
                                self._wake_asr_prefix = ""
                                self._wake_canonical_name = ""

                                if not _recog:
                                    recognition_result = ""
                                    recognition_stream = self.recognizer.create_stream()
                                    if self._wake_command_prefix:
                                        wake_only_text = self._wake_command_prefix
                                        self._wake_command_prefix = ""
                                        print("[实验] 完整唤醒短语，发送纯 wake-up 上下文")
                                        threading.Thread(
                                            target=self._on_recognized,
                                            args=(wake_only_text,),
                                            daemon=True,
                                        ).start()
                                    else:
                                        print("[实验] 本句没有附带指令，继续等待...")
                                    continue
                            # 打断后 2 秒内、唤醒后 2 秒内跳过退出检测，避免残留音频误触发
                            _recent_interrupt = (
                                time.time() - self._last_interrupt_time
                            ) < 2.0
                            _recent_wake = (time.time() - self._last_wake_time) < 2.0
                            _is_exit = (
                                not _recent_interrupt
                                and not _recent_wake
                                and (
                                    _recog in EXIT_KEYWORDS
                                    or _recog in INSTANT_EXIT_FUZZY
                                )
                            )
                            if _is_exit:
                                print(f"收到退出指令: {recognition_result.strip()}")
                                self._interrupt_openclaw()
                                # self._clear_openclaw_context()
                                stop_audio_stream()
                                self._clear_queue()
                                self.jarvis.on_exit()
                                self.visual.clear_texts()
                                self.visual.hide_effects()
                                if not _is_instant_exit(_recog):
                                    play_prebuilt_voice("exit", _random_exit_line())
                                    while is_tts_playing():
                                        time.sleep(0.05)
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

                            # 检测重启关键词
                            _is_restart = _recog in RESTART_KEYWORDS
                            if _is_restart:
                                print(f"收到重启指令: {recognition_result.strip()}")
                                self._restart_assistant()
                                recognition_result = ""
                                continue

                            self.visual.show_user_text(recognition_result)
                            if not self._ignore_next_result:
                                dispatch_text = recognition_result
                                if self._wake_command_prefix:
                                    dispatch_text = (
                                        f"{self._wake_command_prefix}\n{recognition_result}"
                                    )
                                    print(
                                        "[实验] 发送带唤醒上下文的指令: "
                                        f"{self._wake_command_prefix} + {recognition_result}"
                                    )
                                    self._wake_command_prefix = ""
                                threading.Thread(
                                    target=self._on_recognized,
                                    args=(dispatch_text,),
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
                                # 不再打印提示——_on_recognized 回复完成后会统一提示用户
                            else:
                                if not self._is_openclaw_busy:
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
                                if not self._is_openclaw_busy:
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
                speech_started = False
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
        """执行打断操作：软停止（断点续传），不中断后台任务。

        打断时只停 TTS 播报和流式回调，SSE 连接保持不断开。
        浏览器等后台资源继续运行，由 idle reaper 在超时后自动回收。
        快路径识别到「中断任务」意图时，改调 _cancel_task()。
        """
        print("\n[打断] 检测到唤醒词，执行软停止（断点续传）...")
        # 软停止：标记请求已停止，TTS 静默，但不断开 SSE 连接
        self.openclaw.send_stop_command()
        # 设置停止标志，用于阻塞等待循环
        self._stop_openclaw_request.set()
        # 立即重置状态，确保可以重新唤醒
        self._is_openclaw_busy = False
        self._is_processing = False
        self.continuous_mode = False
        if hasattr(self, "_waiting_active"):
            self._waiting_active.clear()
        # 停止 TTS 播放
        stop_tts()
        # 记录打断时间，用于防止后续误触发退出检测
        self._last_interrupt_time = time.time()
        print("[打断] 软停止完成，后台任务继续运行")

    def _cancel_task(self):
        """硬取消任务：快路径识别到「中断任务」意图时调用。

        断开 SSE 连接，触发 agent.interrupt()，浏览器等后台资源
        会被清理。用于用户明确要求取消任务。
        """
        print("\n[取消任务] 快路径识别到中断任务意图，执行硬取消...")
        self.openclaw.cancel_task()
        self._stop_openclaw_request.set()
        self._is_openclaw_busy = False
        self._is_processing = False
        self.continuous_mode = False
        if hasattr(self, "_waiting_active"):
            self._waiting_active.clear()
        stop_tts()
        self._last_interrupt_time = time.time()
        print("[取消任务] 硬取消完成，后台资源将被清理")

    def _interrupt_openclaw_silent(self):
        """静默软停止：退下时调用，不断开连接。

        仅标记请求已软停、重置状态、停 TTS。后台任务继续运行。
        """
        self.openclaw.send_stop_command()  # 软停止，不断开 SSE
        self._stop_openclaw_request.set()
        self._is_openclaw_busy = False
        self._is_processing = False
        self.continuous_mode = False
        if hasattr(self, "_waiting_active"):
            self._waiting_active.clear()
        stop_tts()
        # 同样记录打断时间，防止误触发退出检测
        self._last_interrupt_time = time.time()

    def _clear_openclaw_context(self):
        """退下时通知主脑清空会话上下文（异步，不阻塞）"""
        try:
            self.openclaw.send_clear_command()
            print(f"[{self._agent_label()}] 已发送 /clear，清空会话上下文")
        except Exception as e:
            print(f"[{self._agent_label()}] 发送 /clear 失败: {e}")

    def _route_stream(self, text, on_chunk=None, on_start=None, on_end=None,
                      on_tool_call=None, force_agent_reason: str = ""):
        """分流：轻消息白名单进快模型，其余默认走 agent。

        与桥 send_and_wait_stream 同签名/同回调契约——TTS 流水线、等待音、结果处理
        全部复用，两条路对上层完全透明。未配置快模型 / 非轻消息 / 快路径失败，
        一律走 agent 兜底（fail-open）。
        """
        import routing
        fp = getattr(self, "_fast_path", None)
        use_fast = (
            fp is not None
            and fp.is_available()
            and not force_agent_reason
            and routing.is_obviously_light(text)
        )
        if use_fast:
            try:
                from fast_path import AgentHandoff
                return fp.send_and_wait_stream(
                    text, on_chunk=on_chunk, on_start=on_start, on_end=on_end,
                )
            except AgentHandoff as h:
                print(f"[分流] 升级 agent（{h.reason}）: {h.task[:50]}")
                text = h.task or text  # 用模型清洗过的任务文本（兜底原文）
        else:
            if force_agent_reason:
                reason = f"原文强制 agent: {force_agent_reason}"
            else:
                reason = "无快模型" if (fp is None or not fp.is_available()) else "非轻消息"
            print(f"[分流] 直连 agent（{reason}）")

        # 重路径：agent 桥（openclaw / hermes），保持原有行为不变
        return self.openclaw.send_and_wait_stream(
            text, on_chunk=on_chunk, on_start=on_start, on_end=on_end,
            on_tool_call=on_tool_call,
        )

    # ── 唤醒待决策：退下后台任务续做/搁置 ──────────────────────────

    def _has_inflight_task(self) -> bool:
        """当前桥是否有"被软停但后台仍在跑"的任务。仅 hermes 桥支持，其余退化为 False。"""
        fn = getattr(self.openclaw, "has_inflight_task", None)
        try:
            return bool(fn()) if callable(fn) else False
        except Exception:  # noqa: BLE001 — 检测失败一律退化为"无在跑任务"，走正常问候
            return False

    def _ask_resume_decision(self):
        """唤醒时发现后台任务在跑：不发问候，改问是否继续，置待决策标志。

        同步播报（此刻音频流已停，见主循环 stop_audio_stream→start_audio_stream 区间），
        问话期间不会被自身回声误识别；播报完主循环恢复音频流，用户下一句即答案。
        """
        self._pending_resume_decision = True
        self._last_wake_time = time.time()  # 保护期，避免问话回声误触发退出检测
        hint = ""
        fn = getattr(self.openclaw, "pending_task_hint", None)
        if callable(fn):
            try:
                hint = (fn() or "").strip()
            except Exception:  # noqa: BLE001
                hint = ""
        print(f"[待决策] 后台任务在跑（{hint[:40] or '未知'}），询问是否继续...")
        try:
            text_to_speech_play("Sir, the previous task is still running. Shall I continue?")
        except Exception as e:  # noqa: BLE001 — 播报失败不影响后续决策监听
            print(f"[待决策] 询问播报失败（忽略）: {e}")

    @staticmethod
    def _classify_resume_reply(text: str) -> str:
        """把用户对"要不要继续"的回答分成 resume / abandon / new_command。

        规则（保守，避免误判）：
          - 含明确否定词 → 纯短否定当 abandon，否定+其它内容当 new_command；
          - 含"继续/接着" → resume；极短肯定词（≤3字：要/好/是/对/嗯/行）→ resume；
          - 其余（既不像肯定也不像否定）→ new_command（顺带搁置旧任务）。
        """
        t = (text or "").strip()
        if not t:
            return "abandon"
        low = t.lower()
        no_words = ("不用", "不要", "别", "算了", "取消", "停", "no", "stop", "cancel")
        if any(k in low for k in no_words) or t in ("不", "不了"):
            return "abandon" if len(t) <= 4 else "new_command"
        if "继续" in t or "接着" in t or low in ("yes", "continue", "go on"):
            return "resume"
        if len(t) <= 3 and any(k in low for k in ("要", "好", "是", "对", "嗯", "行", "ok")):
            return "resume"
        return "new_command"

    def _abandon_previous_task(self):
        """标记搁置上一任务：后台悄声跑完，但注入提示阻止模型再主动接续。"""
        fn = getattr(self.openclaw, "mark_previous_task_abandoned", None)
        if callable(fn):
            try:
                fn()
            except Exception:  # noqa: BLE001
                pass

    def _prepare_agent_text(self, text: str) -> str:
        """Jarvis full-English mode: translate Chinese before agent routing."""
        # 组合唤醒指令的协议前缀必须原样保留，只翻译后面的自然语言任务。
        if text.startswith("voice-assistant-wake-up-") and "\n" in text:
            wake_prefix, command = text.split("\n", 1)
            return f"{wake_prefix}\n{self._prepare_agent_text(command)}"
        if self.current_cfg.get("id") != "jarvis":
            return text
        if not self.current_cfg.get("full_english_mode", False):
            return text
        try:
            from translation import contains_cjk, translate_to_english
        except Exception as e:  # noqa: BLE001
            print(f"[语言模式] 翻译模块不可用，保持原文: {e}")
            return text

        if not contains_cjk(text):
            return text

        try:
            import routing
            original_needs_live_data = routing.needs_live_data(text)
        except Exception:  # noqa: BLE001
            routing = None
            original_needs_live_data = False

        result = translate_to_english(text)
        print("[语言模式] english")
        print(f"[翻译] zh->en {result.latency_ms}ms")
        print(f"[翻译] 原文: {_short_log_text(result.original_text)}")
        if result.success and result.translated_text:
            translated = result.translated_text
            if (
                original_needs_live_data
                and routing is not None
                and not routing.needs_live_data(translated)
            ):
                translated = f"Current live-data request: {translated}"
            print(f"[翻译] EN: {_short_log_text(translated)}")
            return translated

        fallback = (
            "Sorry, sir. The local translator failed, so I will not send the "
            "Chinese request to Jarvis."
        )
        print(f"[翻译] 失败: {result.error or 'unknown'}")
        return fallback

    @staticmethod
    def _agent_handoff_intent(text: str) -> str:
        try:
            import routing
            return routing.handoff_intent(text)
        except Exception:  # noqa: BLE001
            return ""

    def _on_recognized(self, text: str):
        """识别结果 → 发送给当前主脑 → 整体合成播报回复"""
        # 唤醒待决策：上一句问了"要不要继续"，这句就是回答。
        if self._pending_resume_decision:
            self._pending_resume_decision = False
            decision = self._classify_resume_reply(text)
            print(f"[待决策] 回答={text!r} → {decision}")
            if decision == "resume":
                text = "接着刚才的任务，继续。"  # 走正常 turn，引擎靠 session 上下文接续
            elif decision == "abandon":
                self._abandon_previous_task()
                try:
                    text_to_speech_play("Understood, sir. I will set that aside.")
                except Exception:  # noqa: BLE001
                    pass
                return  # 本轮不发引擎
            else:  # new_command：搁置旧任务，把这句当新指令发引擎
                self._abandon_previous_task()

        original_handoff_intent = self._agent_handoff_intent(text)
        text = self._prepare_agent_text(text)
        agent_label = self._agent_label()
        print(f"\n[→ {agent_label}] {text}")

        # 在发送给主脑之前的一瞬间，还原特效大小
        self.visual.reset_speaking_scale()

        print("◈ 正在思考...", end="", flush=True)

        with self._processing_turn_lock:
            self._processing_turn_id += 1
            turn_id = self._processing_turn_id
            self._is_processing = True  # 标记全流程：指令发出→主脑回复→TTS播报完毕
            self._is_openclaw_busy = True
        self._stop_openclaw_request.clear()
        self._openclaw_request_active.set()

        try:
            import threading
            import queue

            result_queue = queue.Queue()

            # ── 增量 TTS：边收边按句朗读（串行队列）──────────────────────
            # OpenClaw 流式输出时：遇句末标点即把整句送入朗读队列；若超过
            # _TTS_DEBOUNCE_SEC 无新输出，则把缓冲内容也送入队列（应对无标点的
            # 停顿，如等待工具调用）。朗读队列由单独线程串行消费，逐句合成播放，
            # 从而把"等整段说完"降到"等第一句"。
            from tts import _tts_playing

            _TTS_DEBOUNCE_SEC = 1.5
            _TTS_SENT_END = "。！？!?；;…\n"

            synth_queue = queue.Queue()
            tts_buf = {"text": "", "last": time.time()}
            tts_buf_lock = threading.Lock()
            tts_threads_stop = threading.Event()

            # ── 合成/播放流水线：多线程并行合成 + 单线程有序播放 ──────────
            # 每个切片按入队顺序分配递增 seq。多个合成线程并行把切片合成成
            # 音频，结果按 seq 存入 results；单个播放线程严格按 seq 0,1,2… 顺序
            # 播放——靠后的切片即便先合成好也要等前面的，保证播报顺序不乱。
            # 好处：合成耗时被并行掉，句与句之间几乎无停顿。
            seq_ctr = {"n": 0}
            results = {}                  # seq -> (audio, sr) | None(失败/跳过)
            results_cond = threading.Condition()
            play_total = {"n": None}      # 生产结束后置为总切片数，播放线程据此收尾

            def _flush_segment(force=False):
                """把缓冲里的完整句子（force 时为剩余全部）按 4 句分批入队合成。"""
                with tts_buf_lock:
                    buf = tts_buf["text"]
                    if not buf:
                        return
                    if force:
                        seg, tts_buf["text"] = buf, ""
                    else:
                        idx = max(
                            (buf.rfind(c) for c in _TTS_SENT_END), default=-1
                        )
                        if idx < 0:
                            return
                        seg, tts_buf["text"] = buf[: idx + 1], buf[idx + 1 :]
                    seg = _clean_for_tts(seg)
                    if not seg.strip():
                        return
                    # 长句/长段落不一次性整段合成：每 4 句切一批。
                    # 在锁内分配 seq 并入队，保证多线程（chunk 回调 + flusher）
                    # 并发调用时切片顺序不乱。
                    for batch in _batch_sentences(
                        seg,
                        _TTS_SENT_END,
                        _env_int("VOICE_ASSISTANT_TTS_MAX_SENTENCES", 4),
                    ):
                        if not batch.strip():
                            continue
                        seq = seq_ctr["n"]
                        seq_ctr["n"] += 1
                        synth_queue.put((seq, batch))

            def _synth_worker():
                """并行合成：取切片 → 合成 → 按 seq 存结果并通知播放线程。"""
                while True:
                    item = synth_queue.get()
                    if item is None:
                        break
                    seq, text = item
                    result = None
                    if not self._stop_openclaw_request.is_set():
                        result = self.tts.synthesize_to_array(text)
                    with results_cond:
                        results[seq] = result  # 即便失败/跳过也记 None，避免播放线程死等
                        results_cond.notify_all()

            def _play_worker():
                """有序播放：严格按 seq 0,1,2… 顺序，缺哪个等哪个。"""
                from audio import play_array

                next_seq = 0
                while True:
                    with results_cond:
                        while True:
                            if self._stop_openclaw_request.is_set():
                                return
                            if (play_total["n"] is not None
                                    and next_seq >= play_total["n"]):
                                return  # 全部切片已播完
                            if next_seq in results:
                                break
                            results_cond.wait(timeout=0.2)
                        result = results.pop(next_seq)
                    next_seq += 1
                    if not result or self._stop_openclaw_request.is_set():
                        continue
                    audio_data, sr = result
                    _tts_playing.set()
                    # 统一播放出口：重采样到设备原生采样率消除电流杂音，
                    # 打断时立即停掉当前句
                    play_array(
                        audio_data, sr, volume=1.5, blocking=True,
                        stop_check=self._stop_openclaw_request.is_set,
                    )

            def _tts_flusher():
                """监控停顿：缓冲非空且超过 debounce 无新输出则触发朗读。"""
                while not tts_threads_stop.is_set():
                    time.sleep(0.15)
                    if self._stop_openclaw_request.is_set():
                        return
                    with tts_buf_lock:
                        has = bool(tts_buf["text"].strip())
                        idle = time.time() - tts_buf["last"]
                    if has and idle >= _TTS_DEBOUNCE_SEC:
                        _flush_segment(force=True)

            # 合成线程数按设备逻辑核数动态决定（不硬编码）：约半数核、至少 1，
            # 兼顾并行加速与不过度抢占（合成为 CPU 密集，ONNX 内部亦用多线程）。
            num_synth_workers = max(1, (os.cpu_count() or 2) // 2)
            synth_threads = [
                threading.Thread(target=_synth_worker, daemon=True)
                for _ in range(num_synth_workers)
            ]
            play_thread = threading.Thread(target=_play_worker, daemon=True)
            tts_flusher_thread = threading.Thread(target=_tts_flusher, daemon=True)
            for _t in synth_threads:
                _t.start()
            play_thread.start()
            tts_flusher_thread.start()

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

                waiting_thread = threading.Thread(
                    target=_waiting_sound_loop, daemon=True
                )
                waiting_thread.start()

                received_chunks = []
                stop_requested = threading.Event()

                def _on_stream_start():
                    if self._stop_openclaw_request.is_set():
                        stop_requested.set()
                        return
                    self._waiting_active.clear()
                    time.sleep(0.05)
                    print(f"\n[← {agent_label}] ", end="", flush=True)

                def _on_stream_chunk(chunk):
                    if self._stop_openclaw_request.is_set():
                        stop_requested.set()
                        return
                    received_chunks.append(chunk)
                    full_text = "".join(received_chunks)
                    print(chunk, end="", flush=True)
                    self.visual.show_ai_text(full_text)
                    # 累积到朗读缓冲，遇句末标点立即切句入队
                    with tts_buf_lock:
                        tts_buf["text"] += chunk
                        tts_buf["last"] = time.time()
                    _flush_segment(force=False)

                def _on_stream_end():
                    if not stop_requested.is_set():
                        self._waiting_active.clear()

                def _on_stream_tool_call(name, args):
                    # 模型只发 tool_use、无文本时 on_start 不会触发，on_end 会把
                    # waiting 提示音关掉，导致工具执行的数秒里纯静默（用户感知为
                    # "0 回复"）。这里在工具调用时重新拉起 waiting 音，堵住静默窗口，
                    # 直到下一段文本到来（_on_stream_start 再关掉它）。
                    if self._stop_openclaw_request.is_set():
                        return
                    if received_chunks:
                        return  # 已经开口说过话，无需提示音兜底
                    if not self._waiting_active.is_set():
                        self._waiting_active.set()
                        threading.Thread(
                            target=_waiting_sound_loop, daemon=True
                        ).start()

                try:
                    reply = self._route_stream(
                        text,
                        on_chunk=_on_stream_chunk,
                        on_start=_on_stream_start,
                        on_end=_on_stream_end,
                        on_tool_call=_on_stream_tool_call,
                        force_agent_reason=original_handoff_intent,
                    )
                    self._waiting_active.clear()
                    waiting_thread.join(timeout=0.5)
                    result_queue.put(("success", reply))
                except Exception as e:
                    self._waiting_active.clear()
                    result_queue.put(("error", str(e)))
                finally:
                    with self._processing_turn_lock:
                        if self._processing_turn_id == turn_id:
                            self._is_openclaw_busy = False
                            self._openclaw_request_active.clear()

            request_thread = threading.Thread(target=_openclaw_request, daemon=True)
            request_thread.start()

            while True:
                try:
                    status, data = result_queue.get(timeout=0.5)
                    break
                except queue.Empty:
                    if self._stop_openclaw_request.is_set():
                        self.openclaw.send_stop_command()  # 软停止，不断开 SSE
                        print(f"\n[打断] {agent_label} 请求已软停止")
                        return

            if status == "success":
                reply = data
                if reply:
                    print()
                    # 流已结束：停止停顿监控，把剩余缓冲全部入队
                    tts_threads_stop.set()
                    if not self._stop_openclaw_request.is_set():
                        _flush_segment(force=True)
                    # 告知播放线程切片总数、唤醒它收尾；停掉各合成线程
                    with results_cond:
                        play_total["n"] = seq_ctr["n"]
                        results_cond.notify_all()
                    for _t in synth_threads:
                        synth_queue.put(None)
                    play_thread.join()

                    # TTS播报结束，检查是否被中断
                    if self._stop_openclaw_request.is_set():
                        print("\n[打断] TTS播报被中断，跳过收尾音效")
                        return

                    # 只在仍然处于连续对话模式时才提示继续
                    if self.continuous_mode:
                        print("◈ Go ahead, sir. I am listening...", flush=True)
                        self.jarvis.play_sound("continue")
                    return
                else:
                    fallback = "Sorry, sir. I did not receive a valid response from the main agent."
                    print(f"\n[← {agent_label}] (无回复)")
                    print(f"[{agent_label}] 空回复：请求完成但未收到文本内容")
                    self.visual.show_ai_text(fallback)
                    self.jarvis.on_error("No response")
                    if not self._stop_openclaw_request.is_set():
                        try:
                            text_to_speech_play(fallback)
                        except Exception as e:  # noqa: BLE001
                            print(f"[{agent_label}] 空回复兜底播报失败: {e}")
                    # 空回复时也根据连续对话状态给提示
                    if self.continuous_mode:
                        print("◈ Go ahead, sir. I am listening...", flush=True)
                        self.jarvis.play_sound("continue")
            else:
                print(f"[{agent_label}] 异常: {data}")
                self.jarvis.on_error(data)
        finally:
            # 兜底停掉增量 TTS 流水线与残留播放（打断/异常/无回复路径）
            try:
                tts_threads_stop.set()
                # 唤醒播放线程收尾（若未在成功分支设过总数）、停掉合成线程
                with results_cond:
                    if play_total["n"] is None:
                        play_total["n"] = seq_ctr["n"]
                    results_cond.notify_all()
                for _ in range(num_synth_workers):
                    synth_queue.put(None)
                _tts_playing.clear()
            except Exception:
                pass
            self.last_voice_time = time.time()
            with self._processing_turn_lock:
                if self._processing_turn_id == turn_id:
                    self._is_processing = False
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

    def exit_standby(self, instant: bool = False):
        """执行退下操作：从连续对话模式回到待机模式"""
        # 已经处于待机状态，跳过重复退出（防止 TTS 回声反复触发）
        if not self.is_awake and not self.continuous_mode:
            print("[exit_standby] 已在待机状态，跳过")
            return
        print("\n[收到退下信号]")
        # 退下即取消未答完的"是否继续"待决策，避免下次唤醒串状态。
        self._pending_resume_decision = False
        # 使用静默中断，避免重复发送 /stop 命令
        self._interrupt_openclaw_silent()
        # self._clear_openclaw_context()
        if hasattr(self, "_waiting_active"):
            self._waiting_active.clear()
        self.jarvis.on_exit()
        self.visual.clear_texts()
        self.visual.hide_effects()
        self.is_awake = False
        self.continuous_mode = False
        self._verified_speaker_name = None
        self._conv_audio_buffer.clear()
        # 退下时清空快路径滚动上下文，避免下次唤醒串上一次的追问语境
        _fp = getattr(self, "_fast_path", None)
        if _fp is not None:
            _fp.reset()
        play_prebuilt_voice("exit", _random_exit_line())
        while is_tts_playing():
            time.sleep(0.05)
        self._clear_queue()
        # 通知主循环重置 keyword_stream 和 audio_stream
        self._keyword_stream_reset_event.set()
        # 清除停止标志，确保不影响后续唤醒
        self._stop_openclaw_request.clear()
        print("\n已退出监听，等待唤醒词...")

    def _restart_assistant(self):
        """重启语音助手：执行 start.sh 或 start.bat 脚本"""
        # 幂等保护：回声 / 重复识别可能在极短时间内再次触发重启，
        # 避免拉起多个 start.sh 导致出现多个助手进程
        if getattr(self, "_restarting", False):
            print("[重启] 已在重启流程中，忽略重复的重启指令")
            return
        self._restarting = True

        print("\n[重启] 检测到重启指令，正在重启语音助手...")

        self._interrupt_openclaw_silent()
        self.is_awake = False
        self.continuous_mode = False
        self._verified_speaker_name = None
        self._conv_audio_buffer.clear()
        self._clear_queue()
        self.stop_event.set()

        import subprocess
        import platform
        import os
        from pathlib import Path

        project_dir = Path(__file__).parent.parent
        is_windows = platform.system() == "Windows"

        if is_windows:
            script_path = project_dir / "scripts" / "start.bat"
        else:
            script_path = project_dir / "scripts" / "start.sh"

        if not script_path.exists():
            print(f"[重启] 错误: 找不到启动脚本 {script_path}")
            return

        print(f"[重启] 执行脚本: {script_path}")

        try:
            if is_windows:
                subprocess.Popen(
                    ["cmd", "/c", "start", "/b", str(script_path)],
                    cwd=str(project_dir),
                    creationflags=subprocess.CREATE_NEW_PROCESS_GROUP
                    | subprocess.DETACHED_PROCESS,
                )
            else:
                subprocess.Popen(
                    ["bash", str(script_path)],
                    cwd=str(project_dir),
                    start_new_session=True,
                )
            print("[重启] 重启进程已启动，当前实例退出。")
            time.sleep(0.3)
            os._exit(0)
        except Exception as e:
            print(f"[重启] 执行重启脚本失败: {e}")


def _enforce_single_instance():
    """启动时确保只有一个实例：杀掉 PID 文件中记录的其它存活实例。

    重启竞态下可能并发拉起多个 main.py，此处兜底收敛到单个进程。
    """
    try:
        if not os.path.exists(PID_FILE):
            return
        with open(PID_FILE, encoding="utf-8") as f:
            content = f.read().strip()
        old_pid = int(content) if content else 0
    except (ValueError, OSError):
        return

    if old_pid <= 0 or old_pid == os.getpid():
        return

    try:
        os.kill(old_pid, 0)  # 探测是否存活，不存在会抛 OSError
    except OSError:
        return  # 旧进程已不存在

    print(f"[单例] 检测到已有助手实例 PID={old_pid}，正在终止以避免重复进程...")
    try:
        os.kill(old_pid, signal.SIGKILL)
    except OSError as e:
        print(f"[单例] 终止旧实例失败: {e}")
        return

    # 等待旧实例退出（最多 ~2 秒）
    for _ in range(20):
        try:
            os.kill(old_pid, 0)
            time.sleep(0.1)
        except OSError:
            break


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

    # 关键词检测模型参数（sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20，中英双语）
    parser.add_argument(
        "--kws-tokens",
        type=str,
        default="models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/tokens.txt",
    )
    parser.add_argument(
        "--kws-encoder",
        type=str,
        default="models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/encoder-epoch-13-avg-2-chunk-16-left-64.onnx",
    )
    parser.add_argument(
        "--kws-decoder",
        type=str,
        default="models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/decoder-epoch-13-avg-2-chunk-16-left-64.onnx",
    )
    parser.add_argument(
        "--kws-joiner",
        type=str,
        default="models/sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20/joiner-epoch-13-avg-2-chunk-16-left-64.onnx",
    )
    parser.add_argument("--keywords-file", type=str, default="keywords/lin-meimei.txt")
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

    # SenseVoice 模型参数（离线识别）
    _project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    _sense_voice_model_dir = os.path.join(
        _project_dir,
        "models",
        "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17",
    )
    parser.add_argument(
        "--sense-voice-model",
        type=str,
        default=os.path.join(_sense_voice_model_dir, "model.int8.onnx"),
    )
    parser.add_argument(
        "--sense-voice-tokens",
        type=str,
        default=os.path.join(_sense_voice_model_dir, "tokens.txt"),
    )
    parser.add_argument(
        "--sense-voice-use-itn",
        type=int,
        default=1,
        help="是否启用反向文本规范化（标点符号）",
    )
    parser.add_argument(
        "--sense-voice-language",
        type=str,
        default="auto",
        help="语言：auto, zh, en, ko, ja, yue",
    )

    # Qwen3-ASR 模型参数（离线识别）
    _qwen3_model_dir = os.path.join(
        _project_dir, "models", "sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25"
    )
    parser.add_argument(
        "--qwen3-conv-frontend",
        type=str,
        default=os.path.join(_qwen3_model_dir, "conv_frontend.onnx"),
    )
    parser.add_argument(
        "--qwen3-encoder",
        type=str,
        default=os.path.join(_qwen3_model_dir, "encoder.int8.onnx"),
    )
    parser.add_argument(
        "--qwen3-decoder",
        type=str,
        default=os.path.join(_qwen3_model_dir, "decoder.int8.onnx"),
    )
    parser.add_argument(
        "--qwen3-tokenizer",
        type=str,
        default=os.path.join(_qwen3_model_dir, "tokenizer"),
    )
    parser.add_argument(
        "--vad-model",
        type=str,
        default=os.path.join(_project_dir, "models", "silero_vad.onnx"),
    )

    parser.add_argument(
        "--hotwords-file", type=str, default=os.path.join(_project_dir, "hotwords.txt")
    )
    parser.add_argument("--hotwords-score", type=float, default=1.5)

    parser.add_argument("--provider", type=str, default=_detect_best_provider())

    return parser.parse_args()


def main():
    global _assistant_instance

    setup_logging(_PROJECT_DIR)

    # 单例收敛必须在任何慢初始化（模型加载 / 打断词生成 / 桥接预检）之前完成：
    # 进程一起来就先杀掉旧实例并抢占 PID 文件，把重启竞态窗口压到最小——否则
    # 两个新进程可能同时卡在慢构造里、都读到旧(已死)PID、都判无需杀、都写 PID，
    # 双双存活（"重启出现 2 个进程"的根因）。
    _enforce_single_instance()
    with open(PID_FILE, "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))

    args = get_args()

    # 加载所有 assistant 配置
    default_cfg, all_assistants = _load_all_assistant_configs()
    print(f"[配置] 激活 assistant: {default_cfg['name']} ({default_cfg['id']})")

    # 使用 global.txt 作为唤醒词文件（由 start.sh 脚本合并生成）
    args.keywords_file = os.path.join(_PROJECT_DIR, "keywords", "global.txt")

    # 构建 keyword_to_assistant_id 映射（从所有 assistant 配置中读取）
    keyword_mapping = {}
    for assistant in all_assistants:
        assistant_id = assistant["id"]
        keywords_file = assistant.get("keywords_file")
        if keywords_file:
            full_path = os.path.join(_PROJECT_DIR, keywords_file)
            if os.path.exists(full_path):
                with open(full_path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        if "@" in line:
                            keyword_text = line.split("@")[-1].strip()
                            keyword_mapping[keyword_text] = assistant_id
                print(f"[配置] 加载 {assistant['name']} ({assistant_id}) 的唤醒词映射")

    print(f"[配置] 使用唤醒词文件: {args.keywords_file}")
    print(f"[配置] 唤醒词映射: {keyword_mapping}")

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

    assistant = VoiceAssistant(args, default_cfg, all_assistants, keyword_mapping)
    _assistant_instance = assistant

    api_thread = threading.Thread(target=_start_api_server, daemon=True)
    api_thread.start()
    print(f"API server started on port {API_PORT}")

    # 单例收敛 + PID 抢占已在 main() 顶部完成（慢构造之前），此处不再重复。

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
