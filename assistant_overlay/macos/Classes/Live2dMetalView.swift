import Cocoa
import SpriteKit
import FlutterMacOS

/// Live2D Metal 渲染视图（基于 SpriteKit 临时实现）
/// 注意：完整实现需要接入 Live2D Native SDK (C++)
public class Live2dMetalView: NSView {
  private var skView: SKView!
  private var scene: SKScene!
  private var bodyNode: SKSpriteNode!
  private var mouthNode: SKSpriteNode!
  private var currentMotion: String = "Idle"
  private var lipSyncValue: Double = 0.0

  init(frame: NSRect, modelPath: String, motion: String) {
    super.init(frame: frame)
    setupSpriteKit()
    loadModel(modelPath: modelPath)
    setMotion(motion)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupSpriteKit() {
    skView = SKView(frame: self.bounds)
    skView.autoresizingMask = [.width, .height]
    skView.allowsTransparency = true
    skView.backgroundColor = .clear
    self.addSubview(skView)

    scene = SKScene(size: self.bounds.size)
    scene.backgroundColor = .clear
    scene.scaleMode = .resizeFill
    skView.presentScene(scene)
  }

  private func loadModel(modelPath: String) {
    // TODO: 接入 Live2D Native SDK
    // 1. 初始化 Cubism Core
    // 2. 加载 .moc3 模型
    // 3. 设置 Metal 渲染管线
    // 4. 加载纹理
    // 5. 设置动画系统

    // 临时占位：显示占位图
    let placeholderText = SKLabelNode(text: "Live2D Loading...")
    placeholderText.fontSize = 20
    placeholderText.fontColor = .white
    placeholderText.position = CGPoint(x: frame.midX, y: frame.midY)
    scene.addChild(placeholderText)
  }

  public func setMotion(_ motion: String) {
    currentMotion = motion
    // TODO: 切换 Live2D 动画
    // Core::SetMotion(motion)
  }

  public func setLipSync(_ value: Double) {
    lipSyncValue = value
    // TODO: 驱动口型 Blend Shape
    // Core::SetParameterValue("PARAM_MOUTH_OPEN_Y", value)
  }

  public func dispose() {
    // TODO: 释放 Live2D 资源
    skView?.removeFromSuperview()
  }

  // MARK: - Platform Channel Methods

  public func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setMotion":
      if let motion = call.arguments as? String {
        setMotion(motion)
      }
      result(nil)
    case "setLipSync":
      if let args = call.arguments as? [String: Any],
         let value = args["value"] as? Double {
        setLipSync(value)
      }
      result(nil)
    case "dispose":
      dispose()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
