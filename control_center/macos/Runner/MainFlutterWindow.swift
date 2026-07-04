import Cocoa
import FlutterMacOS
import bitsdojo_window_macos

// 自定义标题栏：继承 BitsdojoWindow 并启用 BDW_CUSTOM_FRAME，隐藏系统原生标题栏，
// 由 Flutter 侧（window_titlebar.dart）自绘标题栏与窗口控制按钮。
class MainFlutterWindow: BitsdojoWindow {
  override func bitsdojo_window_configure() -> UInt {
    return BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
