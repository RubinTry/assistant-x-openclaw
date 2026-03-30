#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
配置管理工具，用于管理大模型配置
"""

import json
import sys
from pathlib import Path
from model_manager import ModelManager

class ConfigManager:
    """配置管理工具"""
    
    def __init__(self, config_path: str = "app/big_models.json"):
        self.config_path = config_path
        self.model_manager = ModelManager(config_path)
    
    def list_models(self):
        """列出所有模型配置"""
        models = self.model_manager.config.get('models', {})
        print("\n=== 模型配置列表 ===")
        for model_id, config in models.items():
            status = "✓ 启用" if config.get('enabled', False) else "✗ 禁用"
            default = " (默认)" if model_id == self.model_manager.config.get('default_model') else ""
            print(f"{model_id}: {config.get('name', 'Unknown')} - {status}{default}")
            print(f"  URL: {config.get('base_url', 'N/A')}")
            print(f"  模型: {config.get('model_name', 'N/A')}")
            print()
    
    def enable_model(self, model_id: str):
        """启用模型"""
        if self.model_manager.enable_model(model_id):
            print(f"✓ 已启用模型: {model_id}")
        else:
            print(f"✗ 启用模型失败: {model_id}")
    
    def disable_model(self, model_id: str):
        """禁用模型"""
        if self.model_manager.disable_model(model_id):
            print(f"✓ 已禁用模型: {model_id}")
        else:
            print(f"✗ 禁用模型失败: {model_id}")
    
    def set_default_model(self, model_id: str):
        """设置默认模型"""
        if self.model_manager.set_default_model(model_id):
            print(f"✓ 已设置默认模型: {model_id}")
        else:
            print(f"✗ 设置默认模型失败: {model_id}")
    
    def add_model(self, model_id: str, name: str, base_url: str, api_key: str, model_name: str):
        """添加新模型配置"""
        models = self.model_manager.config.get('models', {})
        
        if model_id in models:
            print(f"✗ 模型ID已存在: {model_id}")
            return False
        
        new_model = {
            "name": name,
            "base_url": base_url,
            "api_key": api_key,
            "model_name": model_name,
            "enabled": True,
            "timeout": None,
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
        
        models[model_id] = new_model
        
        if self.model_manager._save_config():
            print(f"✓ 已添加模型: {model_id}")
            return True
        else:
            print(f"✗ 添加模型失败: {model_id}")
            return False
    
    def update_api_key(self, model_id: str, api_key: str):
        """更新模型的API密钥"""
        if self.model_manager.update_model_config(model_id, {'api_key': api_key}):
            print(f"✓ 已更新API密钥: {model_id}")
        else:
            print(f"✗ 更新API密钥失败: {model_id}")
    
    def show_global_settings(self):
        """显示全局设置"""
        settings = self.model_manager.get_global_settings()
        print("\n=== 全局设置 ===")
        for key, value in settings.items():
            print(f"{key}: {value}")
        print()
    
    def interactive_menu(self):
        """交互式菜单"""
        while True:
            print("\n=== 大模型配置管理工具 ===")
            print("1. 列出所有模型")
            print("2. 启用模型")
            print("3. 禁用模型")
            print("4. 设置默认模型")
            print("5. 添加新模型")
            print("6. 更新API密钥")
            print("7. 显示全局设置")
            print("8. 退出")
            
            choice = input("\n请选择操作 (1-8): ").strip()
            
            if choice == '1':
                self.list_models()
            elif choice == '2':
                model_id = input("请输入要启用的模型ID: ").strip()
                if model_id:
                    self.enable_model(model_id)
            elif choice == '3':
                model_id = input("请输入要禁用的模型ID: ").strip()
                if model_id:
                    self.disable_model(model_id)
            elif choice == '4':
                model_id = input("请输入要设为默认的模型ID: ").strip()
                if model_id:
                    self.set_default_model(model_id)
            elif choice == '5':
                print("\n添加新模型:")
                model_id = input("模型ID: ").strip()
                name = input("模型名称: ").strip()
                base_url = input("API地址: ").strip()
                api_key = input("API密钥: ").strip()
                model_name = input("模型名称(API): ").strip()
                
                if all([model_id, name, base_url, model_name]):
                    self.add_model(model_id, name, base_url, api_key, model_name)
                else:
                    print("✗ 请填写所有必需字段")
            elif choice == '6':
                model_id = input("请输入模型ID: ").strip()
                api_key = input("请输入新的API密钥: ").strip()
                if model_id and api_key:
                    self.update_api_key(model_id, api_key)
            elif choice == '7':
                self.show_global_settings()
            elif choice == '8':
                print("再见！")
                break
            else:
                print("无效选择，请重试")


def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description="大模型配置管理工具")
    parser.add_argument("--config", default="app/big_models.json", help="配置文件路径")
    parser.add_argument("--list", action="store_true", help="列出所有模型")
    parser.add_argument("--enable", help="启用指定模型")
    parser.add_argument("--disable", help="禁用指定模型")
    parser.add_argument("--default", help="设置默认模型")
    parser.add_argument("--interactive", action="store_true", help="启动交互式菜单")
    
    args = parser.parse_args()
    
    config_manager = ConfigManager(args.config)
    
    if args.list:
        config_manager.list_models()
    elif args.enable:
        config_manager.enable_model(args.enable)
    elif args.disable:
        config_manager.disable_model(args.disable)
    elif args.default:
        config_manager.set_default_model(args.default)
    elif args.interactive:
        config_manager.interactive_menu()
    else:
        # 默认启动交互式菜单
        config_manager.interactive_menu()


if __name__ == "__main__":
    main()