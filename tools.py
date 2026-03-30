"""
语音助手工具模块
包含各种可供AI调用的工具函数
"""

import datetime
import json
import subprocess
import os
import platform
from typing import Dict, Any, List, Union


class ToolRegistry:
    """工具注册器，管理所有可用的工具"""
    
    def __init__(self):
        self.tools = {}
        self._register_default_tools()
    
    def _register_default_tools(self):
        """注册默认工具"""
        self.register_tool("get_current_time", get_current_time, get_current_time_schema())
        self.register_tool("get_installed_applications", get_installed_applications, get_installed_applications_schema())
        self.register_tool("control_application", control_application, control_application_schema())
        self.register_tool("control_volume", control_volume, control_volume_schema())
        self.register_tool("control_brightness", control_brightness, control_brightness_schema())
        self.register_tool("lock_screen", lock_screen, lock_screen_schema())
        self.register_tool("exit_activation", exit_activation, exit_activation_schema())
    
    def register_tool(self, name: str, func: callable, schema: dict):
        """注册一个工具"""
        self.tools[name] = {
            "function": func,
            "schema": schema
        }
    
    def get_tool_schemas(self) -> List[Dict]:
        """获取所有工具的schema定义"""
        return [tool["schema"] for tool in self.tools.values()]
    
    def execute_tool(self, tool_name: str, arguments: Dict[str, Any]) -> str:
        """执行指定的工具"""
        if tool_name not in self.tools:
            return f"未知工具: {tool_name}"
        
        try:
            func = self.tools[tool_name]["function"]
            return func(**arguments)
        except Exception as e:
            return f"工具执行错误: {str(e)}"


def get_current_time_schema() -> Dict:
    """获取当前时间工具的schema定义"""
    return {
        "type": "function",
        "function": {
            "name": "get_current_time",
            "description": "获取当前的日期和时间",
            "parameters": {
                "type": "object",
                "properties": {
                    "format": {
                        "type": "string",
                        "description": "时间格式，可选值：'datetime'（完整日期时间）、'time'（仅时间）、'date'（仅日期）",
                        "enum": ["datetime", "time", "date"]
                    }
                },
                "required": []
            }
        }
    }


def get_installed_applications_schema() -> Dict:
    """获取已安装应用程序工具的schema定义"""
    return {
        "type": "function",
        "function": {
            "name": "get_installed_applications",
            "description": "获取电脑中已安装的应用程序列表。当用户需要打开、切换、最小化、关闭窗口或退出某个软件时，必须先调用此工具获取可用的应用程序列表。",
            "parameters": {
                "type": "object",
                "properties": {
                    "include_system_apps": {
                        "type": "boolean",
                        "description": "是否包含系统应用程序，默认为false（仅显示用户应用）",
                        "default": False
                    },
                    "filter_keyword": {
                        "type": "string",
                        "description": "过滤关键词，仅返回包含此关键词的应用程序（可选）"
                    }
                },
                "required": []
            }
        }
    }


def control_application_schema() -> Dict:
    """应用程序控制工具的schema定义"""
    return {
        "type": "function",
        "function": {
            "name": "control_application",
            "description": "控制应用程序的各种操作，包括打开、切换、最小化、关闭窗口、退出进程等。工具会自动查找匹配的应用程序并执行操作。",
            "parameters": {
                "type": "object",
                "properties": {
                    "app_name": {
                        "type": "string",
                        "description": "应用程序名称，支持中文名称（如'微信'）或英文名称（如'WeChat'）"
                    },
                    "action": {
                        "type": "string",
                        "description": "要执行的操作",
                        "enum": ["open", "activate", "minimize", "close_window", "quit", "hide", "show"]
                    }
                },
                "required": ["app_name", "action"]
            }
        }
    }


def control_volume_schema() -> Dict:
    """音量控制工具的schema定义"""
    return {
        "type": "function",
        "function": {
            "name": "control_volume",
            "description": "控制电脑音量，支持设置音量、增加音量、减少音量、静音和取消静音操作",
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "description": "音量操作类型",
                        "enum": ["set", "increase", "decrease", "mute", "unmute", "get"]
                    },
                    "value": {
                        "type": "integer",
                        "description": "音量值（0-100），仅在action为'set'、'increase'或'decrease'时需要",
                        "minimum": 0,
                        "maximum": 100
                    }
                },
                "required": ["action"]
            }
        }
    }


def control_brightness_schema() -> Dict:
    """屏幕亮度控制工具的schema定义"""
    return {
        "type": "function",
        "function": {
            "name": "control_brightness",
            "description": "控制电脑主屏幕亮度，支持设置亮度、增加亮度、减少亮度操作",
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "description": "亮度操作类型",
                        "enum": ["set", "increase", "decrease", "get"]
                    },
                    "value": {
                        "type": "integer",
                        "description": "亮度值（0-100），仅在action为'set'、'increase'或'decrease'时需要",
                        "minimum": 0,
                        "maximum": 100
                    }
                },
                "required": ["action"]
            }
        }
    }


def lock_screen_schema() -> Dict:
    """锁屏工具的schema定义"""
    return {
        "type": "function",
        "function": {
            "name": "lock_screen",
            "description": "触发电脑锁屏操作，立即锁定屏幕并要求用户重新登录",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        }
    }


def exit_activation_schema() -> Dict:
    """退出激活状态工具的schema定义"""
    return {
        "type": "function",
        "function": {
            "name": "exit_activation",
            "description": "退出语音助手的激活状态，返回到需要唤醒词的待机模式。当用户明确表示要退出激活状态时调用此工具。",
            "parameters": {
                "type": "object",
                "properties": {
                    "reason": {
                        "type": "string",
                        "description": "退出激活的原因，如用户说了什么触发退出",
                        "default": "用户要求退出激活状态"
                    }
                },
                "required": []
            }
        }
    }


def get_current_time(format: str = "datetime") -> str:
    """
    获取当前时间
    
    Args:
        format: 时间格式类型
            - "time": 仅返回时间 (HH点MM分SS秒)
            - "date": 仅返回日期 (YYYY年MM月DD日)
            - "datetime": 返回完整日期时间 (默认)
            
    Returns:
        str: 格式化的时间字符串，适合语音播报
    """
    now = datetime.datetime.now()
    
    if format == "time":
        return now.strftime("现在是%H点%M分%S秒")
    elif format == "date":
        weekday = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"][now.weekday()]
        return now.strftime(f"今天是%Y年%m月%d日，{weekday}")
    else:  # datetime
        weekday = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"][now.weekday()]
        return now.strftime(f"现在是%Y年%m月%d日，{weekday}，%H点%M分")


def get_installed_applications(include_system_apps: bool = False, filter_keyword: str = None) -> str:
    """
    获取电脑中已安装的应用程序列表
    
    Args:
        include_system_apps: 是否包含系统应用程序，默认为False
        filter_keyword: 过滤关键词，仅返回包含此关键词的应用程序（支持中英文名称匹配）
        
    Returns:
        str: 应用程序列表的JSON字符串，包含应用名称和路径信息
    """
    system = platform.system()
    applications = []
    
    try:
        if system == "Darwin":  # macOS
            applications = _get_macos_applications(include_system_apps)
        elif system == "Windows":  # Windows
            # Windows实现暂时留空，后续可扩展
            return "Windows系统的应用程序获取功能暂未实现"
        else:
            return f"不支持的操作系统: {system}"
        
        # 应用过滤器（支持中英文名称匹配）
        if filter_keyword:
            applications = _filter_applications_by_keyword(applications, filter_keyword)
        
        # 格式化返回结果
        if not applications:
            return "未找到任何应用程序"
        
        result = {
            "system": system,
            "total_count": len(applications),
            "applications": applications
        }
        
        return json.dumps(result, ensure_ascii=False, indent=2)
        
    except Exception as e:
        return f"获取应用程序列表时发生错误: {str(e)}"


def _get_macos_applications(include_system_apps: bool = False) -> List[Dict[str, str]]:
    """
    获取macOS系统中的应用程序列表
    
    Args:
        include_system_apps: 是否包含系统应用程序
        
    Returns:
        List[Dict]: 应用程序信息列表
    """
    applications = []
    
    # 主要应用程序目录
    app_directories = ["/Applications"]
    
    # 如果包含系统应用，添加系统目录
    if include_system_apps:
        app_directories.extend([
            "/System/Applications",
            "/System/Library/CoreServices",
            os.path.expanduser("~/Applications")
        ])
    else:
        # 用户应用目录
        user_apps = os.path.expanduser("~/Applications")
        if os.path.exists(user_apps):
            app_directories.append(user_apps)
    
    # 扫描应用程序目录
    for directory in app_directories:
        if not os.path.exists(directory):
            continue
            
        try:
            for item in os.listdir(directory):
                if item.endswith('.app'):
                    app_path = os.path.join(directory, item)
                    app_name = item[:-4]  # 移除.app后缀
                    
                    # 获取应用程序的显示名称
                    display_name = _get_app_display_name(app_path) or app_name
                    
                    applications.append({
                        "name": display_name,
                        "bundle_name": app_name,
                        "path": app_path,
                        "directory": directory
                    })
        except PermissionError:
            # 跳过没有权限访问的目录
            continue
    
    # 按名称排序
    applications.sort(key=lambda x: x['name'].lower())
    
    return applications


def _get_app_display_name(app_path: str) -> str:
    """
    获取macOS应用程序的显示名称，优先获取本地化名称
    
    Args:
        app_path: 应用程序路径
        
    Returns:
        str: 应用程序显示名称
    """
    try:
        # 首先尝试获取本地化的显示名称
        localized_name = _get_localized_app_name(app_path)
        if localized_name:
            return localized_name
        
        # 如果没有本地化名称，使用Info.plist中的名称
        info_plist_path = os.path.join(app_path, "Contents", "Info.plist")
        if os.path.exists(info_plist_path):
            # 使用plutil命令读取plist文件
            result = subprocess.run(
                ["plutil", "-extract", "CFBundleDisplayName", "raw", info_plist_path],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
            
            # 如果没有CFBundleDisplayName，尝试CFBundleName
            result = subprocess.run(
                ["plutil", "-extract", "CFBundleName", "raw", info_plist_path],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
    except Exception:
        pass
    
    return None


def _get_localized_app_name(app_path: str) -> str:
    """
    获取应用程序的本地化显示名称
    
    Args:
        app_path: 应用程序路径
        
    Returns:
        str: 本地化显示名称，如果没有则返回None
    """
    try:
        # 检查中文本地化资源
        localized_dirs = [
            "zh-Hans.lproj",  # 简体中文
            "zh-Hant.lproj",  # 繁体中文
            "zh_CN.lproj",    # 中国大陆
            "zh.lproj"        # 中文通用
        ]
        
        resources_path = os.path.join(app_path, "Contents", "Resources")
        
        for lproj_dir in localized_dirs:
            lproj_path = os.path.join(resources_path, lproj_dir)
            if os.path.exists(lproj_path):
                # 查找InfoPlist.strings文件
                strings_file = os.path.join(lproj_path, "InfoPlist.strings")
                if os.path.exists(strings_file):
                    # 使用plutil读取本地化字符串
                    result = subprocess.run(
                        ["plutil", "-extract", "CFBundleDisplayName", "raw", strings_file],
                        capture_output=True,
                        text=True,
                        timeout=5
                    )
                    if result.returncode == 0 and result.stdout.strip():
                        return result.stdout.strip()
                    
                    # 如果没有CFBundleDisplayName，尝试CFBundleName
                    result = subprocess.run(
                        ["plutil", "-extract", "CFBundleName", "raw", strings_file],
                        capture_output=True,
                        text=True,
                        timeout=5
                    )
                    if result.returncode == 0 and result.stdout.strip():
                        return result.stdout.strip()
        
        # 如果没有找到本地化字符串文件，尝试使用系统API获取显示名称
        result = subprocess.run(
            ["mdls", "-name", "kMDItemDisplayName", "-raw", app_path],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0 and result.stdout.strip() and result.stdout.strip() != "(null)":
            return result.stdout.strip()
            
    except Exception:
        pass
    
    return None


def control_application(app_name: str, action: str) -> str:
    """
    控制应用程序的各种操作，自动查找匹配的应用程序
    
    Args:
        app_name: 应用程序名称，支持中文名称（如'微信'）或英文名称（如'WeChat'）
        action: 要执行的操作 (open, activate, minimize, close_window, quit, hide, show)
        
    Returns:
        str: 操作结果描述
    """
    try:
        # 首先获取应用程序列表，查找匹配的应用
        apps_result = get_installed_applications(filter_keyword=app_name)
        
        if "未找到任何应用程序" in apps_result:
            # 获取所有应用程序列表用于建议
            all_apps_result = get_installed_applications(include_system_apps=False)
            if "未找到任何应用程序" not in all_apps_result:
                return f"未找到名为 '{app_name}' 的应用程序。以下是可用的应用程序列表：\n{all_apps_result}"
            else:
                return f"未找到名为 '{app_name}' 的应用程序"
        
        # 解析应用程序信息
        import json
        apps_data = json.loads(apps_result)
        if not apps_data.get("applications"):
            return f"未找到名为 '{app_name}' 的应用程序"
        
        # 使用第一个匹配的应用程序
        target_app = apps_data["applications"][0]
        actual_name = target_app["name"]  # 使用实际的显示名称
        bundle_name = target_app["bundle_name"]  # bundle名称
        app_path = target_app["path"]  # 应用路径
        
        # 根据操作类型选择使用哪个名称
        if action == "open":
            # 打开操作优先使用路径，其次使用bundle名称
            cmd = ["open", app_path]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            return f"成功打开 {actual_name}" if result.returncode == 0 else f"打开 {actual_name} 失败: {result.stderr}"
            
        elif action in ["activate", "show"]:
            # 激活操作使用bundle名称
            cmd = ["osascript", "-e", f'tell application "{bundle_name}" to activate']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            return f"成功切换到 {actual_name}" if result.returncode == 0 else f"切换到 {actual_name} 失败: {result.stderr}"
            
        elif action == "minimize":
            # 最小化使用bundle名称
            cmd = ["osascript", "-e", f'tell application "{bundle_name}" to set miniaturized of every window to true']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            return f"成功最小化 {actual_name}" if result.returncode == 0 else f"最小化 {actual_name} 失败: {result.stderr}"
            
        elif action == "close_window":
            # 关闭窗口使用bundle名称
            cmd = ["osascript", "-e", f'tell application "{bundle_name}" to close every window']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            return f"成功关闭 {actual_name} 窗口" if result.returncode == 0 else f"关闭 {actual_name} 窗口失败: {result.stderr}"
            
        elif action == "quit":
            # 退出使用bundle名称
            cmd = ["osascript", "-e", f'tell application "{bundle_name}" to quit']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            return f"成功退出 {actual_name}" if result.returncode == 0 else f"退出 {actual_name} 失败: {result.stderr}"
            
        elif action == "hide":
            # 隐藏使用bundle名称
            cmd = ["osascript", "-e", f'tell application "System Events" to set visible of process "{bundle_name}" to false']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            return f"成功隐藏 {actual_name}" if result.returncode == 0 else f"隐藏 {actual_name} 失败: {result.stderr}"
            
        else:
            return f"不支持的操作: {action}"
            
    except Exception as e:
        return f"执行 {action} 操作时出错: {str(e)}"


def control_volume(action: str, value: int = None) -> str:
    """
    控制电脑音量
    
    Args:
        action: 音量操作类型 (set, increase, decrease, mute, unmute, get)
        value: 音量值（0-100），仅在set、increase或decrease时需要
        
    Returns:
        str: 操作结果描述
    """
    try:
        system = platform.system()
        
        if system == "Darwin":  # macOS
            if action == "get":
                # 获取当前音量
                result = subprocess.run(
                    ["osascript", "-e", "output volume of (get volume settings)"],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0:
                    current_volume = result.stdout.strip()
                    return f"当前音量为 {current_volume}%"
                else:
                    return "获取音量失败"
                    
            elif action == "set":
                if value is None:
                    return "设置音量需要指定音量值（0-100）"
                value = max(0, min(100, value))  # 限制范围
                result = subprocess.run(
                    ["osascript", "-e", f"set volume output volume {value}"],
                    capture_output=True, text=True, timeout=5
                )
                return f"音量已设置为 {value}%" if result.returncode == 0 else "设置音量失败"
                
            elif action == "increase":
                if value is None:
                    value = 10  # 默认增加10%
                # 先获取当前音量
                result = subprocess.run(
                    ["osascript", "-e", "output volume of (get volume settings)"],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0:
                    current_volume = int(result.stdout.strip())
                    new_volume = min(100, current_volume + value)
                    result = subprocess.run(
                        ["osascript", "-e", f"set volume output volume {new_volume}"],
                        capture_output=True, text=True, timeout=5
                    )
                    return f"音量已从 {current_volume}% 增加到 {new_volume}%" if result.returncode == 0 else "增加音量失败"
                else:
                    return "获取当前音量失败"
                    
            elif action == "decrease":
                if value is None:
                    value = 10  # 默认减少10%
                # 先获取当前音量
                result = subprocess.run(
                    ["osascript", "-e", "output volume of (get volume settings)"],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0:
                    current_volume = int(result.stdout.strip())
                    new_volume = max(0, current_volume - value)
                    result = subprocess.run(
                        ["osascript", "-e", f"set volume output volume {new_volume}"],
                        capture_output=True, text=True, timeout=5
                    )
                    return f"音量已从 {current_volume}% 减少到 {new_volume}%" if result.returncode == 0 else "减少音量失败"
                else:
                    return "获取当前音量失败"
                    
            elif action == "mute":
                result = subprocess.run(
                    ["osascript", "-e", "set volume with output muted"],
                    capture_output=True, text=True, timeout=5
                )
                return "已静音" if result.returncode == 0 else "静音失败"
                
            elif action == "unmute":
                result = subprocess.run(
                    ["osascript", "-e", "set volume without output muted"],
                    capture_output=True, text=True, timeout=5
                )
                return "已取消静音" if result.returncode == 0 else "取消静音失败"
                
            else:
                return f"不支持的音量操作: {action}"
                
        else:
            return f"暂不支持 {system} 系统的音量控制"
            
    except Exception as e:
        return f"音量控制出错: {str(e)}"


def control_brightness(action: str, value: int = None) -> str:
    """
    控制电脑主屏幕亮度
    
    Args:
        action: 亮度操作类型 (set, increase, decrease, get)
        value: 亮度值（0-100），仅在set、increase或decrease时需要
        
    Returns:
        str: 操作结果描述
    """
    try:
        system = platform.system()
        
        if system == "Darwin":  # macOS
            if action == "get":
                # 获取当前亮度
                result = subprocess.run(
                    ["brightness", "-l"],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0:
                    # 解析输出获取主显示器亮度
                    lines = result.stdout.strip().split('\n')
                    for line in lines:
                        if 'display 0:' in line:
                            brightness = float(line.split(':')[1].strip()) * 100
                            return f"当前屏幕亮度为 {brightness:.0f}%"
                    return "获取亮度失败"
                else:
                    # 如果没有brightness命令，尝试使用AppleScript
                    result = subprocess.run(
                        ["osascript", "-e", 'tell application "System Preferences" to get brightness of screen'],
                        capture_output=True, text=True, timeout=5
                    )
                    if result.returncode == 0:
                        brightness = float(result.stdout.strip()) * 100
                        return f"当前屏幕亮度为 {brightness:.0f}%"
                    else:
                        return "获取亮度失败，请确保已安装brightness命令行工具"
                        
            elif action == "set":
                if value is None:
                    return "设置亮度需要指定亮度值（0-100）"
                value = max(0, min(100, value))  # 限制范围
                brightness_value = value / 100.0  # 转换为0-1范围
                
                # 尝试使用brightness命令
                result = subprocess.run(
                    ["brightness", str(brightness_value)],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0:
                    return f"屏幕亮度已设置为 {value}%"
                else:
                    # 如果没有brightness命令，提示用户安装
                    return "设置亮度失败，请先安装brightness命令行工具：brew install brightness"
                    
            elif action in ["increase", "decrease"]:
                if value is None:
                    value = 10  # 默认调整10%
                    
                # 先获取当前亮度
                result = subprocess.run(
                    ["brightness", "-l"],
                    capture_output=True, text=True, timeout=5
                )
                if result.returncode == 0:
                    lines = result.stdout.strip().split('\n')
                    current_brightness = None
                    for line in lines:
                        if 'display 0:' in line:
                            current_brightness = float(line.split(':')[1].strip()) * 100
                            break
                    
                    if current_brightness is not None:
                        if action == "increase":
                            new_brightness = min(100, current_brightness + value)
                        else:  # decrease
                            new_brightness = max(0, current_brightness - value)
                        
                        brightness_value = new_brightness / 100.0
                        result = subprocess.run(
                            ["brightness", str(brightness_value)],
                            capture_output=True, text=True, timeout=5
                        )
                        if result.returncode == 0:
                            return f"屏幕亮度已从 {current_brightness:.0f}% 调整到 {new_brightness:.0f}%"
                        else:
                            return f"调整亮度失败"
                    else:
                        return "获取当前亮度失败"
                else:
                    return "获取当前亮度失败，请确保已安装brightness命令行工具"
                    
            else:
                return f"不支持的亮度操作: {action}"
                
        else:
            return f"暂不支持 {system} 系统的亮度控制"
            
    except Exception as e:
        return f"亮度控制出错: {str(e)}"


def lock_screen() -> str:
    """
    触发电脑锁屏操作
    
    Returns:
        str: 操作结果描述
    """
    try:
        system = platform.system()
        
        if system == "Darwin":  # macOS
            # 使用pmset命令锁屏
            result = subprocess.run(
                ["pmset", "displaysleepnow"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                return "屏幕已锁定"
            else:
                # 如果pmset失败，尝试使用AppleScript
                result = subprocess.run(
                    ["osascript", "-e", 'tell application "System Events" to keystroke "q" using {control down, command down}'],
                    capture_output=True, text=True, timeout=5
                )
                return "屏幕已锁定" if result.returncode == 0 else "锁屏失败"
                
        elif system == "Windows":
            # Windows锁屏命令
            result = subprocess.run(
                ["rundll32.exe", "user32.dll,LockWorkStation"],
                capture_output=True, text=True, timeout=5
            )
            return "屏幕已锁定" if result.returncode == 0 else "锁屏失败"
            
        elif system == "Linux":
            # Linux锁屏命令（尝试多种桌面环境）
            lock_commands = [
                ["gnome-screensaver-command", "-l"],  # GNOME
                ["xdg-screensaver", "lock"],          # 通用
                ["loginctl", "lock-session"],         # systemd
                ["dm-tool", "lock"]                   # LightDM
            ]
            
            for cmd in lock_commands:
                try:
                    result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
                    if result.returncode == 0:
                        return "屏幕已锁定"
                except FileNotFoundError:
                    continue
            
            return "锁屏失败，未找到合适的锁屏命令"
            
        else:
            return f"暂不支持 {system} 系统的锁屏功能"
            
    except Exception as e:
        return f"锁屏操作出错: {str(e)}"


def exit_activation(reason: str = "用户要求退出激活状态") -> str:
    """
    退出语音助手的激活状态，返回到需要唤醒词的待机模式
    
    Args:
        reason: 退出激活的原因
        
    Returns:
        str: 操作结果描述，包含特殊标记用于主程序识别
    """
    return f"EXIT_ACTIVATION:{reason}"


def _filter_applications_by_keyword(applications: List[Dict[str, str]], keyword: str) -> List[Dict[str, str]]:
    """
    根据关键词过滤应用程序列表，支持中英文名称匹配
    
    Args:
        applications: 应用程序列表
        keyword: 过滤关键词
        
    Returns:
        List[Dict]: 过滤后的应用程序列表
    """
    keyword_lower = keyword.lower()
    filtered_apps = []
    
    for app in applications:
        # 检查显示名称、bundle名称是否包含关键词
        if (keyword_lower in app['name'].lower() or 
            keyword_lower in app['bundle_name'].lower()):
            filtered_apps.append(app)
    
    return filtered_apps


# 创建全局工具注册器实例
tool_registry = ToolRegistry()


# 使用示例
if __name__ == "__main__":
    # 测试工具
    print("测试时间工具:")
    print(f"完整时间: {get_current_time()}")
    print(f"仅时间: {get_current_time('time')}")
    print(f"仅日期: {get_current_time('date')}")
    
    # 测试应用程序获取工具
    print("\n测试应用程序获取工具:")
    apps_result = get_installed_applications(include_system_apps=False, filter_keyword="微信")
    print(f"应用程序列表: {apps_result}")
    
    # 测试应用程序控制工具
    print("\n测试应用程序控制工具:")
    control_result = control_application("微信", "open")
    print(f"打开微信结果: {control_result}")
    
    # 测试工具注册器
    print("\n测试工具注册器:")
    schemas = tool_registry.get_tool_schemas()
    print(f"可用工具数量: {len(schemas)}")
    
    result = tool_registry.execute_tool("get_current_time", {"format": "time"})
    print(f"时间工具执行结果: {result}")
    
    result = tool_registry.execute_tool("get_installed_applications", {"filter_keyword": "微信"})
    print(f"应用程序获取工具执行结果: {result}")
    
    result = tool_registry.execute_tool("control_application", {"app_name": "微信", "action": "activate"})
    print(f"应用程序控制工具执行结果: {result}")
