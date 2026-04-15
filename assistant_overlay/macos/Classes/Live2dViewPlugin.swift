import Cocoa
import FlutterMacOS

public class Live2dViewPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let factory = Live2dViewFactory(registrar: registrar)
    registrar.register(factory, withId: "live2d_view")
  }
}
