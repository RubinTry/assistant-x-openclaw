import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:typed_data';

dynamic createVideoElement(String src) {
  final video = web.document.createElement('video') as web.HTMLVideoElement;
  video.src = src;
  video.crossOrigin = 'anonymous';
  video.loop = true;
  video.muted = true;
  video.playsInline = true;
  video.play();
  return video;
}

web.HTMLCanvasElement? _offscreenCanvas;
web.CanvasRenderingContext2D? _offscreenCtx;

void updateTextureFromVideo(dynamic gl, int target, dynamic video) {
  if (gl == null || video == null) return;
  final v = video as web.HTMLVideoElement;
  if (v.videoWidth == 0 || v.videoHeight == 0) return;

  // Lazily create offscreen canvas
  _offscreenCanvas ??= web.document.createElement('canvas') as web.HTMLCanvasElement;
  if (_offscreenCanvas!.width != v.videoWidth || _offscreenCanvas!.height != v.videoHeight) {
    _offscreenCanvas!.width = v.videoWidth;
    _offscreenCanvas!.height = v.videoHeight;
    _offscreenCtx = _offscreenCanvas!.getContext('2d') as web.CanvasRenderingContext2D;
  }

  // Draw video frame to canvas and get pixels
  _offscreenCtx?.drawImage(v, 0, 0);
  final imageData = _offscreenCtx?.getImageData(0, 0, v.videoWidth, v.videoHeight);
  if (imageData == null) return;

  // WebGL constants
  const rgba = 0x1908; 
  const unsignedByte = 0x1401;
  
  final pixels = Uint8List.fromList(imageData.data.toDart); // Convert to flutter_angle array

  gl.texImage2D(
    target,
    0,
    rgba,
    v.videoWidth,
    v.videoHeight,
    0,
    rgba,
    unsignedByte,
    pixels,
  );
}

void videoPlay(dynamic source) {
  if (source != null) {
    (source as web.HTMLVideoElement).play();
  }
}

void videoPause(dynamic source) {
  if (source != null) {
    (source as web.HTMLVideoElement).pause();
  }
}

void videoSeekTo(dynamic source, Duration duration) {
  if (source != null) {
    (source as web.HTMLVideoElement).currentTime = duration.inMilliseconds / 1000.0;
  }
}

double videoGetDuration(dynamic source) {
  if (source != null) {
    return (source as web.HTMLVideoElement).duration.toDouble();
  }
  return 0.0;
}

double videoGetPosition(dynamic source) {
  if (source != null) {
    return (source as web.HTMLVideoElement).currentTime.toDouble();
  }
  return 0.0;
}
