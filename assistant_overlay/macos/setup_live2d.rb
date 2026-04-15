#!/usr/bin/env ruby
# 自动配置 Xcode 项目以支持 Live2D

require 'xcodeproj'
require 'fileutils'

PROJECT_PATH = 'Runner.xcodeproj'
TARGET_NAME = 'Runner'

# Live2D 相关文件配置
LIVE2D_FILES = {
  # 头文件
  headers: [
    'Live2DRenderer/Live2DRenderer.h',
    'Live2DRenderer/CubismSDK/Core/include/Live2DCubismCore.h'
  ],
  # 实现文件
  sources: [
    'Live2DRenderer/Live2DRenderer.mm',
    'Live2DRenderer/Live2DPlugin.swift'
  ],
  # 库文件
  libraries: [
    'Live2DRenderer/CubismSDK/Core/lib/macos/arm64/libLive2DCubismCore.a',
    'Live2DRenderer/CubismSDK/Core/lib/macos/x86_64/libLive2DCubismCore.a'
  ]
}

# 需要添加的头文件搜索路径
HEADER_SEARCH_PATHS = [
  '$(PROJECT_DIR)/Live2DRenderer',
  '$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/include',
  '$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Framework/src'
]

# 库搜索路径
LIBRARY_SEARCH_PATHS = [
  '$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/lib/macos/arm64',
  '$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/lib/macos/x86_64'
]

def setup_live2d
  puts "🔧 正在配置 Live2D..."
  
  # 打开项目
  project = Xcodeproj::Project.open(PROJECT_PATH)
  target = project.targets.find { |t| t.name == TARGET_NAME }
  
  unless target
    puts "❌ 错误: 找不到目标 #{TARGET_NAME}"
    exit 1
  end
  
  # 1. 移除已存在的 CubismSDK 文件夹引用（如果有）
  remove_existing_cubism_sdk(project)
  
  # 2. 添加文件
  add_live2d_files(project, target)
  
  # 3. 配置构建设置
  configure_build_settings(target)
  
  # 4. 保存项目
  project.save
  puts "✅ Live2D 配置完成！"
end

def remove_existing_cubism_sdk(project)
  puts "🧹 清理已存在的 CubismSDK 引用..."
  
  # 查找并移除 CubismSDK 组
  project.main_group.groups.each do |group|
    if group.name == 'CubismSDK' || group.path == 'CubismSDK'
      puts "   移除组: #{group.name || group.path}"
      group.remove_from_project
    end
  end
  
  # 移除 main_group 下直接引用的 Live2DRenderer（如果存在）
  project.main_group.children.each do |child|
    if child.name == 'Live2DRenderer' || child.path == 'Live2DRenderer'
      puts "   移除引用: #{child.name || child.path}"
      child.remove_from_project
    end
  end
end

def add_live2d_files(project, target)
  puts "📁 添加 Live2D 文件..."
  
  # 创建或获取 Live2DRenderer 组
  live2d_group = project.main_group.find_subpath(File.join('Live2DRenderer'), true)
  live2d_group.name = 'Live2DRenderer'
  
  # 添加头文件
  puts "   添加头文件..."
  LIVE2D_FILES[:headers].each do |file_path|
    next unless File.exist?(file_path)
    file_ref = live2d_group.new_reference(file_path)
    file_ref.name = File.basename(file_path)
    puts "     + #{file_ref.name}"
  end
  
  # 添加源文件并加入编译
  puts "   添加源文件..."
  sources_build_phase = target.source_build_phase
  LIVE2D_FILES[:sources].each do |file_path|
    next unless File.exist?(file_path)
    file_ref = live2d_group.new_reference(file_path)
    file_ref.name = File.basename(file_path)
    sources_build_phase.add_file_reference(file_ref)
    puts "     + #{file_ref.name}"
  end
  
  # 添加库文件并链接
  puts "   添加库文件..."
  frameworks_build_phase = target.frameworks_build_phase
  LIVE2D_FILES[:libraries].each do |file_path|
    next unless File.exist?(file_path)
    file_ref = live2d_group.new_reference(file_path)
    file_ref.name = File.basename(file_path)
    frameworks_build_phase.add_file_reference(file_ref)
    puts "     + #{file_ref.name}"
  end
end

def configure_build_settings(target)
  puts "⚙️  配置构建设置..."
  
  ['Debug', 'Release', 'Profile'].each do |config_name|
    config = target.build_configurations.find { |c| c.name == config_name }
    next unless config
    
    settings = config.build_settings
    
    # 设置头文件搜索路径
    existing_paths = settings['HEADER_SEARCH_PATHS'] || ['$(inherited)']
    existing_paths = [existing_paths] if existing_paths.is_a?(String)
    
    HEADER_SEARCH_PATHS.each do |path|
      unless existing_paths.include?(path)
        existing_paths << path
      end
    end
    settings['HEADER_SEARCH_PATHS'] = existing_paths
    
    # 设置库搜索路径
    existing_lib_paths = settings['LIBRARY_SEARCH_PATHS'] || ['$(inherited)']
    existing_lib_paths = [existing_lib_paths] if existing_lib_paths.is_a?(String)
    
    LIBRARY_SEARCH_PATHS.each do |path|
      unless existing_lib_paths.include?(path)
        existing_lib_paths << path
      end
    end
    settings['LIBRARY_SEARCH_PATHS'] = existing_lib_paths
    
    # 设置链接标志
    existing_flags = settings['OTHER_LDFLAGS'] || ['$(inherited)']
    existing_flags = [existing_flags] if existing_flags.is_a?(String)
    
    unless existing_flags.include?('-lLive2DCubismCore')
      existing_flags << '-lLive2DCubismCore'
    end
    settings['OTHER_LDFLAGS'] = existing_flags
    
    # 设置桥接头文件
    settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'Runner/Runner-Bridging-Header.h'
    
    # C++ 标准库设置
    settings['CLANG_CXX_LIBRARY'] = 'libc++'
    settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++11'
    
    puts "   ✅ #{config_name} 配置完成"
  end
end

# 检查是否安装了 xcodeproj gem
begin
  require 'xcodeproj'
rescue LoadError
  puts "❌ 缺少 xcodeproj gem，正在安装..."
  system('gem install xcodeproj')
  puts "✅ 安装完成，请重新运行脚本"
  exit
end

# 运行配置
setup_live2d
