import Cocoa
import FlutterMacOS
import bitsdojo_window_macos

// macOS：保留原生"红绿灯"窗口按钮，但隐藏标题栏 chrome（透明标题栏 + 内容全尺寸铺满）。
// 不用 BDW_CUSTOM_FRAME（那会连原生按钮一起去掉）；仅 HIDE_ON_STARTUP 消除首帧闪烁。
// Flutter 侧只画一条可拖拽的品牌条，左侧留出原生红绿灯的位置。
class MainFlutterWindow: BitsdojoWindow {
  override func bitsdojo_window_configure() -> UInt {
    return BDW_HIDE_ON_STARTUP
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 透明标题栏 + 全尺寸内容：原生红绿灯浮在内容左上角，标题栏背景/文字隐藏。
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
