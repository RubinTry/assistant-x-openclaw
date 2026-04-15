import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置 Flutter GPU 环境变量（必须在 Flutter 引擎启动前）
        setenv("FLTEnableFlutterGPU", "true", 1)

        NSApp.setActivationPolicy(.accessory)
        super.applicationDidFinishLaunching(notification)
    }
}
