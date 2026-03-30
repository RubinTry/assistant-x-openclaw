import json
import os
import logging
import re
from typing import Dict, Any, Optional, List
from pathlib import Path

# 尝试导入python-dotenv，如果没有安装则跳过
try:
    from dotenv import load_dotenv
    DOTENV_AVAILABLE = True
except ImportError:
    DOTENV_AVAILABLE = False

class ModelManager:
    """大模型管理器，负责加载和管理不同的大模型配置"""
    
    def __init__(self, config_path: str = "app/big_models.json"):
        self.config_path = config_path
        
        # 先初始化logger
        self.logger = logging.getLogger(__name__)
        
        # 加载环境变量
        if DOTENV_AVAILABLE:
            env_path = os.path.join(os.path.dirname(config_path) or ".", '.env')
            if os.path.exists(env_path):
                load_dotenv(env_path)
        
        self.config = self._load_config()
        
    def _resolve_env_vars(self, value: str) -> str:
        """解析环境变量，支持 ${VAR_NAME} 格式"""
        if not isinstance(value, str):
            return value
            
        # 匹配 ${VAR_NAME} 格式的环境变量
        pattern = r'\$\{([^}]+)\}'
        
        def replace_env_var(match):
            var_name = match.group(1)
            env_value = os.getenv(var_name)
            if env_value is None:
                self.logger.warning(f"环境变量 {var_name} 未设置，保持原值")
                return match.group(0)  # 返回原始字符串
            return env_value
        
        return re.sub(pattern, replace_env_var, value)
    
    def _process_config_values(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """递归处理配置中的环境变量"""
        if isinstance(config, dict):
            return {key: self._process_config_values(value) for key, value in config.items()}
        elif isinstance(config, list):
            return [self._process_config_values(item) for item in config]
        elif isinstance(config, str):
            return self._resolve_env_vars(config)
        else:
            return config
        
    def _load_config(self) -> Dict[str, Any]:
        """加载大模型配置文件"""
        try:
            config_file = Path(self.config_path)
            if not config_file.exists():
                self.logger.error(f"配置文件不存在: {self.config_path}")
                return self._get_default_config()
                
            with open(config_file, 'r', encoding='utf-8') as f:
                config = json.load(f)
                
            # 验证配置格式
            if not self._validate_config(config):
                self.logger.error("配置文件格式无效，使用默认配置")
                return self._get_default_config()
            
            # 处理环境变量
            config = self._process_config_values(config)
            
            return config
            
        except Exception as e:
            self.logger.error(f"加载配置文件失败: {e}")
            return self._get_default_config()
    
    def _validate_config(self, config: Dict[str, Any]) -> bool:
        """验证配置文件格式"""
        required_keys = ['models', 'default_model', 'global_settings']
        return all(key in config for key in required_keys)
    
    def _get_default_config(self) -> Dict[str, Any]:
        """获取默认配置"""
        return {
            "models": {
                "lm_studio": {
                    "name": "LM Studio",
                    "base_url": "http://localhost:1234",
                    "api_key": "lm-studio",
                    "model_name": "gpt-oss-20b",
                    "enabled": True,
                    "timeout": 30,
                    "retry_attempts": 3,
                    "retry_delay": 0.5,
                    "parameters": {
                        "temperature": 0.7,
                        "max_tokens": 1000
                    }
                }
            },
            "default_model": "lm_studio",
            "fallback_models": ["lm_studio"],
            "global_settings": {
                "max_memory": 50,
                "connection_timeout": 10,
                "request_timeout": 30,
                "enable_streaming": True,
                "enable_tools": True,
                "log_level": "INFO"
            }
        }
    
    def get_model_config(self, model_id: str = None) -> Optional[Dict[str, Any]]:
        """获取指定模型的配置"""
        if model_id is None:
            model_id = self.config.get('default_model', 'lm_studio')
            
        models = self.config.get('models', {})
        model_config = models.get(model_id)
        
        if not model_config:
            self.logger.error(f"未找到模型配置: {model_id}")
            return None
            
        if not model_config.get('enabled', False):
            self.logger.warning(f"模型未启用: {model_id}")
            return None
            
        return model_config.copy()  # 返回副本避免意外修改
    
    def get_available_models(self) -> List[str]:
        """获取所有可用的模型ID列表"""
        models = self.config.get('models', {})
        return [model_id for model_id, config in models.items() 
                if config.get('enabled', False)]
    
    def get_fallback_models(self) -> List[str]:
        """获取备用模型列表"""
        fallback_models = self.config.get('fallback_models', [])
        available_models = self.get_available_models()
        return [model for model in fallback_models if model in available_models]
    
    def get_global_settings(self) -> Dict[str, Any]:
        """获取全局设置"""
        return self.config.get('global_settings', {})
    
    def update_model_config(self, model_id: str, updates: Dict[str, Any]) -> bool:
        """更新模型配置"""
        try:
            if model_id not in self.config.get('models', {}):
                self.logger.error(f"模型不存在: {model_id}")
                return False
                
            # 更新配置
            model_config = self.config['models'][model_id]
            model_config.update(updates)
            
            # 保存到文件
            return self._save_config()
            
        except Exception as e:
            self.logger.error(f"更新模型配置失败: {e}")
            return False
    
    def enable_model(self, model_id: str) -> bool:
        """启用模型"""
        return self.update_model_config(model_id, {'enabled': True})
    
    def disable_model(self, model_id: str) -> bool:
        """禁用模型"""
        return self.update_model_config(model_id, {'enabled': False})
    
    def set_default_model(self, model_id: str) -> bool:
        """设置默认模型"""
        try:
            if model_id not in self.config.get('models', {}):
                self.logger.error(f"模型不存在: {model_id}")
                return False
                
            self.config['default_model'] = model_id
            return self._save_config()
            
        except Exception as e:
            self.logger.error(f"设置默认模型失败: {e}")
            return False
    
    def _save_config(self) -> bool:
        """保存配置到文件"""
        try:
            with open(self.config_path, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=4, ensure_ascii=False)
            return True
            
        except Exception as e:
            self.logger.error(f"保存配置文件失败: {e}")
            return False
    
    def reload_config(self) -> bool:
        """重新加载配置文件"""
        try:
            self.config = self._load_config()
            self.logger.info("配置文件重新加载成功")
            return True
            
        except Exception as e:
            self.logger.error(f"重新加载配置文件失败: {e}")
            return False
    
    def add_model(self, model_id: str, config: Dict[str, Any]) -> bool:
        """添加新模型配置"""
        try:
            if model_id in self.config.get('models', {}):
                self.logger.error(f"模型ID已存在: {model_id}")
                return False
            
            # 确保配置包含必需字段
            required_fields = ['name', 'base_url', 'api_key', 'model_name']
            for field in required_fields:
                if field not in config:
                    self.logger.error(f"缺少必需字段: {field}")
                    return False
            
            # 设置默认值
            default_config = {
                "enabled": True,
                "timeout": 30,
                "retry_attempts": 3,
                "retry_delay": 0.5,
                "parameters": {
                    "temperature": 0.7,
                    "max_tokens": 1000,
                    "top_p": 1.0,
                    "frequency_penalty": 0.0,
                    "presence_penalty": 0.0
                }
            }
            
            # 合并配置
            final_config = {**default_config, **config}
            
            # 添加到配置
            self.config['models'][model_id] = final_config
            
            return self._save_config()
            
        except Exception as e:
            self.logger.error(f"添加模型失败: {e}")
            return False