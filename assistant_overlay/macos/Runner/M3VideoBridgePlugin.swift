import Cocoa
import FlutterMacOS
import AVFoundation
import CoreVideo
import Metal

// EGL and ANGLE Constant Definitions
let EGL_METAL_TEXTURE_ANGLE: Int32 = 0x34A7
let EGL_NONE: Int32 = 0x3038
let GL_TEXTURE_2D: UInt32 = 0x0DE1
let GL_RGBA: UInt32 = 0x1908
let GL_UNSIGNED_BYTE: UInt32 = 0x1401
let GL_UNPACK_ROW_LENGTH: UInt32 = 0x0CF2

typealias EGLDisplay = UnsafeMutableRawPointer
typealias EGLContext = UnsafeMutableRawPointer
typealias EGLImage = UnsafeMutableRawPointer
typealias EGLClientBuffer = UnsafeMutableRawPointer

public class M3VideoBridgePlugin: NSObject, FlutterPlugin {
  private var registrar: FlutterPluginRegistrar?
  private var videoPlayers: [Int: M3VideoPlayer] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.macbear.angle_test/video", binaryMessenger: registrar.messenger)
    let instance = M3VideoBridgePlugin()
    instance.registrar = registrar
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "registerSurface":
      guard let args = call.arguments as? [String: Any],
            let textureId = args["textureId"] as? Int,
            let assetPath = args["assetPath"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId or assetPath", details: nil))
        return
      }
      
      setupVideo(textureId: textureId, assetPath: assetPath)
      result(true)
      
    case "updateSurface":
      guard let args = call.arguments as? [String: Any],
            let textureId = args["textureId"] as? Int else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
        return
      }
      autoreleasepool {
        let player = videoPlayers[textureId]
        var success = player?.updateGLTextureFromMetal(glTextureId: textureId) ?? false
        if !success {
          success = player?.updateGLTextureFromPixels(glTextureId: textureId) ?? false
        }
        result(success)
      }
      
    case "release":
      guard let args = call.arguments as? [String: Any],
            let textureId = args["textureId"] as? Int else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
        return
      }
      releaseVideo(textureId: textureId)
      result(true)
      
    case "play":
      guard let args = call.arguments as? [String: Any],
            let textureId = args["textureId"] as? Int else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
        return
      }
      videoPlayers[textureId]?.play()
      result(true)
      
    case "pause":
      guard let args = call.arguments as? [String: Any],
            let textureId = args["textureId"] as? Int else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
        return
      }
      videoPlayers[textureId]?.pause()
      result(true)
      
    case "seekTo":
      guard let args = call.arguments as? [String: Any],
            let textureId = args["textureId"] as? Int,
            let seconds = args["seconds"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId or seconds", details: nil))
        return
      }
      videoPlayers[textureId]?.seekTo(seconds)
      result(true)
      
    case "getDuration":
      guard let args = call.arguments as? [String: Any],
            let textureId = args["textureId"] as? Int else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
        return
      }
      result(videoPlayers[textureId]?.getDuration() ?? 0.0)
      
    case "getPosition":
      guard let args = call.arguments as? [String: Any],
            let textureId = args["textureId"] as? Int else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
        return
      }
      result(videoPlayers[textureId]?.getPosition() ?? 0.0)
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setupVideo(textureId: Int, assetPath: String) {
    releaseVideo(textureId: textureId)
    
    let url: URL
    let lowerPath = assetPath.lowercased()
    if lowerPath.hasPrefix("http://") || lowerPath.hasPrefix("https://") {
      guard let networkUrl = URL(string: assetPath) else {
        print("--- M3VideoBridge macOS: ERROR: Invalid network URL: \(assetPath)")
        return
      }
      url = networkUrl
      print("--- M3VideoBridge macOS (Network): \(url)")
    } else {
      let assetKey = registrar?.lookupKey(forAsset: assetPath) ?? assetPath
      // Construct absolute path from main bundle
      let bundlePath = Bundle.main.bundlePath
      let finalPath = (bundlePath as NSString).appendingPathComponent(assetKey)
      url = URL(fileURLWithPath: finalPath)
      print("--- M3VideoBridge macOS (Asset): \(finalPath)")
    }
    
    videoPlayers[textureId] = M3VideoPlayer(url: url)
  }

  private func releaseVideo(textureId: Int) {
    videoPlayers[textureId]?.release()
    videoPlayers.removeValue(forKey: textureId)
  }
}

class M3VideoPlayer: NSObject {
  var player: AVPlayer?
  var videoOutput: AVPlayerItemVideoOutput?
  var playerItem: AVPlayerItem?
  private var playToEndObserver: Any?
  
  // Metal & Texture Cache
  private var metalDevice: MTLDevice?
  private var textureCache: CVMetalTextureCache?
  private var texWidth: Int = 0
  private var texHeight: Int = 0
  
  // EGL Function Pointers
  private var eglGetCurrentDisplay: (@convention(c) () -> EGLDisplay?)?
  private var eglGetCurrentContext: (@convention(c) () -> EGLContext?)?
  private var eglCreateImageKHR: (@convention(c) (EGLDisplay?, EGLContext?, UInt32, EGLClientBuffer?, UnsafePointer<Int32>?) -> EGLImage?)?
  private var eglDestroyImageKHR: (@convention(c) (EGLDisplay?, EGLImage?) -> UInt32)?
  private var glEGLImageTargetTexture2DOES: (@convention(c) (UInt32, EGLImage?) -> Void)?
  private var glBindTexture: (@convention(c) (UInt32, UInt32) -> Void)?
  private var glTexImage2D: (@convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void)?
  private var glTexSubImage2D: (@convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void)?
  private var glPixelStorei: (@convention(c) (UInt32, Int32) -> Void)?
  private var eglGetError: (@convention(c) () -> Int32)?
  private var eglHandle: UnsafeMutableRawPointer?
  private var glesHandle: UnsafeMutableRawPointer?

  init(url: URL) {
    super.init()
    print("--- M3VideoBridge asset: \(url)")
    
    setupMetal()
    setupEGLFunctions()
    
    let playerItem = AVPlayerItem(url: url)
    self.playerItem = playerItem
    
    let pixBuffAttributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferMetalCompatibilityKey as String: true
    ]
    videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixBuffAttributes)
    playerItem.add(videoOutput!)
    
    player = AVPlayer(playerItem: playerItem)
    player?.actionAtItemEnd = .none
    player?.isMuted = true
    
    playToEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
      self?.player?.seek(to: .zero)
      self?.player?.play()
    }
    
    playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
    player?.play()
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    if keyPath == "status", let item = object as? AVPlayerItem {
      print("--- M3VideoBridge: PlayerItem status: \(item.status.rawValue)")
    } else {
      super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
  }

  private func setupMetal() {
    metalDevice = MTLCreateSystemDefaultDevice()
    if let device = metalDevice {
      CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
      print("--- M3VideoBridge: Metal device & TextureCache initialized")
    }
  }

  private func setupEGLFunctions() {
    if eglHandle == nil {
      eglHandle = dlopen("@rpath/libEGL.framework/libEGL", RTLD_NOW)
    }
    if glesHandle == nil {
      glesHandle = dlopen("@rpath/libGLESv2.framework/libGLESv2", RTLD_NOW)
    }
    
    guard let egl = eglHandle, let gles = glesHandle else {
      print("--- M3VideoBridge: ERROR: Failed to load ANGLE frameworks: libEGL: \(eglHandle != nil), libGLESv2: \(glesHandle != nil)")
      return
    }

    print("--- M3VideoBridge: ANGLE frameworks loaded successfully")
    
    eglGetCurrentDisplay = unsafeBitCast(dlsym(egl, "eglGetCurrentDisplay"), to: (@convention(c) () -> EGLDisplay?).self)
    eglGetCurrentContext = unsafeBitCast(dlsym(egl, "eglGetCurrentContext"), to: (@convention(c) () -> EGLContext?).self)
    eglCreateImageKHR = unsafeBitCast(dlsym(egl, "eglCreateImageKHR"), to: (@convention(c) (EGLDisplay?, EGLContext?, UInt32, EGLClientBuffer?, UnsafePointer<Int32>?) -> EGLImage?).self)
    eglDestroyImageKHR = unsafeBitCast(dlsym(egl, "eglDestroyImageKHR"), to: (@convention(c) (EGLDisplay?, EGLImage?) -> UInt32).self)
    glEGLImageTargetTexture2DOES = unsafeBitCast(dlsym(gles, "glEGLImageTargetTexture2DOES"), to: (@convention(c) (UInt32, EGLImage?) -> Void).self)
    glBindTexture = unsafeBitCast(dlsym(gles, "glBindTexture"), to: (@convention(c) (UInt32, UInt32) -> Void).self)
    glTexImage2D = unsafeBitCast(dlsym(gles, "glTexImage2D"), to: (@convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void).self)
    glTexSubImage2D = unsafeBitCast(dlsym(gles, "glTexSubImage2D"), to: (@convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void).self)
    glPixelStorei = unsafeBitCast(dlsym(gles, "glPixelStorei"), to: (@convention(c) (UInt32, Int32) -> Void).self)
    eglGetError = unsafeBitCast(dlsym(egl, "eglGetError"), to: (@convention(c) () -> Int32).self)
    
    let eglQueryString = unsafeBitCast(dlsym(egl, "eglQueryString"), to: (@convention(c) (EGLDisplay?, Int32) -> UnsafePointer<Int8>?)?.self)
    
    if eglCreateImageKHR != nil {
      print("--- M3VideoBridge: ANGLE EGL extensions functions loaded")
      if let display = eglGetCurrentDisplay?(), let query = eglQueryString {
        if let extensions = query(display, 0x3055 /* EGL_EXTENSIONS */) {
          let str = String(cString: extensions)
          if str.contains("EGL_ANGLE_metal_texture_client_buffer") {
            print("--- M3VideoBridge: Metal texture client buffer extension is SUPPORTED")
          } else {
            print("--- M3VideoBridge: WARNING: Metal texture client buffer extension NOT found in extensions string")
          }
        }
      }
    } else {
      print("--- M3VideoBridge: WARNING: ANGLE EGL extensions NOT found")
    }
  }

  func updateGLTextureFromMetal(glTextureId: Int) -> Bool {
    guard let output = videoOutput, 
          let playerItem = player?.currentItem,
          let cache = textureCache else {
      return false
    }

    if eglCreateImageKHR == nil || glEGLImageTargetTexture2DOES == nil {
      setupEGLFunctions()
      if eglCreateImageKHR == nil {
        print("--- M3VideoBridge: ERROR: EGL functions not loaded")
        return false 
      }
    }

    if playerItem.status != .readyToPlay { return false }

    let currentTime = playerItem.currentTime()
    // OPTIMIZATION: Only update if a new frame is actually available
    if !output.hasNewPixelBuffer(forItemTime: currentTime) {
      return true // Return success as we are reusing the previous frame mapping
    }

    guard let pixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
      return false
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    var cvMetalTexture: CVMetalTexture?
    let result = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault,
      cache,
      pixelBuffer,
      nil,
      .bgra8Unorm,
      width,
      height,
      0,
      &cvMetalTexture
    )

    if result == kCVReturnSuccess, let cvTexture = cvMetalTexture, let metalTexture = CVMetalTextureGetTexture(cvTexture) {
      guard let display = eglGetCurrentDisplay!() else {
        return false
      }
      
      let context: EGLContext? = nil // EGL_NO_CONTEXT
      
      // 1. Wrap MTLTexture into EGLImage
      let mtlTexturePtr = Unmanaged.passUnretained(metalTexture).toOpaque()
      let attribs: [Int32] = [EGL_NONE]
      
      let eglImage = eglCreateImageKHR!(display, context, UInt32(EGL_METAL_TEXTURE_ANGLE), mtlTexturePtr, attribs)
      if eglImage == nil {
        print("--- M3VideoBridge: ERROR: eglCreateImageKHR failed with error code: 0x\(String(eglGetError!(), radix: 16))")
        return false
      }

      // 2. Bind EGLImage to the GL texture
      print("--- M3VideoBridge: Binding texture \(glTextureId) with EGLImage")
      glBindTexture!(GL_TEXTURE_2D, UInt32(glTextureId))
      glEGLImageTargetTexture2DOES!(GL_TEXTURE_2D, eglImage)
      
      // 3. Cleanup EGLImage
      _ = eglDestroyImageKHR!(display, eglImage)
      
      return true
    } else {
      if result != kCVReturnSuccess {
        print("--- M3VideoBridge: ERROR: CVMetalTextureCacheCreateTextureFromImage failed: \(result)")
      } else {
        print("--- M3VideoBridge: ERROR: Failed to get MTLTexture from CVMetalTexture")
      }
    }

    return false
  }

  func updateGLTextureFromPixels(glTextureId: Int) -> Bool {
    guard let output = videoOutput, let playerItem = player?.currentItem else { return false }
    if playerItem.status != .readyToPlay { return false }
    
    if glTexImage2D == nil || glTexSubImage2D == nil || glPixelStorei == nil || glBindTexture == nil {
      print("--- M3VideoBridge: ERROR: GL functions not loaded for pixel update")
      return false
    }

    let currentTime = playerItem.currentTime()
    if !output.hasNewPixelBuffer(forItemTime: currentTime) {
      return true
    }

    guard let pixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
      return false
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else { return false }

    glBindTexture!(GL_TEXTURE_2D, UInt32(glTextureId))
    
    // Handle alignment/padding
    let bytesPerPixel = 4
    if bytesPerRow != width * bytesPerPixel {
      glPixelStorei!(GL_UNPACK_ROW_LENGTH, Int32(bytesPerRow / bytesPerPixel))
    } else {
      glPixelStorei!(GL_UNPACK_ROW_LENGTH, 0)
    }

    if width != texWidth || height != texHeight {
      print("--- M3VideoBridge: Resizing texture to \(width)x\(height)")
      glTexImage2D!(GL_TEXTURE_2D, 0, Int32(GL_RGBA), Int32(width), Int32(height), 0, GL_RGBA, GL_UNSIGNED_BYTE, address)
      texWidth = width
      texHeight = height
    } else {
      glTexSubImage2D!(GL_TEXTURE_2D, 0, 0, 0, Int32(width), Int32(height), GL_RGBA, GL_UNSIGNED_BYTE, address)
    }
    
    // Reset pixel store
    glPixelStorei!(GL_UNPACK_ROW_LENGTH, 0)

    return true
  }

  func getFrameData() -> [String: Any]? {
    // Keep legacy fallback for compatibility
    guard let output = videoOutput, let playerItem = player?.currentItem else { return nil }
    if playerItem.status != .readyToPlay { return nil }
    let currentTime = playerItem.currentTime()
    if let pixelBuffer = output.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
      return extractFrameData(pixelBuffer)
    }
    return nil
  }

  private func extractFrameData(_ pixelBuffer: CVPixelBuffer) -> [String: Any] {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [:] }
    
    let bytesPerPixel = 4
    let targetBytesPerRow = width * bytesPerPixel
    var data: Data

    if bytesPerRow == targetBytesPerRow {
      // No padding, easy copy
      data = Data(bytes: address, count: targetBytesPerRow * height)
    } else {
      // Compact row by row
      data = Data(capacity: targetBytesPerRow * height)
      for row in 0..<height {
        data.append(address.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self), count: targetBytesPerRow)
      }
    }
    
    return [
      "pixels": FlutterStandardTypedData(bytes: data),
      "width": Int(width),
      "height": Int(height)
    ]
  }

  func release() {
    player?.pause()
    if let item = playerItem {
      item.removeObserver(self, forKeyPath: "status")
    }
    if let observer = playToEndObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    playToEndObserver = nil
    playerItem = nil
    player = nil
    videoOutput = nil

    if let cache = textureCache {
      CVMetalTextureCacheFlush(cache, 0)
    }
    textureCache = nil
    
    if let handle = eglHandle {
      dlclose(handle)
      eglHandle = nil
    }
    if let handle = glesHandle {
      dlclose(handle)
      glesHandle = nil
    }
  }

  func play() {
    player?.play()
  }

  func pause() {
    player?.pause()
  }

  func seekTo(_ seconds: Double) {
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
  }

  func getDuration() -> Double {
    guard let item = player?.currentItem else { return 0.0 }
    let duration = item.duration
    return duration.isNumeric ? duration.seconds : 0.0
  }

  func getPosition() -> Double {
    guard let item = player?.currentItem else { return 0.0 }
    return item.currentTime().seconds
  }

  deinit {
    release()
  }
}