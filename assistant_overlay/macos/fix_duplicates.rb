#!/usr/bin/env ruby
require 'xcodeproj'

PROJECT_PATH = 'Runner.xcodeproj'
TARGET_NAME = 'Runner'

def fix_duplicates
  puts "🔧 修复重复文件引用..."
  
  project = Xcodeproj::Project.open(PROJECT_PATH)
  target = project.targets.find { |t| t.name == TARGET_NAME }
  
  unless target
    puts "❌ 找不到目标"
    return
  end
  
  # 1. 获取所有源文件引用
  source_files = {}
  project.files.each do |file|
    next unless file.path
    basename = File.basename(file.path)
    source_files[basename] ||= []
    source_files[basename] << file
  end
  
  # 2. 找到重复的并删除
  duplicates = source_files.select { |k, v| v.length > 1 }
  
  duplicates.each do |basename, files|
    puts "   发现重复: #{basename} (#{files.length} 个引用)"
    
    # 保留第一个，删除其他的
    files[1..-1].each do |dup_file|
      puts "     删除重复引用: #{dup_file.uuid}"
      
      # 从 build phases 中移除
      target.build_phases.each do |phase|
        phase.files.each do |build_file|
          if build_file.file_ref == dup_file
            puts "       从 #{phase.display_name} 移除"
            build_file.remove_from_project
          end
        end
      end
      
      # 从项目中移除文件引用
      dup_file.remove_from_project
    end
  end
  
  # 3. 保存
  project.save
  puts "✅ 修复完成"
end

begin
  require 'xcodeproj'
  fix_duplicates
rescue LoadError
  puts "❌ 需要安装 xcodeproj: gem install xcodeproj"
end
