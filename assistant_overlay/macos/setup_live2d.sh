#!/bin/bash
# Live2D 一键配置脚本

set -e

echo "🚀 Live2D 自动配置脚本"
echo "========================"

# 检查 Ruby
if ! command -v ruby &> /dev/null; then
    echo "❌ 错误: 需要安装 Ruby"
    exit 1
fi

# 安装 xcodeproj gem（如果需要）
if ! ruby -e "require 'xcodeproj'" 2>/dev/null; then
    echo "📦 安装 xcodeproj..."
    gem install xcodeproj --user-install
fi

# 1. 首先清理现有的 CubismSDK 引用（从 project.pbxproj 中删除）
echo "🧹 清理现有的 CubismSDK 引用..."

# 备份项目文件
if [ ! -f "Runner.xcodeproj/project.pbxproj.backup" ]; then
    cp Runner.xcodeproj/project.pbxproj Runner.xcodeproj/project.pbxproj.backup
    echo "   📋 已备份 project.pbxproj"
fi

# 删除可能导致重复文件引用的条目
ruby << 'RUBY_CODE'
require 'xcodeproj'

begin
  project = Xcodeproj::Project.open('Runner.xcodeproj')
  
  # 移除所有 CubismSDK 相关的组
  project.main_group.groups.each do |group|
    if group.name && (group.name.include?('CubismSDK') || group.name.include?('Live2DRenderer'))
      puts "   移除组: #{group.name}"
      group.remove_from_project
    end
  end
  
  # 移除 main_group 下的直接引用
  to_remove = []
  project.main_group.children.each do |child|
    if child.name && (child.name.include?('CubismSDK') || child.name.include?('Live2DRenderer'))
      to_remove << child
    end
  end
  
  to_remove.each do |child|
    puts "   移除引用: #{child.name}"
    child.remove_from_project
  end
  
  project.save
  puts "   ✅ 清理完成"
rescue => e
  puts "   ⚠️  清理时出错（可能已是干净状态）: #{e.message}"
end
RUBY_CODE

# 2. 运行 Ruby 配置脚本
echo ""
echo "🔧 配置 Live2D..."
ruby setup_live2d.rb

# 3. 验证配置
echo ""
echo "✅ 配置完成！"
echo ""
echo "请检查以下内容："
echo "  1. 打开 Runner.xcworkspace"
echo "  2. 检查 Build Settings 中的："
echo "     - HEADER_SEARCH_PATHS"
echo "     - LIBRARY_SEARCH_PATHS"
echo "     - OTHER_LDFLAGS"
echo "     - SWIFT_OBJC_BRIDGING_HEADER"
echo ""
echo "然后运行: flutter run"
