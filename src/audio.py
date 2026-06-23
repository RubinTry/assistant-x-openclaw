import os
import platform
import subprocess
import sys
import time

_is_windows = sys.platform.startswith("win") or platform.system() == "Windows"
_is_macos = platform.system() == "Darwin"

# 输出设备原生采样率缓存。TTS 模型多为 22050Hz，而声卡常工作在 44100/48000Hz，
# 直接以 22050Hz 调用 sd.play 会让 PortAudio/CoreAudio 实时变采样，在部分机器上
# 产生明显的电流杂音/咝咝声。播放前先用 soxr 高质量重采样到设备原生采样率，
# 让 PortAudio 打开一个采样率匹配的流，从根源上消除这种杂音。
_output_sr = None


def _device_output_samplerate() -> int:
    """查询并缓存默认输出设备的原生采样率，失败返回 0。"""
    global _output_sr
    if _output_sr is None:
        try:
            import sounddevice as sd

            info = sd.query_devices(kind="output")
            _output_sr = int(info["default_samplerate"])
        except Exception:
            _output_sr = 0
    return _output_sr


def play_array(audio, sr, volume: float = 1.0, blocking: bool = True, stop_check=None):
    """播放 float32 音频数组（统一播放出口）。

    1. 先重采样到输出设备原生采样率，避免实时变采样引入电流杂音；
    2. 增益后做硬限幅兜底，杜绝越界削波；
    3. blocking 且提供 stop_check（可调用，返回 True 表示请求打断）时，可中断等待。
    """
    import numpy as np
    import sounddevice as sd

    if audio is None or len(audio) == 0:
        return False

    audio = np.ascontiguousarray(audio, dtype=np.float32)

    dev_sr = _device_output_samplerate()
    if dev_sr and dev_sr != sr:
        try:
            import soxr

            audio = soxr.resample(audio, sr, dev_sr).astype(np.float32)
            sr = dev_sr
        except Exception:
            pass  # 没装 soxr 时退回原采样率播放

    if volume != 1.0:
        audio = audio * np.float32(volume)
    np.clip(audio, -1.0, 1.0, out=audio)  # 兜底防削波

    sd.play(audio, samplerate=sr)
    if blocking:
        if stop_check is None:
            sd.wait()
        else:
            deadline = time.time() + len(audio) / float(sr) + 0.1
            while time.time() < deadline:
                if stop_check():
                    sd.stop()
                    break
                time.sleep(0.05)
    return True


def play_audio_file(file_path: str, volume: float = 0.5, blocking: bool = False):
    if not os.path.exists(file_path):
        return False
    try:
        if _is_windows:
            import soundfile as sf

            data, sr = sf.read(file_path, dtype="float32")
            if data.ndim > 1:
                data = data[:, 0]
            play_array(data, sr, volume=volume, blocking=blocking)
        elif _is_macos:
            cmd = ["afplay", "-v", str(volume), file_path]
            if blocking:
                subprocess.run(cmd, check=True, capture_output=True, timeout=10)
            else:
                subprocess.Popen(cmd)
        else:
            for player in ["aplay", "paplay", "ffplay"]:
                try:
                    subprocess.run(
                        [player, file_path], check=True, capture_output=True, timeout=10
                    )
                    break
                except (FileNotFoundError, subprocess.CalledProcessError):
                    continue
        return True
    except Exception:
        return False


def stop_audio():
    try:
        if _is_windows:
            import sounddevice as sd

            sd.stop()
        elif _is_macos:
            subprocess.run(["pkill", "-f", "afplay"], capture_output=True)
        else:
            for player in ["pkill", "killall"]:
                try:
                    subprocess.run([player, "-f", "aplay"], capture_output=True)
                    subprocess.run([player, "-f", "paplay"], capture_output=True)
                    break
                except FileNotFoundError:
                    pass
    except Exception:
        pass
