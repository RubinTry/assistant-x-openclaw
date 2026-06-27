#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
摄像头抓帧（macOS / avfoundation）

用途：按需抓一张摄像头静帧，经本机 HTTP API(/camera/snapshot) 提供给 Hermes，
再交给 vision_analyze 等做画面理解（“用摄像头看看我”）。

实现：复用仓库已自带的 pip 包 **imageio-ffmpeg** 的静态 ffmpeg 二进制——它编进了
avfoundation 输入设备，跨架构、免系统安装、免 PATH。优先用它，缺失再回退系统 ffmpeg。

设计原则（与 media_pause / dock_control 一致）：**软失败**。
  - 非 macOS / ffmpeg 不可用 / 摄像头未授权导致卡死 → 超时返回 None，绝不崩、不挂住调用方。
  - avfoundation 首帧常偏暗（曝光未收敛），用 select 丢弃前若干帧再取稳定帧。

⚠️ 权限：抓帧进程的摄像头 TCC 授权归「拉起它的 App」（本项目里是**控制中心**）。
  控制中心 Info.plist 需带 `NSCameraUsageDescription`，首次抓帧会弹授权窗，点允许后永久生效。
  默认分辨率 1920x1080@30 取自本机 FaceTime 摄像头支持的模式；换机器可经构造参数调整。
"""

import logging
import os
import platform
import shutil
import subprocess
import threading

logger = logging.getLogger(__name__)


class CameraController:
    def __init__(self, device_index=0, warmup_frames=8, capture_timeout=8.0,
                 video_size="1920x1080", framerate=30):
        self.device_index = device_index
        self.warmup_frames = warmup_frames
        self.capture_timeout = capture_timeout
        self.video_size = video_size
        self.framerate = framerate
        self._lock = threading.Lock()
        self._ffmpeg = self._find_ffmpeg()
        self._available = self._ffmpeg is not None and platform.system() == "Darwin"

        if self._available:
            print(f"[摄像头] ffmpeg 可用，按需抓帧已就绪: {self._ffmpeg}")
        elif platform.system() != "Darwin":
            logger.info("[摄像头] 非 macOS，摄像头抓帧不启用")
        else:
            print("[摄像头] 未找到 ffmpeg，摄像头抓帧降级为关闭（软失败）")

    def _find_ffmpeg(self):
        # 主路径：pip 包 imageio-ffmpeg 自带的静态二进制（含 avfoundation）
        try:
            import imageio_ffmpeg
            return imageio_ffmpeg.get_ffmpeg_exe()
        except Exception as e:
            logger.debug("[摄像头] imageio-ffmpeg 不可用，尝试系统 ffmpeg: %s", e)
        # 兜底：系统 ffmpeg
        return shutil.which("ffmpeg")

    def is_available(self) -> bool:
        return self._available

    def capture(self, out_path: str):
        """抓一帧到 out_path（JPEG）。成功返回 out_path，失败/超时返回 None。串行、幂等。"""
        if not self._available:
            return None
        with self._lock:
            try:
                os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
            except Exception:
                pass
            # 丢弃前 warmup_frames 帧（曝光预热）后取 1 帧
            vf = f"select=gte(n\\,{self.warmup_frames})"
            cmd = [
                self._ffmpeg, "-hide_banner", "-loglevel", "error",
                "-f", "avfoundation",
                "-framerate", str(self.framerate),
                "-video_size", self.video_size,
                "-i", str(self.device_index),
                "-frames:v", "1",
                "-vf", vf,
                "-fps_mode", "passthrough",
                "-y", out_path,
            ]
            try:
                r = subprocess.run(
                    cmd, capture_output=True, text=True, timeout=self.capture_timeout
                )
            except subprocess.TimeoutExpired:
                logger.warning("[摄像头] 抓帧超时（多半是摄像头未授权或被占用）")
                return None
            except Exception as e:
                logger.warning("[摄像头] 抓帧异常: %s", e)
                return None

            if (r.returncode == 0 and os.path.exists(out_path)
                    and os.path.getsize(out_path) > 0):
                return out_path
            logger.warning(
                "[摄像头] 抓帧失败: rc=%s err=%s",
                r.returncode, (r.stderr or "").strip()[:300],
            )
            return None


# ── 单例 ──────────────────────────────────────────────────
_controller = None
_controller_lock = threading.Lock()


def get_camera_controller() -> CameraController:
    global _controller
    with _controller_lock:
        if _controller is None:
            _controller = CameraController()
        return _controller
