#!/usr/bin/env python3
"""
Live2D Xcode 项目自动配置脚本
"""

import os
import re
import uuid
import shutil
from datetime import datetime

PROJECT_PATH = "Runner.xcodeproj/project.pbxproj"
BACKUP_PATH = f"Runner.xcodeproj/project.pbxproj.backup.{datetime.now().strftime('%Y%m%d_%H%M%S')}"

# 需要添加的文件
FILES_TO_ADD = {
    'Live2DRenderer.h': {
        'path': 'Live2DRenderer/Live2DRenderer.h',
        'type': 'header',
    },
    'Live2DRenderer.mm': {
        'path': 'Live2DRenderer/Live2DRenderer.mm',
        'type': 'source',
    },
    'Live2DPlugin.swift': {
        'path': 'Live2DRenderer/Live2DPlugin.swift',
        'type': 'source',
    },
    'Live2DCubismCore.h': {
        'path': 'Live2DRenderer/CubismSDK/Core/include/Live2DCubismCore.h',
        'type': 'header',
    },
}

LIBRARIES_TO_ADD = {
    'libLive2DCubismCore.a (arm64)': {
        'path': 'Live2DRenderer/CubismSDK/Core/lib/macos/arm64/libLive2DCubismCore.a',
    },
    'libLive2DCubismCore.a (x86_64)': {
        'path': 'Live2DRenderer/CubismSDK/Core/lib/macos/x86_64/libLive2DCubismCore.a',
    },
}

def generate_uuid():
    """生成 Xcode 格式的 UUID"""
    return str(uuid.uuid4()).upper().replace('-', '')[:24]

def backup_project():
    """备份项目文件"""
    if not os.path.exists(BACKUP_PATH):
        shutil.copy2(PROJECT_PATH, BACKUP_PATH)
        print(f"📋 已备份到: {BACKUP_PATH}")

def clean_existing_references(content):
    """清理现有的 Live2D 和 CubismSDK 引用"""
    print("🧹 清理现有引用...")
    
    # 移除 CubismSDK 组定义（简化处理，移除整个组部分）
    # 这个正则比较危险，实际使用时要小心
    patterns = [
        r'\s+\w+ /\* CubismSDK \*/ = \{[^}]+\};',
        r'\s+\w+ /\* Live2DRenderer \*/ = \{[^}]+\};',
    ]
    
    for pattern in patterns:
        content = re.sub(pattern, '', content)
    
    return content

def add_file_references(content):
    """添加文件引用"""
    print("📁 添加文件引用...")
    
    file_refs = []
    build_files = []
    
    for name, info in FILES_TO_ADD.items():
        if not os.path.exists(info['path']):
            print(f"   ⚠️  跳过（不存在）: {name}")
            continue
        
        file_uuid = generate_uuid()
        build_uuid = generate_uuid()
        
        # 文件引用
        if info['type'] == 'header':
            ref = f"\t	{file_uuid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; name = {name}; path = {info['path']}; sourceTree = \"<group>\"; }};"
        else:
            ref = f"\t	{file_uuid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {'sourcecode.cpp.objcpp' if name.endswith('.mm') else 'sourcecode.swift'}; name = {name}; path = {info['path']}; sourceTree = \"<group>\"; }};"
        
        file_refs.append(ref)
        print(f"   + {name}")
    
    # 添加库文件引用
    for name, info in LIBRARIES_TO_ADD.items():
        if not os.path.exists(info['path']):
            print(f"   ⚠️  跳过（不存在）: {name}")
            continue
        
        file_uuid = generate_uuid()
        ref = f"\t	{file_uuid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = archive.ar; name = libLive2DCubismCore.a; path = {info['path']}; sourceTree = \"<group>\"; }};"
        file_refs.append(ref)
        print(f"   + {name}")
    
    return content

def update_build_settings(content):
    """更新构建设置"""
    print("⚙️  更新构建设置...")
    
    # 头文件搜索路径
    header_paths = [
        '$(PROJECT_DIR)/Live2DRenderer',
        '$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/include',
        '$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Framework/src',
    ]
    
    # 库搜索路径
    lib_paths = [
        '$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/lib/macos/arm64',
        '$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/lib/macos/x86_64',
    ]
    
    # 替换或添加 HEADER_SEARCH_PATHS
    for path in header_paths:
        if path not in content:
            # 在现有 HEADER_SEARCH_PATHS 中添加
            content = re.sub(
                r'(HEADER_SEARCH_PATHS = \(\s*\n)([^)]+)(\);)',
                rf'\1\2\t\t\t\t"{path}",\n\3',
                content
            )
    
    # 替换或添加 LIBRARY_SEARCH_PATHS
    for path in lib_paths:
        if path not in content:
            content = re.sub(
                r'(LIBRARY_SEARCH_PATHS = \(\s*\n)([^)]+)(\);)',
                rf'\1\2\t\t\t\t"{path}",\n\3',
                content
            )
    
    # 添加 OTHER_LDFLAGS
    if '-lLive2DCubismCore' not in content:
        content = re.sub(
            r'(OTHER_LDFLAGS = \(\s*\n)([^)]+)(\);)',
            rf'\1\2\t\t\t\t"-lLive2DCubismCore",\n\3',
            content
        )
    
    print("   ✅ 构建设置已更新")
    return content

def main():
    print("🚀 Live2D Xcode 项目配置")
    print("=" * 40)
    
    if not os.path.exists(PROJECT_PATH):
        print(f"❌ 错误: 找不到 {PROJECT_PATH}")
        return
    
    # 备份
    backup_project()
    
    # 读取项目文件
    with open(PROJECT_PATH, 'r') as f:
        content = f.read()
    
    # 处理
    content = clean_existing_references(content)
    content = add_file_references(content)
    content = update_build_settings(content)
    
    # 保存
    with open(PROJECT_PATH, 'w') as f:
        f.write(content)
    
    print("")
    print("✅ 配置完成！")
    print("")
    print("注意：此脚本为简化版本，可能需要手动调整：")
    print("  1. 在 Xcode 中检查文件是否正确添加")
    print("  2. 确保 Build Phases 包含新文件")
    print("  3. 检查 Build Settings 中的路径")
    print("")
    print("如果出现问题，可以从备份恢复：")
    print(f"  cp {BACKUP_PATH} {PROJECT_PATH}")

if __name__ == '__main__':
    main()
