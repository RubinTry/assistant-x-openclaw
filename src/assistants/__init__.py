import importlib
import logging
import threading
from typing import Optional, Dict

from assistants.feedback import AssistantFeedback, NullAssistantFeedback
from assistants.tts import AssistantTTS, NullAssistantTTS
from assistants.visual import AssistantVisual, NullAssistantVisual

__all__ = [
    "AssistantFeedback",
    "NullAssistantFeedback",
    "AssistantTTS",
    "NullAssistantTTS",
    "AssistantVisual",
    "NullAssistantVisual",
    "AssistantInstance",
    "AssistantManager",
    "get_manager",
]

logger = logging.getLogger(__name__)

_LEGACY_MAP = {
    "jarvis": {
        "feedback": "jarvis",
        "visual": "jarvis",
        "tts": "jarvis",
    },
    "lin-meimei": {
        "feedback": "custom",
        "visual": "custom",
        "tts": "custom",
    },
}

_LEGACY_CONFIGS = {
    "lin-meimei": {
        "feedback_config": {
            "sounds": {
                "processing": "processing_linmeimei.wav",
                "waiting": "processing_linmeimei.wav",
            },
            "notification_prefix": "林妹妹",
            "hud": {
                "init": [
                    "～～～～～～～～～～～～～～～～～～～～",
                    "　　　　🌸 林妹妹驾到 🌸",
                    "～～～～～～～～～～～～～～～～～～～～",
                ],
                "exit": ["妹妹歇着了...", "有事再唤妹妹..."],
                "error": ["哎呀，出岔子了...", "这可不妙..."],
                "thinking": ["容妹妹想想...", "且慢，让我琢磨琢磨..."],
                "waiting": ["妹妹在听呢...", "哥哥请讲..."],
            },
        },
        "visual_config": {"agent_id": "lin-meimei"},
        "tts_config": {
            "engine": "vits",
            "model_dir": "models/vits-melo-tts-zh_en",
            "speed": 0.85,
        },
    },
}


def _resolve_class(dotted_path: str):
    module_path, class_name = dotted_path.rsplit(":", 1)
    module = importlib.import_module(module_path)
    return getattr(module, class_name)


class AssistantInstance:
    def __init__(
        self,
        assistant_id: str,
        config: dict,
        sound_enabled: bool = True,
        hud_enabled: bool = True,
        notification_enabled: bool = True,
    ):
        self.id = assistant_id
        self.config = config
        self.name = config.get("name", assistant_id)

        self.feedback = self._create_feedback(
            sound_enabled, hud_enabled, notification_enabled
        )
        self.visual = self._create_visual(hud_enabled)
        self.tts = self._create_tts()

    def _get_component_spec(self, component: str) -> str | None:
        components = self.config.get("components", {})
        spec = components.get(component)
        if spec:
            return spec
        legacy = _LEGACY_MAP.get(self.id, {}).get(component)
        if legacy:
            return legacy
        return None

    def _get_sub_config(self, component: str) -> dict:
        config_key = f"{component}_config"
        sub = self.config.get(config_key)
        if sub:
            return sub
        legacy_cfg = _LEGACY_CONFIGS.get(self.id, {})
        return legacy_cfg.get(config_key, {})

    def _create_feedback(
        self, sound_enabled: bool, hud_enabled: bool, notification_enabled: bool
    ):
        spec = self._get_component_spec("feedback")

        if spec == "jarvis":
            from assistants.jarvis.feedback import JarvisFeedback

            return JarvisFeedback(sound_enabled, hud_enabled, notification_enabled)

        if spec == "custom":
            from assistants.custom_feedback import ConfigurableFeedback

            cfg = self._get_sub_config("feedback")
            return ConfigurableFeedback(
                cfg, sound_enabled, hud_enabled, notification_enabled
            )

        if spec and ":" in spec:
            try:
                cls = _resolve_class(spec)
                return cls(sound_enabled, hud_enabled, notification_enabled)
            except Exception as e:
                logger.error(f"加载 feedback 组件失败 [{spec}]: {e}")

        logger.warning(f"未知 Assistant 反馈: {self.id} (spec={spec})，使用空实现")
        return NullAssistantFeedback()

    def _create_visual(self, enabled: bool):
        if not enabled:
            return NullAssistantVisual()

        spec = self._get_component_spec("visual")

        if spec == "jarvis":
            from assistants.jarvis.visual import JarvisVisual

            visual = JarvisVisual(
                effect_name=self.config.get("visualEffect", "Particle")
            )
            visual.start()
            return visual

        if spec == "custom":
            from assistants.custom_visual import ConfigurableVisual

            cfg = self._get_sub_config("visual")
            visual = ConfigurableVisual(cfg)
            visual.start()
            return visual

        if spec and ":" in spec:
            try:
                cls = _resolve_class(spec)
                visual = cls()
                visual.start()
                return visual
            except Exception as e:
                logger.error(f"加载 visual 组件失败 [{spec}]: {e}")

        logger.warning(f"未知 Assistant 特效: {self.id} (spec={spec})，使用空实现")
        return NullAssistantVisual()

    def _tts_config(self, spec: str) -> dict:
        """取 tts_configs.<spec>，无则退到 tts_config。"""
        per_engine = (self.config.get("tts_configs") or {}).get(spec)
        return per_engine if per_engine is not None else self._get_sub_config("tts")

    def _create_tts(self):
        spec = self._get_component_spec("tts")

        if spec == "jarvis":
            from assistants.jarvis.tts import JarvisTTS

            return JarvisTTS(self._tts_config(spec))

        if spec == "custom":
            from assistants.custom_tts import CustomTTS

            return CustomTTS(self._tts_config(spec))

        if spec == "macos_say":
            from assistants.macos_say_tts import MacosSayTTS

            return MacosSayTTS(self._tts_config(spec))

        if spec == "jarvis_v2_onnx":
            from assistants.jarvis.tts import JarvisV2OnnxTTS

            return JarvisV2OnnxTTS(self._tts_config(spec))

        # 零样本克隆说话人：由 tts_configs.<spec>.engine 指定
        tts_cfg = self._tts_config(spec)
        if tts_cfg.get("engine") == "zipvoice":
            from assistants.jarvis.tts import ZipVoiceTTS

            return ZipVoiceTTS(tts_cfg)

        if spec and ":" in spec:
            try:
                cls = _resolve_class(spec)
                return cls()
            except Exception as e:
                logger.error(f"加载 TTS 组件失败 [{spec}]: {e}")

        logger.warning(f"未知 Assistant TTS: {self.id} (spec={spec})，使用空实现")
        return NullAssistantTTS()

    def stop(self):
        if self.visual:
            self.visual.stop()


class AssistantManager:
    def __init__(self):
        self._assistants: Dict[str, AssistantInstance] = {}
        self._current: Optional[AssistantInstance] = None
        self._lock = threading.Lock()

    def register(
        self,
        assistant_id: str,
        config: dict,
        sound_enabled: bool = True,
        hud_enabled: bool = True,
        notification_enabled: bool = True,
    ):
        with self._lock:
            if assistant_id in self._assistants:
                self._assistants[assistant_id].stop()

            instance = AssistantInstance(
                assistant_id, config, sound_enabled, hud_enabled, notification_enabled
            )
            self._assistants[assistant_id] = instance
            logger.info(f"Registered assistant: {assistant_id} ({instance.name})")

    def get(self, assistant_id: str) -> Optional[AssistantInstance]:
        return self._assistants.get(assistant_id)

    def switch_to(self, assistant_id: str) -> Optional[AssistantInstance]:
        with self._lock:
            if assistant_id not in self._assistants:
                logger.error(f"Assistant not found: {assistant_id}")
                return None

            self._current = self._assistants[assistant_id]
            logger.info(f"Switched to assistant: {assistant_id} ({self._current.name})")
            return self._current

    @property
    def current(self) -> Optional[AssistantInstance]:
        return self._current

    def get_all_enabled(self) -> Dict[str, AssistantInstance]:
        return dict(self._assistants)

    def stop_all(self):
        with self._lock:
            for instance in self._assistants.values():
                instance.stop()
            self._assistants.clear()
            self._current = None


_manager = AssistantManager()


def get_manager() -> AssistantManager:
    return _manager
