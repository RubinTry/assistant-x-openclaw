import Cocoa
import FlutterMacOS
import AVFoundation

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let controller = mainFlutterWindow?.contentViewController as? FlutterViewController

    if let controller = controller {
      let permissionChannel = FlutterMethodChannel(name: "com.assistant/permission",
                                                    binaryMessenger: controller.engine.binaryMessenger)

      permissionChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "requestMicrophonePermission" {
          self?.requestMicrophonePermission(result: result)
        } else if call.method == "checkMicrophonePermission" {
          self?.checkMicrophonePermission(result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    super.applicationDidFinishLaunching(aNotification)
  }

  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      DispatchQueue.main.async {
        result(granted)
      }
    }
  }

  private func checkMicrophonePermission(result: @escaping FlutterResult) {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    switch status {
    case .authorized:
      result("granted")
    case .denied:
      result("denied")
    case .notDetermined:
      result("undetermined")
    case .restricted:
      result("denied")
    @unknown default:
      result("unknown")
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}