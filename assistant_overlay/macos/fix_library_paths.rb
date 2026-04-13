#!/usr/bin/env ruby
require 'xcodeproj'

PROJECT_PATH = 'Runner.xcodeproj'
TARGET_NAME = 'Runner'

# 只保留 macOS 路径
ALLOWED_PATHS = [
  '$(inherited)',
  '$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/lib/macos/arm64',
  '$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/lib/macos/x86_64',
]

def fix_library_paths
  puts "🔧 修复 Library Search Paths..."
  
  project = Xcodeproj::Project.open(PROJECT_PATH)
  target = project.targets.find { |t| t.name == TARGET_NAME }
  
  unless target
    puts "❌ 找不到目标"
    return
  end
  
  target.build_configurations.each do |config|
    paths = config.build_settings['LIBRARY_SEARCH_PATHS'] || []
    paths = [paths] if paths.is_a?(String)
    
    # 过滤只保留 macOS 路径
    new_paths = paths.select { |p| ALLOWED_PATHS.any? { |allowed| p.include?(allowed) || p == '$(inherited)' } }
    
    # 确保包含 macOS 路径
    ALLOWED_PATHS.each do |allowed|
      unless new_paths.any? { |p| p.include?(allowed) }
        new_paths << allowed
      end
    end
    
    puts "   #{config.name}:"
    puts "     原路径数: #{paths.length}"
    puts "     新路径数: #{new_paths.length}"
    
    config.build_settings['LIBRARY_SEARCH_PATHS'] = new_paths
  end
  
  project.save
  puts "✅ Library Search Paths 已修复"
end

begin
  require 'xcodeproj'
  fix_library_paths
rescue LoadError
  puts "❌ 需要安装 xcodeproj: gem install xcodeproj"
end
