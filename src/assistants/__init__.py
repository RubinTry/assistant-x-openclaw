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
    "get_feedback",
    "get_tts",
    "get_visual_effects",
    "AssistantInstance",
    "AssistantManager",
]

logger = logging.getLogger(__name__)


class AssistantInstance:
    """封装单个 assistant 的所有组件"""
    
    def __init__(self, assistant_id: str, config: dict, 
                 sound_enabled: bool = True, 
                 hud_enabled: bool = True, 
                 notification_enabled: bool = True):
        self.id = assistant_id
        self.config = config
        self.name = config.get("name", assistant_id)
        
        # 创建组件实例
        self.feedback = self._create_feedback(sound_enabled, hud_enabled, notification_enabled)
        self.visual = self._create_visual(hud_enabled)
        self.tts = self._create_tts()
        
    def _create_feedback(self, sound_enabled: bool, hud_enabled: bool, notification_enabled: bool):
        """创建反馈组件"""
        if self.id == "jarvis":
            from assistants.jarvis.feedback import JarvisFeedback
            return JarvisFeedback(sound_enabled, hud_enabled, notification_enabled)
        elif self.id == "lin-meimei":
            from assistants.lin_meimei.feedback import LinMeimeiFeedback
            return LinMeimeiFeedback(sound_enabled, hud_enabled, notification_enabled)
        else:
            logger.warning(f"未知 Assistant 反馈: {self.id}，使用空实现")
            return NullAssistantFeedback()
    
    def _create_visual(self, enabled: bool):
        """创建视觉组件"""
        if not enabled:
            return NullAssistantVisual()
        
        if self.id == "jarvis":
            from assistants.jarvis.visual import JarvisVisual
            visual = JarvisVisual()
            visual.start()
            return visual
        elif self.id == "lin-meimei":
            from assistants.lin_meimei.visual import LinMeimeiVisual
            visual = LinMeimeiVisual()
            visual.start()
            return visual
        else:
            logger.warning(f"未知 Assistant 特效: {self.id}，使用空实现")
            return NullAssistantVisual()
    
    def _create_tts(self):
        """创建 TTS 组件"""
        if self.id == "jarvis":
            from assistants.jarvis.tts import JarvisTTS
            return JarvisTTS()
        elif self.id == "lin-meimei":
            from assistants.lin_meimei.tts import LinMeimeiTTS
            return LinMeimeiTTS()
        else:
            logger.warning(f"未知 Assistant TTS: {self.id}，使用空实现")
            return NullAssistantTTS()
    
    def stop(self):
        """停止并清理资源"""
        if self.visual:
            self.visual.stop()


class AssistantManager:
    """管理多个 assistant 实例"""
    
    def __init__(self):
        self._assistants: Dict[str, AssistantInstance] = {}
        self._current: Optional[AssistantInstance] = None
        self._lock = threading.Lock()
    
    def register(self, assistant_id: str, config: dict,
                 sound_enabled: bool = True,
                 hud_enabled: bool = True,
                 notification_enabled: bool = True):
        """注册一个 assistant"""
        with self._lock:
            if assistant_id in self._assistants:
                # 如果已存在，先停止旧的
                self._assistants[assistant_id].stop()
            
            instance = AssistantInstance(
                assistant_id, config,
                sound_enabled, hud_enabled, notification_enabled
            )
            self._assistants[assistant_id] = instance
            logger.info(f"Registered assistant: {assistant_id} ({instance.name})")
    
    def get(self, assistant_id: str) -> Optional[AssistantInstance]:
        """获取指定 assistant 实例"""
        return self._assistants.get(assistant_id)
    
    def switch_to(self, assistant_id: str) -> Optional[AssistantInstance]:
        """切换到指定 assistant"""
        with self._lock:
            if assistant_id not in self._assistants:
                logger.error(f"Assistant not found: {assistant_id}")
                return None
            
            self._current = self._assistants[assistant_id]
            logger.info(f"Switched to assistant: {assistant_id} ({self._current.name})")
            return self._current
    
    @property
    def current(self) -> Optional[AssistantInstance]:
        """获取当前激活的 assistant"""
        return self._current
    
    def get_all_enabled(self) -> Dict[str, AssistantInstance]:
        """获取所有已启用的 assistant"""
        return dict(self._assistants)
    
    def stop_all(self):
        """停止所有 assistant"""
        with self._lock:
            for instance in self._assistants.values():
                instance.stop()
            self._assistants.clear()
            self._current = None


# 全局 Manager 实例
_manager = AssistantManager()


def get_manager() -> AssistantManager:
    """获取全局 AssistantManager"""
    return _manager


# ── 以下保持向后兼容 ─────────────────────────────────────────

# 兼容旧代码的单例模式变量
_feedback_instance: Optional[AssistantFeedback] = None
_visual_instance: Optional[AssistantVisual] = None
_visual_lock = threading.Lock()
_tts_instance: Optional[AssistantTTS] = None


def get_feedback(
    sound_enabled: bool = True,
    hud_enabled: bool = True,
    notification_enabled: bool = True,
    assistant: str = "lin-meimei",
) -> AssistantFeedback:
    """根据 assistant ID 获取对应的反馈实例（单例）- 兼容旧代码"""
    global _feedback_instance
    if _feedback_instance is None:
        if assistant == "jarvis":
            from assistants.jarvis.feedback import JarvisFeedback
            _feedback_instance = JarvisFeedback(sound_enabled, hud_enabled, notification_enabled)
        elif assistant == "lin-meimei":
            from assistants.lin_meimei.feedback import LinMeimeiFeedback
            _feedback_instance = LinMeimeiFeedback(sound_enabled, hud_enabled, notification_enabled)
        else:
            logger.warning(f"未知 Assistant 反馈: {assistant}，使用空实现")
            _feedback_instance = NullAssistantFeedback()
    return _feedback_instance


def get_visual_effects(enabled: bool = True, assistant: str = "lin-meimei") -> AssistantVisual:
    """根据 assistant ID 获取对应的视觉特效实例（单例）- 兼容旧代码"""
    global _visual_instance
    with _visual_lock:
        if not enabled:
            if _visual_instance:
                _visual_instance.stop()
                _visual_instance = None
            return NullAssistantVisual()

        if _visual_instance is None:
            if assistant == "jarvis":
                from assistants.jarvis.visual import JarvisVisual
                _visual_instance = JarvisVisual()
            elif assistant == "lin-meimei":
                from assistants.lin_meimei.visual import LinMeimeiVisual
                _visual_instance = LinMeimeiVisual()
            else:
                logger.warning(f"未知 Assistant 特效: {assistant}，使用空实现")
                return NullAssistantVisual()
            _visual_instance.start()
        return _visual_instance


def get_tts(assistant: str = "lin-meimei") -> AssistantTTS:
    """根据 assistant ID 获取对应的 TTS 实例（单例）- 兼容旧代码"""
    global _tts_instance
    if _tts_instance is None:
        if assistant == "jarvis":
            from assistants.jarvis.tts import JarvisTTS
            _tts_instance = JarvisTTS()
        elif assistant == "lin-meimei":
            from assistants.lin_meimei.tts import LinMeimeiTTS
            _tts_instance = LinMeimeiTTS()
        else:
            logger.warning(f"未知 Assistant TTS: {assistant}，使用空实现")
            _tts_instance = NullAssistantTTS()
    return _tts_instance
