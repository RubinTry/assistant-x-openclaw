from openai import OpenAI
from openai.types.chat import ChatCompletionToolParam
import logging
import json
import time
from typing import Optional, List, Dict, Any, Union
from collections import deque

# 处理tools模块的导入
try:
    from tools import tool_registry
except ImportError:
    # 如果直接导入失败，尝试从app目录导入
    import sys
    import os
    sys.path.append(os.path.dirname(__file__))
    from tools import tool_registry

# 导入模型管理器
try:
    from model_manager import ModelManager
except ImportError:
    # 如果直接导入失败，尝试从app目录导入
    import sys
    import os
    sys.path.append(os.path.dirname(__file__))
    from model_manager import ModelManager

class AIAssistant:
    def __init__(self, model_id: str = None, config_path: str = "./big_models.json"):
        """
        初始化AI助手
        
        Args:
            model_id: 模型ID，如果为None则使用默认模型
            config_path: 配置文件路径
        """
        # 初始化模型管理器
        self.model_manager = ModelManager(config_path)
        
        # 获取全局设置
        global_settings = self.model_manager.get_global_settings()
        self.max_memory = global_settings.get('max_memory', 50)
        
        # 设置当前使用的模型
        self.current_model_id = model_id or self.model_manager.config.get('default_model', 'lm_studio')
        self.current_model_config = self.model_manager.get_model_config(self.current_model_id)
        
        if not self.current_model_config:
            # 尝试使用备用模型
            fallback_models = self.model_manager.get_fallback_models()
            if fallback_models:
                self.current_model_id = fallback_models[0]
                self.current_model_config = self.model_manager.get_model_config(self.current_model_id)
            
            if not self.current_model_config:
                raise ValueError("没有可用的模型配置")
        
        # 初始化OpenAI客户端
        self.client = self._create_client()
        
        # 使用deque来存储对话历史，自动限制长度
        self.conversation_history = deque(maxlen=self.max_memory)
        self.system_prompt = None
        
        # 设置日志级别
        log_level = global_settings.get('log_level', 'INFO')
        logging.basicConfig(level=getattr(logging, log_level))
        self.logger = logging.getLogger(__name__)
        
        # 从工具注册器获取可用的工具
        enable_tools = global_settings.get('enable_tools', True)
        if enable_tools:
            tool_schemas = tool_registry.get_tool_schemas()
            self.tools: Optional[List[ChatCompletionToolParam]] = tool_schemas if tool_schemas else None
        else:
            self.tools = None
    
    def _create_client(self) -> OpenAI:
        """创建OpenAI客户端"""
        base_url = self.current_model_config['base_url'].rstrip('/')
        api_key = self.current_model_config['api_key']
        timeout = self.current_model_config.get('timeout', None)
        
        return OpenAI(
            base_url=f"{base_url}/v1",
            api_key=api_key,
            timeout=timeout
        )
    
    def switch_model(self, model_id: str) -> bool:
        """切换到指定的模型"""
        try:
            model_config = self.model_manager.get_model_config(model_id)
            if not model_config:
                self.logger.error(f"无法切换到模型: {model_id}")
                return False
            
            self.current_model_id = model_id
            self.current_model_config = model_config
            self.client = self._create_client()
            
            self.logger.info(f"已切换到模型: {model_id}")
            return True
            
        except Exception as e:
            self.logger.error(f"切换模型失败: {e}")
            return False
    
    def get_current_model_info(self) -> Dict[str, Any]:
        """获取当前模型信息"""
        return {
            'model_id': self.current_model_id,
            'model_name': self.current_model_config.get('name', 'Unknown'),
            'base_url': self.current_model_config.get('base_url', ''),
            'model_name_api': self.current_model_config.get('model_name', '')
        }
    
    def get_available_models(self) -> List[str]:
        """获取可用模型列表"""
        return self.model_manager.get_available_models()
    
    def check_connection(self) -> bool:
        """
        检查与当前模型的连接状态
        
        Returns:
            bool: 连接是否成功
        """
        try:
            # 尝试多个备用模型
            fallback_models = self.model_manager.get_fallback_models()
            
            for model_id in [self.current_model_id] + fallback_models:
                if model_id == self.current_model_id:
                    client = self.client
                else:
                    # 创建临时客户端测试其他模型
                    temp_config = self.model_manager.get_model_config(model_id)
                    if not temp_config:
                        continue
                    
                    base_url = temp_config['base_url'].rstrip('/')
                    api_key = temp_config['api_key']
                    timeout = temp_config.get('timeout', 10)
                    
                    client = OpenAI(
                        base_url=f"{base_url}/v1",
                        api_key=api_key,
                        timeout=timeout
                    )
                
                try:
                    # 尝试连接
                    models = client.models.list()
                    
                    # 如果不是当前模型，则切换到这个可用的模型
                    if model_id != self.current_model_id:
                        self.logger.info(f"当前模型 {self.current_model_id} 不可用，切换到 {model_id}")
                        self.switch_model(model_id)
                    
                    self.logger.info(f"成功连接到模型: {model_id}")
                    return True
                    
                except Exception as e:
                    self.logger.warning(f"模型 {model_id} 连接失败: {e}")
                    continue
            
            self.logger.error("所有模型都无法连接")
            return False
            
        except Exception as e:
            self.logger.error(f"检查连接时发生错误: {e}")
            return False
    
    def get_available_models_from_server(self) -> list:
        """
        从服务器获取可用的模型列表
        
        Returns:
            list: 可用模型列表
        """
        try:
            models = self.client.models.list()
            return [model.id for model in models.data]
        except Exception as e:
            self.logger.error(f"获取服务器模型列表失败: {e}")
            return []
    
    def set_system_prompt(self, system_prompt: str):
        """
        设置系统提示词
        
        Args:
            system_prompt: 系统提示词
        """
        self.system_prompt = system_prompt
    
    def clear_conversation(self):
        """
        清空对话历史
        """
        self.conversation_history.clear()
        self.logger.info("对话历史已清空")
    
    def get_conversation_history(self) -> List[Dict[str, str]]:
        """
        获取对话历史
        
        Returns:
            List[Dict]: 对话历史列表
        """
        return list(self.conversation_history)
    
    def add_to_history(self, role: str, content: str):
        """
        添加消息到对话历史
        
        Args:
            role: 角色 (user/assistant)
            content: 消息内容
        """
        self.conversation_history.append({
            "role": role,
            "content": content
        })
    
    def execute_tool(self, tool_name: str, arguments: dict) -> str:
        """
        执行工具调用
        
        Args:
            tool_name: 工具名称
            arguments: 工具参数
            
        Returns:
            str: 工具执行结果
        """
        return tool_registry.execute_tool(tool_name, arguments)
    
    def _get_model_parameters(self, **kwargs) -> Dict[str, Any]:
        """获取模型参数，优先使用传入的参数，否则使用配置文件中的默认参数"""
        default_params = self.current_model_config.get('parameters', {})
        
        # 合并参数，传入的参数优先
        params = {}
        for key in ['temperature', 'max_tokens', 'top_p', 'frequency_penalty', 'presence_penalty']:
            if key in kwargs:
                params[key] = kwargs[key]
            elif key in default_params:
                params[key] = default_params[key]
        
        return params
    
    def _retry_request(self, request_func, max_retries: int = None, retry_delay: float = None):
        """重试请求机制"""
        if max_retries is None:
            max_retries = self.current_model_config.get('retry_attempts', 3)
        if retry_delay is None:
            retry_delay = self.current_model_config.get('retry_delay', 0.5)
        
        last_exception = None
        
        for attempt in range(max_retries + 1):
            try:
                return request_func()
            except Exception as e:
                last_exception = e
                if attempt < max_retries:
                    self.logger.warning(f"请求失败，{retry_delay}秒后重试 (尝试 {attempt + 1}/{max_retries + 1}): {e}")
                    time.sleep(retry_delay)
                    retry_delay *= 1.5  # 指数退避
                else:
                    self.logger.error(f"请求最终失败: {e}")
        
        raise last_exception
    
    def chat(self, message: str, system_prompt: str = None, use_history: bool = True, **kwargs) -> Optional[str]:
        """
        与AI进行对话（支持多轮对话和工具调用）
        
        Args:
            message: 用户消息
            system_prompt: 系统提示词（如果提供，会覆盖默认系统提示词）
            use_history: 是否使用对话历史
            **kwargs: 其他参数如temperature, max_tokens等
            
        Returns:
            str: AI的回复，如果失败返回None
        """
        try:
            # 获取模型参数
            model_params = self._get_model_parameters(**kwargs)
            
            # 构建消息列表
            messages = []
            
            # 添加系统提示词
            current_system_prompt = system_prompt or self.system_prompt
            if current_system_prompt:
                messages.append({
                    "role": "system",
                    "content": current_system_prompt
                })
            
            # 如果使用历史记录，添加对话历史
            if use_history:
                messages.extend(list(self.conversation_history))
            
            # 添加当前用户消息
            messages.append({
                "role": "user",
                "content": message
            })
            
            # 定义请求函数
            def make_request():
                # 使用OpenAI SDK发送请求，根据是否有工具来决定参数
                request_params = {
                    "model": self.current_model_config.get('model_name', 'gpt-3.5-turbo'),
                    "messages": messages,
                    "stream": False,
                    **model_params
                }
                
                if self.tools and len(self.tools) > 0:
                    request_params.update({
                        "tools": self.tools,
                        "tool_choice": "auto"
                    })
                
                return self.client.chat.completions.create(**request_params)
            
            # 使用重试机制发送请求
            response = self._retry_request(make_request)
            
            if response.choices and len(response.choices) > 0:
                choice = response.choices[0]
                message_obj = choice.message
                
                # 检查是否需要调用工具
                if message_obj.tool_calls:
                    # 将助手的工具调用消息添加到历史
                    if use_history:
                        self.add_to_history("user", message)
                        messages.append({
                            "role": "assistant",
                            "content": message_obj.content,
                            "tool_calls": [
                                {
                                    "id": tool_call.id,
                                    "type": "function",
                                    "function": {
                                        "name": tool_call.function.name,
                                        "arguments": tool_call.function.arguments
                                    }
                                } for tool_call in message_obj.tool_calls
                            ]
                        })
                    
                    # 执行工具调用
                    for tool_call in message_obj.tool_calls:
                        function_name = tool_call.function.name
                        function_args = json.loads(tool_call.function.arguments)
                        
                        self.logger.info(f"调用工具: {function_name}, 参数: {function_args}")
                        
                        # 执行工具
                        tool_result = self.execute_tool(function_name, function_args)
                        
                        # 特殊处理：如果是退出激活工具，直接返回结果
                        if function_name == "exit_activation" and tool_result.startswith("EXIT_ACTIVATION:"):
                            self.logger.info("检测到退出激活工具调用，直接返回结果")
                            return tool_result
                        
                        # 将工具结果添加到消息历史
                        messages.append({
                            "role": "tool",
                            "tool_call_id": tool_call.id,
                            "content": tool_result
                        })
                    
                    # 再次调用AI获取最终回复
                    self.logger.info("工具调用完成，正在获取AI最终回复...")
                    
                    # 检查是否还有更多工具调用需要处理
                    max_iterations = 5  # 防止无限循环
                    iteration = 0
                    
                    while iteration < max_iterations:
                        iteration += 1
                        self.logger.info(f"AI回复迭代 {iteration}")
                        
                        def make_final_request():
                            request_params = {
                                "model": self.current_model_config.get('model_name', 'gpt-3.5-turbo'),
                                "messages": messages,
                                "stream": False,
                                **model_params
                            }
                            
                            if self.tools and len(self.tools) > 0:
                                request_params.update({
                                    "tools": self.tools,
                                    "tool_choice": "auto"
                                })
                            
                            return self.client.chat.completions.create(**request_params)
                        
                        final_response = self._retry_request(make_final_request)
                        
                        if final_response.choices and len(final_response.choices) > 0:
                            final_message = final_response.choices[0].message
                            
                            # 检查是否还有更多工具调用
                            if final_message.tool_calls:
                                self.logger.info(f"检测到更多工具调用: {len(final_message.tool_calls)}")
                                
                                # 添加助手消息到历史
                                messages.append({
                                    "role": "assistant",
                                    "content": final_message.content,
                                    "tool_calls": [
                                        {
                                            "id": tool_call.id,
                                            "type": "function",
                                            "function": {
                                                "name": tool_call.function.name,
                                                "arguments": tool_call.function.arguments
                                            }
                                        } for tool_call in final_message.tool_calls
                                    ]
                                })
                                
                                # 执行新的工具调用
                                for tool_call in final_message.tool_calls:
                                    function_name = tool_call.function.name
                                    function_args = json.loads(tool_call.function.arguments)
                                    
                                    self.logger.info(f"执行额外工具: {function_name}, 参数: {function_args}")
                                    
                                    # 执行工具
                                    tool_result = self.execute_tool(function_name, function_args)
                                    
                                    # 将工具结果添加到消息历史
                                    messages.append({
                                        "role": "tool",
                                        "tool_call_id": tool_call.id,
                                        "content": tool_result
                                    })
                                
                                # 继续下一轮迭代
                                continue
                            else:
                                # 没有更多工具调用，获取最终回复
                                final_reply = final_message.content
                                if final_reply:
                                    self.logger.info(f"AI最终回复: {final_reply[:50]}...")
                                    
                                    # 将最终回复添加到历史记录
                                    if use_history:
                                        self.add_to_history("assistant", final_reply.strip())
                                    
                                    return final_reply.strip()
                                else:
                                    self.logger.warning("AI回复为空，继续尝试...")
                                    continue
                        else:
                            self.logger.error("获取AI回复失败，响应格式错误")
                            break
                    
                    # 如果达到最大迭代次数或出现错误
                    self.logger.warning(f"工具调用处理完成，但可能未获得满意的回复（迭代次数: {iteration}）")
                    return "我已经处理了您的请求，但可能需要更多信息才能给出完整回复。"
                
                else:
                    # 普通回复，无需工具调用
                    reply = message_obj.content
                    self.logger.info(f"AI回复: {reply[:50]}...")
                    
                    # 将用户消息和AI回复添加到历史记录
                    if use_history:
                        self.add_to_history("user", message)
                        self.add_to_history("assistant", reply.strip())
                    
                    return reply.strip()
            else:
                self.logger.error("响应格式错误，未找到choices")
                return None
                
        except Exception as e:
            self.logger.error(f"请求异常: {e}")
            return None
    
    def chat_stream(self, message: str, system_prompt: str = None, use_history: bool = True, **kwargs):
        """
        流式对话，逐步返回AI回复（支持多轮对话）
        
        Args:
            message: 用户消息
            system_prompt: 系统提示词
            use_history: 是否使用对话历史
            **kwargs: 其他参数如temperature, max_tokens等
            
        Yields:
            str: AI回复的片段
        """
        try:
            # 获取模型参数
            model_params = self._get_model_parameters(**kwargs)
            
            # 构建消息列表
            messages = []
            
            # 添加系统提示词
            current_system_prompt = system_prompt or self.system_prompt
            if current_system_prompt:
                messages.append({
                    "role": "system",
                    "content": current_system_prompt
                })
            
            # 如果使用历史记录，添加对话历史
            if use_history:
                messages.extend(list(self.conversation_history))
            
            # 添加当前用户消息
            messages.append({
                "role": "user",
                "content": message
            })
            
            # 定义流式请求函数
            def make_stream_request():
                return self.client.chat.completions.create(
                    model=self.current_model_config.get('model_name', 'gpt-3.5-turbo'),
                    messages=messages,
                    stream=True,
                    **model_params
                )
            
            # 使用重试机制发送流式请求
            stream = self._retry_request(make_stream_request)
            
            full_response = ""
            for chunk in stream:
                if chunk.choices and len(chunk.choices) > 0:
                    delta = chunk.choices[0].delta
                    if delta.content:
                        content = delta.content
                        full_response += content
                        yield content
            
            # 将完整的对话添加到历史记录
            if use_history and full_response:
                self.add_to_history("user", message)
                self.add_to_history("assistant", full_response.strip())
                
        except Exception as e:
            self.logger.error(f"流式请求异常: {e}")


# 使用示例
if __name__ == "__main__":
    # 创建AI助手实例
    assistant = AIAssistant()
    
    # 检查连接
    if assistant.check_connection():
        print("连接成功！")
        
        # 获取当前模型信息
        model_info = assistant.get_current_model_info()
        print(f"当前模型: {model_info}")
        
        # 获取可用模型
        available_models = assistant.get_available_models()
        print(f"可用模型: {available_models}")
        
        # 设置系统提示词
        system_prompt = "你是一个友善的AI助手，请用简洁明了的中文回答用户的问题。你能记住我们之前的对话内容，并且可以调用工具获取实时信息。"
        assistant.set_system_prompt(system_prompt)
        
        print("\n=== 多轮对话助手（支持工具调用和模型切换）===")
        print("支持功能:")
        print("- 输入消息进行对话")
        print("- 询问时间（如：现在几点了？）")
        print("- 输入 'switch <model_id>' 切换模型")
        print("- 输入 'models' 查看可用模型")
        print("- 输入 'info' 查看当前模型信息")
        print("- 输入 'clear' 清空对话历史")
        print("- 输入 'history' 查看对话历史")
        print("- 输入 'count' 查看当前记忆的消息数量")
        print("- 输入 'quit' 退出程序")
        print("=" * 40)
        
        while True:
            user_input = input("\n请输入您的问题: ").strip()
            
            if user_input.lower() == 'quit':
                print("再见！")
                break
            elif user_input.lower() == 'clear':
                assistant.clear_conversation()
                print("对话历史已清空！")
                continue
            elif user_input.lower() == 'models':
                models = assistant.get_available_models()
                print(f"可用模型: {models}")
                continue
            elif user_input.lower() == 'info':
                info = assistant.get_current_model_info()
                print(f"当前模型信息: {info}")
                continue
            elif user_input.lower().startswith('switch '):
                model_id = user_input[7:].strip()
                if assistant.switch_model(model_id):
                    print(f"已切换到模型: {model_id}")
                else:
                    print(f"切换模型失败: {model_id}")
                continue
            elif user_input.lower() == 'history':
                history = assistant.get_conversation_history()
                if history:
                    print("\n=== 对话历史 ===")
                    for i, msg in enumerate(history, 1):
                        role = "用户" if msg["role"] == "user" else "助手"
                        content = msg["content"][:100] + "..." if len(msg["content"]) > 100 else msg["content"]
                        print(f"{i}. {role}: {content}")
                    print("=" * 20)
                else:
                    print("暂无对话历史")
                continue
            elif user_input.lower() == 'count':
                count = len(assistant.get_conversation_history())
                print(f"当前记忆的消息数量: {count}/{assistant.max_memory}")
                continue
            elif not user_input:
                print("请输入有效的消息")
                continue
                
            # 进行对话
            response = assistant.chat(user_input)
            if response:
                print(f"\nAI回复: {response}")
                
                # 显示当前记忆状态
                current_count = len(assistant.get_conversation_history())
                if current_count >= assistant.max_memory * 0.8:  # 当记忆达到80%时提醒
                    print(f"\n[提示: 当前记忆 {current_count}/{assistant.max_memory} 条消息，接近上限]")
            else:
                print("抱歉，获取回复失败，请检查模型服务是否正常运行。")
    else:
        print("无法连接到任何模型，请检查配置和服务状态")