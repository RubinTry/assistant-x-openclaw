import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

// VideoBridge
import '../util/video/video_helper.dart';
import '../video_bridge/video_bridge.dart';

// Macbear3D engine
import '../m3_internal.dart';

/// A texture that can be updated from an external source like a video stream or camera.
class M3ExternalTexture extends M3Texture {
  final dynamic source;
  bool isPlaying = false;
  GlobalKey? repaintKey;
  bool _isCapturing = false;
  bool _isNativeCodec = (PlatformInfo.isMacOS || PlatformInfo.isIOS);

  // shared memory for native bridge

  M3ExternalTexture(this.source, {bool? isUseNative}) : super(useMipmaps: false) {
    name = "external_texture";
    if (isUseNative != null) {
      _isNativeCodec = isUseNative && _isNativeCodec;
    }
    M3Log.i('M3ExternalTexture', 'isNativeCodec= $_isNativeCodec');
  }

  /// Constructor to initialize from a video asset path or network URL.
  M3ExternalTexture.videoAsset(String assetPath, {bool? isUseNative})
    : source = createVideoElement(assetPath),
      super(useMipmaps: false) {
    name = assetPath;
    if (isUseNative != null) {
      _isNativeCodec = isUseNative && _isNativeCodec;
    }
    M3Log.i('M3ExternalTexture', 'videoAsset: isNativeCodec= $_isNativeCodec');
  }

  @override
  dispose() {
    releaseNativeBridge();
    super.dispose();
  }

  /// Initialize and load a video asset or network URL texture natively if possible.
  static Future<M3ExternalTexture> createVideo(String assetPath, {bool? isUseNative}) async {
    final texture = M3ExternalTexture.videoAsset(assetPath, isUseNative: isUseNative);
    if (texture._isNativeCodec) {
      texture.isPlaying = await texture.initNativeBridge(assetPath);
      M3Log.i('M3ExternalTexture', 'source created= ${texture.isPlaying} for $assetPath');
    }
    return texture;
  }

  /// Initialize the native OES texture bridge.
  Future<bool> initNativeBridge(String assetPath) async {
    if (_isNativeCodec) {
      if (PlatformInfo.isMacOS || PlatformInfo.isIOS) {
        // Pass the native GL texture ID to the macOS/iOS side.
        isPlaying = await M3VideoBridge.registerSurface(textureId: glId, assetPath: assetPath);
        return isPlaying;
      }
    }
    return false;
  }

  /// Release the native OES texture bridge.
  Future<void> releaseNativeBridge() async {
    if (_isNativeCodec) {
      if (PlatformInfo.isMacOS || PlatformInfo.isIOS) {
        await M3VideoBridge.release(textureId: glId);
        isPlaying = false;
      }
    }
  }

  /// Update the texture from the source.
  /// This should be called every frame in the render loop.
  void update() {
    if (source == null) return;

    if (kIsWeb) {
      // Use the helper to handle WebGL overloads via JS interop where needed.
      bind();
      updateTextureFromVideo(gl, target, source);
    } else {
      // Native implementation:
      if (_isNativeCodec) {
        _updateTextureFromNative();
        return;
      }

      // If source is a ui.Image, we can use _loadTargetFromImage (inherited from M3Texture).
      if (source is ui.Image) {
        loadTargetFromImage(source as ui.Image);
      } else if (source is VideoPlayerController) {
        // Note: For VideoPlayerController on Native, we need a way to get the current frame.
        // As a starting point, the user can pass a ui.Image captured from the controller.
        // We could also integrate a custom platform-specific texture sharing here.
        _captureNativeFrame();
      }
    }
  }

  Future<void> _updateTextureFromNative() async {
    if (PlatformInfo.isMacOS || PlatformInfo.isIOS) {
      // Try to update the surface (Native side will try zero-copy first, then fallback to pixels)
      final bool success = await M3VideoBridge.updateSurface(textureId: glId);
      if (success) {
        return;
      }
    }

    if (PlatformInfo.isAndroid) {
      // Native OES texture is updated directly by the native side (e.g., SurfaceTexture).
      // We trigger the latching of the next frame here.
      await M3VideoBridge.updateSurface(textureId: glId);
      return;
    }
  }

  /// Capture a frame from the RepaintBoundary (Native fallback).
  ///
  /// Note: This method relies on [RenderRepaintBoundary.toImage], which requires
  /// the associated widget to be part of the active widget tree and painted.
  /// To perform "offscreen" capture, the widget should be positioned outside
  /// the visible area (e.g., using `Positioned(left: -2000)`) rather than
  /// using `Offstage` or `Visibility`, which would prevent painting.
  Future<void> _captureNativeFrame() async {
    if (_isCapturing || source is! VideoPlayerController || repaintKey == null) return;
    _isCapturing = true;

    try {
      final controller = source as VideoPlayerController;
      if (!controller.value.isInitialized) return;

      final boundary = repaintKey!.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final img = await boundary.toImage();
        loadTargetFromImage(img);
      }
    } catch (e) {
      // M3Log.e('M3ExternalTexture', 'capturing frame: $e');
    } finally {
      _isCapturing = false;
    }
  }

  /// Helper to create from a video element (Web only)
  static M3ExternalTexture createFromVideo(dynamic videoElement) {
    return M3ExternalTexture(videoElement);
  }

  /// Play the video.
  void play() {
    videoPlay(source);
    isPlaying = true;
    if (_isNativeCodec) {
      M3VideoBridge.play(textureId: glId);
    }
  }

  /// Pause the video.
  void pause() {
    videoPause(source);
    isPlaying = false;
    if (_isNativeCodec) {
      M3VideoBridge.pause(textureId: glId);
    }
  }

  /// Seek to a specific time.
  void seekTo(Duration duration) {
    videoSeekTo(source, duration);
    if (_isNativeCodec) {
      M3VideoBridge.seekTo(textureId: glId, seconds: duration.inMilliseconds / 1000.0);
    }
  }

  /// Get the duration of the video.
  Future<Duration?> getDuration() async {
    if (source == null) return null;

    if (kIsWeb) {
      // For Web, 'source' is an HTMLVideoElement.
      // We use a helper (implemented in the next step) to get the duration.
      final seconds = videoGetDuration(source);
      return Duration(milliseconds: (seconds * 1000).toInt());
    } else {
      if (_isNativeCodec) {
        final seconds = await M3VideoBridge.getDuration(textureId: glId);
        return Duration(milliseconds: (seconds * 1000).toInt());
      } else if (source is VideoPlayerController) {
        final controller = source as VideoPlayerController;
        return controller.value.duration;
      }
    }
    return null;
  }

  /// Get the current playback position.
  Future<Duration?> getPosition() async {
    if (source == null) return null;

    if (kIsWeb) {
      final seconds = videoGetPosition(source);
      return Duration(milliseconds: (seconds * 1000).toInt());
    } else {
      if (_isNativeCodec) {
        final seconds = await M3VideoBridge.getPosition(textureId: glId);
        return Duration(milliseconds: (seconds * 1000).toInt());
      } else if (source is VideoPlayerController) {
        final controller = source as VideoPlayerController;
        return controller.value.position;
      }
    }
    return null;
  }
}
