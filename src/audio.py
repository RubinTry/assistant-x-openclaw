import os
import platform
import subprocess
import sys

_is_windows = sys.platform.startswith("win") or platform.system() == "Windows"
_is_macos = platform.system() == "Darwin"


def play_audio_file(file_path: str, volume: float = 0.5, blocking: bool = False):
    if not os.path.exists(file_path):
        return False
    try:
        if _is_windows:
            import soundfile as sf
            import sounddevice as sd

            data, sr = sf.read(file_path, dtype="float32")
            if data.ndim > 1:
                data = data[:, 0]
            sd.play(data * volume, samplerate=sr)
            if blocking:
                sd.wait()
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
