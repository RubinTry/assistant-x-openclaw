import Cocoa
import FlutterMacOS

public class Live2dViewFactory: NSObject, FlutterPlatformViewFactory {
  private var registrar: FlutterPluginRegistrar

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  public func create(
    withViewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> NSView {
    let params = args as? [String: Any] ?? [:]
    let modelPath = params["modelPath"] as? String ?? ""
    let motion = params["motion"] as? String ?? "Idle"
    return Live2dMetalView(
      frame: NSRect(x: 0, y: 0, width: 300, height: 300),
      modelPath: modelPath,
      motion: motion
    )
  }

  public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}
