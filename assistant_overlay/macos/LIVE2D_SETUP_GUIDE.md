# Live2D 配置指南

## 方案一：手动配置（推荐，最安全）

### 步骤 1：清理项目

```bash
cd macos

# 备份项目文件
cp Runner.xcodeproj/project.pbxproj Runner.xcodeproj/project.pbxproj.backup

# 移除可能导致冲突的 Samples 目录（如果存在）
rm -rf Live2DRenderer/CubismSDK/Samples
```

### 步骤 2：在 Xcode 中操作

1. **打开项目**
   ```bash
   open Runner.xcworkspace
   ```

2. **移除现有的 CubismSDK 引用（如果有）**
   - 在左侧项目导航器中，找到蓝色的 `CubismSDK` 或 `Live2DRenderer` 文件夹
   - 右键 → **Delete** → 选择 **Remove References**（不要选 Move to Trash）

3. **添加 Live2DRenderer 文件夹**
   - 右键 **Runner** → **Add Files to "Runner"**
   - 选择 `Live2DRenderer` 文件夹
   - 选项：
     - ❌ Copy items if needed（**不勾选**）
     - ✅ Create groups（**勾选**）
     - ✅ Add to targets: Runner（**勾选**）
   - 点击 **Add**

4. **只添加需要的库文件**
   - 在 Finder 中打开 `Live2DRenderer/CubismSDK/Core/lib/macos/`
   - 拖拽 `arm64/libLive2DCubismCore.a` 和 `x86_64/libLive2DCubismCore.a` 到 Xcode 的 Runner 下
   - 选项同上

### 步骤 3：配置 Build Settings

选中 **Runner** → **Build Settings**（搜索框输入）：

#### Header Search Paths
添加以下路径（点击 + 添加）：
```
$(PROJECT_DIR)/Live2DRenderer
$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/include
$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Framework/src
```

#### Library Search Paths
添加：
```
$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/lib/macos/arm64
$(PROJECT_DIR)/Live2DRenderer/CubismSDK/Core/lib/macos/x86_64
```

#### Other Linker Flags
添加：
```
-lLive2DCubismCore
```

#### Swift Compiler - General
- **Objective-C Bridging Header**: `Runner/Runner-Bridging-Header.h`

### 步骤 4：验证

运行编译：
```bash
flutter run
```

---

## 方案二：使用脚本（有风险，先备份）

### 前提条件

```bash
# 安装 xcodeproj gem
gem install xcodeproj
```

### 运行脚本

```bash
cd macos
chmod +x setup_live2d.sh
./setup_live2d.sh
```

如果脚本出错，恢复备份：
```bash
cp Runner.xcodeproj/project.pbxproj.backup Runner.xcodeproj/project.pbxproj
```

---

## 常见问题

### Q: 编译时出现 "file not found" 错误
检查 **Header Search Paths** 是否正确配置。

### Q: 链接错误 "library not found"
检查 **Library Search Paths** 和 **Other Linker Flags**。

### Q: "duplicate symbols" 或 "multiple commands produce"
说明有重复的文件引用。需要：
1. 在 Xcode 中移除所有 Live2D 相关文件
2. 重新按照步骤添加

### Q: Swift 编译器报错 "cannot find type 'Live2DRenderer'"
检查 **Bridging Header** 是否正确设置，并且头文件路径正确。

---

## 文件清单

必须存在的文件：
```
macos/Live2DRenderer/
├── Live2DRenderer.h
├── Live2DRenderer.mm
├── Live2DPlugin.swift
└── CubismSDK/
    ├── Core/
    │   ├── include/Live2DCubismCore.h
    │   └── lib/macos/
    │       ├── arm64/libLive2DCubismCore.a
    │       └── x86_64/libLive2DCubismCore.a
    └── Framework/
        └── src/
            └── (所有 .cpp 文件)
```

---

## 替代方案

如果 Live2D 集成太复杂，可以考虑：

1. **使用 flutter_3d_controller**：加载 GLB 格式的 3D 模型
2. **使用 Unity**：通过 flutter_unity_widget 嵌入
3. **使用原生 WebView**：加载 Live2D Web 版本

---

**建议**：先尝试手动配置方案一，这是最安全的方式。
